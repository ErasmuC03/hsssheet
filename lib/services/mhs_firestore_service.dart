import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../config/sheet_config.dart';
import '../models/mhs_record.dart';

class LockResult {
  final bool acquired;
  final String? lockedByEmail;
  final DateTime? expiresAt;

  const LockResult({
    required this.acquired,
    this.lockedByEmail,
    this.expiresAt,
  });
}

class MoveResult {
  final int moved;
  final int skippedLocked;
  final int skippedIncomplete;

  const MoveResult({
    required this.moved,
    required this.skippedLocked,
    required this.skippedIncomplete,
  });
}

class DemoSeedResult {
  final int created;
  final bool alreadyGenerated;

  const DemoSeedResult({
    required this.created,
    required this.alreadyGenerated,
  });
}

class MhsFirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _records =>
      _db.collection('mhs_records');

  /// Watches records for one sheet/tab.
  Stream<List<MhsRecord>> watchRecords(String sheetId) {
    return _records.where('sheet', isEqualTo: sheetId).snapshots().map(
          (snapshot) {
        final records = snapshot.docs.map(MhsRecord.fromDoc).toList();

        records.sort((a, b) {
          final aName = a.text('clientName').toLowerCase();
          final bName = b.text('clientName').toLowerCase();
          return aName.compareTo(bName);
        });

        return records;
      },
    );
  }

  /// Watches the audit/history subcollection for one record.
  Stream<List<Map<String, dynamic>>> watchHistory(String recordId) {
    return _records
        .doc(recordId)
        .collection('history')
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs.map((doc) {
        return {
          'id': doc.id,
          ...doc.data(),
        };
      }).toList();

      items.sort((a, b) {
        final aTime = a['timestamp'];
        final bTime = b['timestamp'];

        if (aTime is Timestamp && bTime is Timestamp) {
          return bTime.compareTo(aTime);
        }

        return 0;
      });

      return items;
    });
  }

  /// Creates a new record in the selected sheet.
  Future<void> createRecord({
    required SheetConfig config,
    required Map<String, dynamic> values,
    required User user,
  }) async {
    final ref = _records.doc();

    final data = {
      ...values,
      'sheet': config.id,
      'sourceSheet': null,
      'sourceSheetTitle': null,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': user.uid,
      'createdByEmail': user.email ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
      'updatedByEmail': user.email ?? '',
    };

    final batch = _db.batch();

    batch.set(ref, data);

    batch.set(ref.collection('history').doc(), {
      'action': 'created',
      'userId': user.uid,
      'userEmail': user.email ?? '',
      'timestamp': FieldValue.serverTimestamp(),
      'changes': data,
    });

    await batch.commit();
  }

  /// Attempts to lock a record before editing.
  ///
  /// If another user has the record locked and the lock has not expired,
  /// the current user cannot edit it.
  Future<LockResult> tryLockRecord({
    required String recordId,
    required User user,
  }) async {
    final ref = _records.doc(recordId);

    return _db.runTransaction<LockResult>((transaction) async {
      final snap = await transaction.get(ref);

      if (!snap.exists) {
        return const LockResult(acquired: false);
      }

      final data = snap.data() ?? {};

      final lockedBy = data['lockedBy']?.toString() ?? '';
      final lockedByEmail = data['lockedByEmail']?.toString() ?? '';

      DateTime? expiresAt;
      final rawExpiry = data['lockExpiresAt'];

      if (rawExpiry is Timestamp) {
        expiresAt = rawExpiry.toDate();
      }

      final isExpired =
          expiresAt == null || expiresAt.isBefore(DateTime.now());

      final canLock = lockedBy.isEmpty || lockedBy == user.uid || isExpired;

      if (!canLock) {
        return LockResult(
          acquired: false,
          lockedByEmail: lockedByEmail,
          expiresAt: expiresAt,
        );
      }

      transaction.update(ref, {
        'lockedBy': user.uid,
        'lockedByEmail': user.email ?? '',
        'lockedAt': FieldValue.serverTimestamp(),
        'lockExpiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(minutes: 10)),
        ),
      });

      return const LockResult(acquired: true);
    });
  }

  /// Releases a lock if the current user owns that lock.
  Future<void> releaseLock({
    required String recordId,
    required User user,
  }) async {
    final ref = _records.doc(recordId);

    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(ref);

      if (!snap.exists) return;

      final data = snap.data() ?? {};
      final lockedBy = data['lockedBy']?.toString() ?? '';

      if (lockedBy == user.uid) {
        transaction.update(ref, {
          'lockedBy': FieldValue.delete(),
          'lockedByEmail': FieldValue.delete(),
          'lockedAt': FieldValue.delete(),
          'lockExpiresAt': FieldValue.delete(),
        });
      }
    });
  }

  /// Updates a record, writes field-level history, and unlocks the record.
  Future<void> updateRecordAndUnlock({
    required String recordId,
    required Map<String, dynamic> values,
    required User user,
  }) async {
    final ref = _records.doc(recordId);

    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(ref);

      if (!snap.exists) {
        throw Exception('Record no longer exists.');
      }

      final before = snap.data() ?? {};

      final changes = <String, dynamic>{};

      for (final entry in values.entries) {
        final oldValue = before[entry.key]?.toString() ?? '';
        final newValue = entry.value?.toString() ?? '';

        if (oldValue != newValue) {
          changes[entry.key] = {
            'old': oldValue,
            'new': newValue,
          };
        }
      }

      final updateData = {
        ...values,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
        'updatedByEmail': user.email ?? '',
        'lockedBy': FieldValue.delete(),
        'lockedByEmail': FieldValue.delete(),
        'lockedAt': FieldValue.delete(),
        'lockExpiresAt': FieldValue.delete(),
      };

      transaction.update(ref, updateData);

      if (changes.isNotEmpty) {
        transaction.set(ref.collection('history').doc(), {
          'action': 'edited',
          'userId': user.uid,
          'userEmail': user.email ?? '',
          'timestamp': FieldValue.serverTimestamp(),
          'changes': changes,
        });
      }
    });
  }

  /// Updates a single field on a record without touching the lock or other fields.
  /// Writes a history entry only when the value actually changes.
  Future<void> quickUpdateField({
    required String recordId,
    required String fieldKey,
    required String value,
    required User user,
  }) async {
    final ref = _records.doc(recordId);

    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      if (!snap.exists) throw Exception('Record not found.');

      final before = snap.data() ?? {};
      final oldValue = before[fieldKey]?.toString() ?? '';

      if (oldValue == value) return; // No change – skip write

      transaction.update(ref, {
        fieldKey: value,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
        'updatedByEmail': user.email ?? '',
      });

      transaction.set(ref.collection('history').doc(), {
        'action': 'inline_edit',
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'changes': {
          fieldKey: {'old': oldValue, 'new': value},
        },
      });
    });
  }

  /// Moves completed records from the current active sheet into the completed tab.
  ///
  /// Paed/CNS uses:
  /// qUploadedToGenieDate
  ///
  /// Clin Psych/SW/ASD uses:
  /// qUploadedToCdisDate
  Future<MoveResult> moveCompletedRecords({
    required SheetConfig config,
    required User user,
  }) async {
    final completedField = config.completedField;

    if (completedField == null) {
      return const MoveResult(
        moved: 0,
        skippedLocked: 0,
        skippedIncomplete: 0,
      );
    }

    final snapshot = await _records.where('sheet', isEqualTo: config.id).get();

    int moved = 0;
    int skippedLocked = 0;
    int skippedIncomplete = 0;

    for (final doc in snapshot.docs) {
      final result = await _db.runTransaction<String>((transaction) async {
        final ref = _records.doc(doc.id);
        final fresh = await transaction.get(ref);

        if (!fresh.exists) return 'missing';

        final data = fresh.data() ?? {};

        final completedValue = data[completedField]?.toString().trim() ?? '';

        if (completedValue.isEmpty) {
          return 'incomplete';
        }

        final lockedBy = data['lockedBy']?.toString() ?? '';
        final lockedByEmail = data['lockedByEmail']?.toString() ?? '';

        DateTime? expiresAt;
        final rawExpiry = data['lockExpiresAt'];

        if (rawExpiry is Timestamp) {
          expiresAt = rawExpiry.toDate();
        }

        final lockExpired =
            expiresAt == null || expiresAt.isBefore(DateTime.now());

        final lockedByOther =
            lockedBy.isNotEmpty && lockedBy != user.uid && !lockExpired;

        if (lockedByOther) {
          return 'locked:$lockedByEmail';
        }

        transaction.update(ref, {
          'sheet': 'completed',
          'sourceSheet': config.id,
          'sourceSheetTitle': config.title,
          'completedMovedAt': FieldValue.serverTimestamp(),
          'completedMovedBy': user.uid,
          'completedMovedByEmail': user.email ?? '',
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': user.uid,
          'updatedByEmail': user.email ?? '',
          'lockedBy': FieldValue.delete(),
          'lockedByEmail': FieldValue.delete(),
          'lockedAt': FieldValue.delete(),
          'lockExpiresAt': FieldValue.delete(),
        });

        transaction.set(ref.collection('history').doc(), {
          'action': 'moved_to_completed',
          'fromSheet': config.id,
          'toSheet': 'completed',
          'completedField': completedField,
          'completedValue': completedValue,
          'userId': user.uid,
          'userEmail': user.email ?? '',
          'timestamp': FieldValue.serverTimestamp(),
        });

        return 'moved';
      });

      if (result == 'moved') {
        moved++;
      } else if (result == 'incomplete') {
        skippedIncomplete++;
      } else if (result.startsWith('locked')) {
        skippedLocked++;
      }
    }

    return MoveResult(
      moved: moved,
      skippedLocked: skippedLocked,
      skippedIncomplete: skippedIncomplete,
    );
  }

  /// Generates fake/de-identified demo data once.
  ///
  /// It checks whether demo records already exist.
  /// If they exist, it will not create duplicates.
  Future<DemoSeedResult> generateDemoDataOnce({
    required User user,
  }) async {
    final existing = await _records
        .where('isDemoData', isEqualTo: true)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      return const DemoSeedResult(
        created: 0,
        alreadyGenerated: true,
      );
    }

    final batch = _db.batch();
    final batchId = DateTime.now().millisecondsSinceEpoch.toString();

    final nowData = {
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': user.uid,
      'createdByEmail': user.email ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
      'updatedByEmail': user.email ?? '',
      'isDemoData': true,
      'demoBatchId': batchId,
    };

    final List<Map<String, dynamic>> demoRecords = [
      {
        'sheet': 'paed_cns',
        'clientName': 'Demo, Amelia',
        'clientDob': '2017-03-14',
        'umrn': 'D-100001',
        'localCdsCatchmentSite': 'Midland',
        'paediatricianClinic': 'Paed-CNS Review Clinic',
        'questionnairePlatform': 'WPS',
        'questionnaireType': 'Conners 4',
        'completedBy': 'Parent',
        'genieSmsSentDate': '2026-04-01',
        'questionnaireDueDate': '2026-04-29',
        'qUploadedToGenieDate': '2026-05-02',
        'followUpReminderDate': '',
        'removeIfNotReceivedDate': '',
        'notifyPaedDate': '',
      },
      {
        'sheet': 'paed_cns',
        'clientName': 'Demo, Noah',
        'clientDob': '2016-11-08',
        'umrn': 'D-100002',
        'localCdsCatchmentSite': 'Armadale',
        'paediatricianClinic': 'Paediatrician Review',
        'questionnairePlatform': 'Paper',
        'questionnaireType': 'RMOC Assessment',
        'completedBy': 'Teacher',
        'genieSmsSentDate': '2026-04-03',
        'questionnaireDueDate': '2026-05-01',
        'qUploadedToGenieDate': '',
        'followUpReminderDate': '2026-05-03',
        'removeIfNotReceivedDate': '2026-05-31',
        'notifyPaedDate': '',
      },
      {
        'sheet': 'paed_cns',
        'clientName': 'Demo, Isla',
        'clientDob': '2018-07-21',
        'umrn': 'D-100003',
        'localCdsCatchmentSite': 'Cannington',
        'paediatricianClinic': 'Paed-CNS Rv Clinic',
        'questionnairePlatform': 'WPS',
        'questionnaireType': 'ASD Questionnaire',
        'completedBy': 'Parent / Teacher',
        'genieSmsSentDate': '2026-04-05',
        'questionnaireDueDate': '2026-05-03',
        'qUploadedToGenieDate': '',
        'followUpReminderDate': '',
        'removeIfNotReceivedDate': '',
        'notifyPaedDate': '',
      },
      {
        'sheet': 'paed_cns',
        'clientName': 'Demo, Oliver',
        'clientDob': '2015-09-02',
        'umrn': 'D-100004',
        'localCdsCatchmentSite': 'Fremantle',
        'paediatricianClinic': 'Paed Clinic',
        'questionnairePlatform': 'Genie SMS',
        'questionnaireType': 'Behaviour Questionnaire',
        'completedBy': 'Parent',
        'genieSmsSentDate': '2026-03-20',
        'questionnaireDueDate': '2026-04-17',
        'qUploadedToGenieDate': '2026-04-18',
        'followUpReminderDate': '',
        'removeIfNotReceivedDate': '',
        'notifyPaedDate': '',
      },
      {
        'sheet': 'clinpsych_sw_asd',
        'clientName': 'Demo, Mia',
        'clientDob': '2014-02-19',
        'umrn': 'D-200001',
        'cpAsd': 'ASD',
        'requestorName': 'Demo Requestor A',
        'questionnairePlatform': 'WPS',
        'questionnaireType': 'ASD Admin Questionnaire',
        'completedBy': 'Parent',
        'optusSmsSentDate': '2026-04-02',
        'questionnaireDueDate': '2026-04-30',
        'qUploadedToCdisDate': '2026-05-01',
        'followUpReminderDate': '',
        'removeIfNotReceivedDate': '',
        'additionalInfo': 'Completed and ready to move.',
      },
      {
        'sheet': 'clinpsych_sw_asd',
        'clientName': 'Demo, Leo',
        'clientDob': '2013-12-01',
        'umrn': 'D-200002',
        'cpAsd': 'CP',
        'requestorName': 'Demo Requestor B',
        'questionnairePlatform': 'Optus SMS',
        'questionnaireType': 'CP Follow-up Questionnaire',
        'completedBy': 'Parent / carer',
        'optusSmsSentDate': '2026-04-04',
        'questionnaireDueDate': '2026-05-02',
        'qUploadedToCdisDate': '',
        'followUpReminderDate': '2026-05-04',
        'removeIfNotReceivedDate': '2026-06-01',
        'additionalInfo': 'Awaiting return.',
      },
      {
        'sheet': 'clinpsych_sw_asd',
        'clientName': 'Demo, Ava',
        'clientDob': '2017-06-11',
        'umrn': 'D-200003',
        'cpAsd': 'SW',
        'requestorName': 'Demo Requestor C',
        'questionnairePlatform': 'Paper',
        'questionnaireType': 'Social Work Questionnaire',
        'completedBy': 'Teacher',
        'optusSmsSentDate': '2026-04-08',
        'questionnaireDueDate': '2026-05-06',
        'qUploadedToCdisDate': '',
        'followUpReminderDate': '',
        'removeIfNotReceivedDate': '',
        'additionalInfo': 'Paper copy sent.',
      },
      {
        'sheet': 'clinpsych_sw_asd',
        'clientName': 'Demo, Ethan',
        'clientDob': '2012-10-27',
        'umrn': 'D-200004',
        'cpAsd': 'ASD',
        'requestorName': 'Demo Requestor D',
        'questionnairePlatform': 'WPS',
        'questionnaireType': 'Conners 4',
        'completedBy': 'Parent / Teacher',
        'optusSmsSentDate': '2026-03-28',
        'questionnaireDueDate': '2026-04-25',
        'qUploadedToCdisDate': '2026-04-26',
        'followUpReminderDate': '',
        'removeIfNotReceivedDate': '',
        'additionalInfo': 'Completed.',
      },
    ];

    for (final record in demoRecords) {
      final ref = _records.doc();

      final data = {
        ...record,
        ...nowData,
        'sourceSheet': null,
        'sourceSheetTitle': null,
      };

      batch.set(ref, data);

      batch.set(ref.collection('history').doc(), {
        'action': 'demo_data_created',
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'changes': data,
      });
    }

    await batch.commit();

    return DemoSeedResult(
      created: demoRecords.length,
      alreadyGenerated: false,
    );
  }
}
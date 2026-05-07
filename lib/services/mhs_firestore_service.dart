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

  /// Generates a batch of 100 demo records. Can be called multiple times —
  /// each call creates a new uniquely-labelled batch (B1, B2 …) so records
  /// from different runs are easy to tell apart in the UI.
  Future<DemoSeedResult> generateDemoDataOnce({
    required User user,
  }) async {
    // ── Determine batch number ──────────────────────────────────────────────
    // Use a high limit so we can correctly count batches even when earlier
    // ones each hold 100 records (100 records × 50 batches = 5 000).
    final existing = await _records
        .where('isDemoData', isEqualTo: true)
        .limit(5000)
        .get();
    final batchNumber = (existing.docs
                .map((d) => d.data()['demoBatchId']?.toString() ?? '')
                .toSet()
                .where((s) => s.isNotEmpty)
                .length) +
            1;
    final batchLabel = 'B$batchNumber';
    final batchId = DateTime.now().millisecondsSinceEpoch.toString();

    // ── Common metadata ────────────────────────────────────────────────────
    final commonData = <String, dynamic>{
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': user.uid,
      'createdByEmail': user.email ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
      'updatedByEmail': user.email ?? '',
      'isDemoData': true,
      'demoBatchId': batchId,
      'sourceSheet': null,
      'sourceSheetTitle': null,
    };

    // ── Date helpers ───────────────────────────────────────────────────────
    // Each batch shifts all dates back by one week so overdue patterns
    // vary between runs.
    final today = DateTime.now();
    final batchOffset = Duration(days: (batchNumber - 1) * 7);

    String fmt(DateTime dt) =>
        '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';

    /// Returns a date string shifted by the batch offset (earlier in the past).
    String sd(DateTime base) => fmt(base.subtract(batchOffset));

    // ── Data pools ────────────────────────────────────────────────────────
    const _firstNames = [
      'Amelia', 'Noah', 'Isla', 'Oliver', 'Charlotte', 'Liam', 'Mia', 'Leo',
      'Ava', 'Ethan', 'Sophie', 'Jackson', 'Chloe', 'Lucas', 'Harper',
      'Mason', 'Evelyn', 'Aiden', 'Abigail', 'Logan', 'Emily', 'James',
      'Elizabeth', 'Benjamin', 'Mila', 'Elijah', 'Luna', 'Alexander',
      'Scarlett', 'Sebastian', 'Aria', 'Jack', 'Grace', 'Owen', 'Henry',
      'Penelope', 'Samuel', 'Layla', 'Daniel', 'Riley', 'Matthew', 'Zoey',
      'Joseph', 'Nora', 'David', 'Lily', 'Carter', 'Eleanor', 'Wyatt',
      'Hannah', 'Julian', 'Lillian', 'Hudson', 'Addison', 'Grayson', 'Aubrey',
      'Lincoln', 'Ellie', 'Theodore', 'Stella', 'Ryan', 'Natalie', 'Angel',
      'Zoe', 'Hunter', 'Victoria', 'Adam', 'Savannah', 'Eli', 'Brooklyn',
      'Asher', 'Audrey', 'Nathan', 'Bella', 'Isaac', 'Claire', 'Dominic',
      'Skylar', 'Austin', 'Lucy', 'Levi', 'Paisley', 'Isaiah', 'Everly',
      'Andrew', 'Anna', 'Caleb', 'Caroline', 'Jordan', 'Genesis', 'Connor',
      'Aaliyah', 'Colton', 'Kennedy', 'Landon', 'Sadie', 'Tyler', 'Madeline',
      'Dylan', 'Aurora',
    ];

    const _lastNames = [
      'Smith', 'Jones', 'Williams', 'Taylor', 'Brown', 'Davies', 'Evans',
      'Wilson', 'Thomas', 'Roberts', 'Johnson', 'Lewis', 'Walker', 'Robinson',
      'Wood', 'Thompson', 'White', 'Watson', 'Jackson', 'Wright', 'Green',
      'Harris', 'Cooper', 'King', 'Lee', 'Martin', 'Clarke', 'James',
      'Morgan', 'Hughes', 'Edwards', 'Hill', 'Moore', 'Clark', 'Harrison',
      'Scott', 'Young', 'Morris', 'Hall', 'Ward', 'Turner', 'Collins',
      'Parker', 'Mitchell', 'Adams', 'Carter', 'Phillips', 'Campbell',
      'Anderson', 'Rivera',
    ];

    const _sites = [
      'Midland', 'Armadale', 'Cannington', 'Fremantle', 'Rockingham',
      'Joondalup', 'Mandurah', 'Bunbury', 'Geraldton', 'Albany',
    ];

    const _paedClinics = [
      'Paed-CNS Review Clinic', 'Paediatrician Review', 'Paed Clinic',
      'Paed-CNS Rv Clinic', 'Neurology Clinic', 'Developmental Paediatrics',
      'Community Paediatrics',
    ];

    const _platforms = ['WPS', 'Paper', 'Genie SMS', 'Optus SMS', 'Email'];

    const _paedQTypes = [
      'Conners 4', 'RMOC Assessment', 'ASD Questionnaire',
      'Behaviour Questionnaire', 'Developmental Assessment',
      'ADHD Rating Scale', 'SDQ', 'Vineland Adaptive Behaviour',
      'ABAS-3', 'BRIEF-2',
    ];

    const _cpQTypes = [
      'ASD Admin Questionnaire', 'CP Follow-up Questionnaire',
      'Social Work Questionnaire', 'Conners 4', 'ADOS-2 Parent Interview',
      'Autism Diagnostic Interview', 'SRS-2', 'SCQ', 'ABC', 'VABS-3',
    ];

    const _completedByOpts = [
      'Parent', 'Teacher', 'Parent / Teacher', 'Parent / carer',
      'Parent / carer / Teacher', 'Carer', 'Self',
    ];

    const _requestors = [
      'Dr A. Nguyen', 'Dr B. Patel', 'Dr C. Sharma', 'Dr D. Mitchell',
      'Dr E. Thompson', 'Dr F. Wilson', 'Dr G. Roberts', 'Dr H. Evans',
      'Dr I. Clarke', 'Dr J. Harrison',
    ];

    const _cpAsdTypes = ['ASD', 'CP', 'SW'];

    const _additionalInfos = [
      '', 'Awaiting return.', 'Follow-up sent. No response yet.',
      'Paper copy sent.', 'Completed and ready to move.',
      'Client contacted twice.', 'Extension requested.',
      'Partially completed — awaiting teacher section.',
      'Sent via alternative platform.', '',
    ];

    // ── Build 100 records ─────────────────────────────────────────────────
    // 0-54  → paed_cns (55 records)
    // 55-99 → clinpsych_sw_asd (45 records)
    final demoRecords = <Map<String, dynamic>>[];

    for (int i = 0; i < 100; i++) {
      // Unique name: pick first & last from pools using offset to avoid
      // the same pair repeating (stride by a prime to cycle differently).
      final first = _firstNames[i % _firstNames.length];
      final last = _lastNames[(i * 3) % _lastNames.length];
      final clientName = 'Demo, $first $last ($batchLabel)';

      // DOB: children aged 5–18, varied by index.
      final ageYears = 5 + (i % 14);
      final dobMonth = ((i * 3) % 12) + 1;
      final dobDay = ((i * 7) % 28) + 1;
      final dob = DateTime(today.year - ageYears, dobMonth, dobDay);

      // Sent date: 8–95 days ago (stride by 1.2 to spread evenly).
      final sentDaysAgo = 8 + ((i * 89) % 88); // 8..95
      final sentDate = today.subtract(Duration(days: sentDaysAgo));
      final dueDate = sentDate.add(const Duration(days: 28));

      // Status pattern (repeats every 10 records):
      // 0-3  completed  (40%)
      // 4-6  overdue    (30%)
      // 7-9  pending    (30%)
      final scenario = i % 10;
      final isCompleted = scenario < 4;
      final isOverdue = !isCompleted && scenario < 7;

      final uploadDate =
          isCompleted ? dueDate.add(Duration(days: (i % 5) + 1)) : null;
      final followUpDate =
          isOverdue ? dueDate.add(const Duration(days: 2)) : null;
      final removeDate =
          isOverdue ? dueDate.add(const Duration(days: 30)) : null;

      final platform = _platforms[i % _platforms.length];
      final completedBy = _completedByOpts[i % _completedByOpts.length];

      if (i < 55) {
        // ── Paed & CNS ───────────────────────────────────────────────────
        final umrn =
            'D-P${batchNumber.toString().padLeft(2, '0')}${(i + 1).toString().padLeft(3, '0')}';
        final notifyDate = (isCompleted && i % 3 == 0)
            ? sd(uploadDate!.add(const Duration(days: 2)))
            : '';

        demoRecords.add({
          'sheet': 'paed_cns',
          'clientName': clientName,
          'clientDob': fmt(dob),
          'umrn': umrn,
          'localCdsCatchmentSite': _sites[i % _sites.length],
          'paediatricianClinic': _paedClinics[i % _paedClinics.length],
          'questionnairePlatform': platform,
          'questionnaireType': _paedQTypes[i % _paedQTypes.length],
          'completedBy': completedBy,
          'genieSmsSentDate': sd(sentDate),
          'questionnaireDueDate': sd(dueDate),
          'qUploadedToGenieDate':
              uploadDate != null ? sd(uploadDate) : '',
          'followUpReminderDate':
              followUpDate != null ? sd(followUpDate) : '',
          'removeIfNotReceivedDate':
              removeDate != null ? sd(removeDate) : '',
          'notifyPaedDate': notifyDate,
        });
      } else {
        // ── Clin Psych / SW / ASD ────────────────────────────────────────
        final j = i - 55;
        final umrn =
            'D-C${batchNumber.toString().padLeft(2, '0')}${(j + 1).toString().padLeft(3, '0')}';

        demoRecords.add({
          'sheet': 'clinpsych_sw_asd',
          'clientName': clientName,
          'clientDob': fmt(dob),
          'umrn': umrn,
          'cpAsd': _cpAsdTypes[j % _cpAsdTypes.length],
          'requestorName': _requestors[j % _requestors.length],
          'questionnairePlatform': platform,
          'questionnaireType': _cpQTypes[j % _cpQTypes.length],
          'completedBy': completedBy,
          'optusSmsSentDate': sd(sentDate),
          'questionnaireDueDate': sd(dueDate),
          'qUploadedToCdisDate':
              uploadDate != null ? sd(uploadDate) : '',
          'followUpReminderDate':
              followUpDate != null ? sd(followUpDate) : '',
          'removeIfNotReceivedDate':
              removeDate != null ? sd(removeDate) : '',
          'additionalInfo': _additionalInfos[i % _additionalInfos.length],
        });
      }
    }

    // ── Write to Firestore ─────────────────────────────────────────────────
    // 100 records × 2 ops = 200 — well within the 500-op batch limit.
    final writeBatch = _db.batch();

    for (final record in demoRecords) {
      final ref = _records.doc();
      final data = {...record, ...commonData};
      writeBatch.set(ref, data);
      writeBatch.set(ref.collection('history').doc(), {
        'action': 'demo_data_created',
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'changes': data,
      });
    }

    await writeBatch.commit();

    return DemoSeedResult(
      created: demoRecords.length,
      alreadyGenerated: false,
    );
  }
}
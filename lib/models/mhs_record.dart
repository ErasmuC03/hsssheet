import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class MhsRecord {
  final String id;
  final Map<String, dynamic> data;

  MhsRecord({
    required this.id,
    required this.data,
  });

  factory MhsRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return MhsRecord(
      id: doc.id,
      data: doc.data() ?? {},
    );
  }

  String get sheet => data['sheet']?.toString() ?? '';

  String text(String key) {
    final value = data[key];

    if (value == null) return '';

    if (value is Timestamp) {
      return DateFormat('yyyy-MM-dd HH:mm').format(value.toDate());
    }

    return value.toString();
  }

  String get updatedByEmail => data['updatedByEmail']?.toString() ?? '';
  String get lockedBy => data['lockedBy']?.toString() ?? '';
  String get lockedByEmail => data['lockedByEmail']?.toString() ?? '';

  DateTime? get lockExpiresAt {
    final value = data['lockExpiresAt'];
    if (value is Timestamp) {
      return value.toDate();
    }
    return null;
  }

  bool isLockedByOther(String currentUserId) {
    if (lockedBy.isEmpty) return false;
    if (lockedBy == currentUserId) return false;

    final expires = lockExpiresAt;

    if (expires == null) return true;

    return expires.isAfter(DateTime.now());
  }

  bool get isLocked {
    if (lockedBy.isEmpty) return false;

    final expires = lockExpiresAt;

    if (expires == null) return true;

    return expires.isAfter(DateTime.now());
  }

  static String formatDateTime(dynamic value) {
    if (value == null) return '';

    if (value is Timestamp) {
      return DateFormat('yyyy-MM-dd HH:mm').format(value.toDate());
    }

    return value.toString();
  }
}
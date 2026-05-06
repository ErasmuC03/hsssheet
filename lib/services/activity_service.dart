import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ActivityService {
  static final ActivityService _instance = ActivityService._internal();
  factory ActivityService() => _instance;
  ActivityService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _activity =>
      _db.collection('user_activity');

  Future<void> _log(Map<String, dynamic> data) async {
    try {
      await _activity.add({
        ...data,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Never crash the app over activity logging
    }
  }

  Future<void> logLogin(User user) => _log({
    'action': 'login',
    'userId': user.uid,
    'userEmail': user.email ?? '',
  });

  Future<void> logLogout(User user) => _log({
    'action': 'logout',
    'userId': user.uid,
    'userEmail': user.email ?? '',
  });

  Future<void> logRecordView(User user, String recordId, String clientName, String sheetId) =>
      _log({
        'action': 'record_view',
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'recordId': recordId,
        'clientName': clientName,
        'sheetId': sheetId,
      });

  Future<void> logRecordEdit(User user, String recordId, String clientName, String sheetId,
      Map<String, dynamic> changes) =>
      _log({
        'action': 'record_edit',
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'recordId': recordId,
        'clientName': clientName,
        'sheetId': sheetId,
        'changedFields': changes.keys.toList(),
      });

  /// Live stream of the latest [limit] activity events across all users.
  Stream<List<Map<String, dynamic>>> watchActivity({int limit = 200}) {
    return _activity
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  /// Stream filtered to a single user.
  Stream<List<Map<String, dynamic>>> watchUserActivity(String userId, {int limit = 100}) {
    return _activity
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }
}
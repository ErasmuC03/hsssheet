import 'package:cloud_firestore/cloud_firestore.dart';

/// Manages the list of allowed options for each dropdown field.
///
/// Firestore structure:
///   dropdown_options/{fieldKey}  →  { options: ['A', 'B', ...] }
class DropdownOptionsService {
  static final DropdownOptionsService _instance = DropdownOptionsService._internal();
  factory DropdownOptionsService() => _instance;
  DropdownOptionsService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('dropdown_options');

  // ── Read ────────────────────────────────────────────────────────────────────

  /// Returns the live list of options for [fieldKey].
  Stream<List<String>> watchOptions(String fieldKey) {
    return _col.doc(fieldKey).snapshots().map((snap) {
      if (!snap.exists) return <String>[];
      final raw = snap.data()?['options'];
      if (raw is List) return raw.map((e) => e.toString()).toList();
      return <String>[];
    });
  }

  /// One-shot fetch of options for [fieldKey].
  Future<List<String>> getOptions(String fieldKey) async {
    final snap = await _col.doc(fieldKey).get();
    if (!snap.exists) return [];
    final raw = snap.data()?['options'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }

  // ── Write ───────────────────────────────────────────────────────────────────

  Future<void> setOptions(String fieldKey, List<String> options) async {
    await _col.doc(fieldKey).set({'options': options});
  }

  Future<void> addOption(String fieldKey, String value) async {
    final current = await getOptions(fieldKey);
    if (current.contains(value)) return;
    await setOptions(fieldKey, [...current, value]);
  }

  Future<void> removeOption(String fieldKey, String value) async {
    final current = await getOptions(fieldKey);
    await setOptions(fieldKey, current.where((e) => e != value).toList());
  }

  Future<void> reorderOptions(String fieldKey, List<String> reordered) async {
    await setOptions(fieldKey, reordered);
  }

  // ── Seed defaults ───────────────────────────────────────────────────────────

  /// Call once on first run to populate sensible defaults if no docs exist yet.
  Future<void> seedDefaultsIfEmpty() async {
    final snap = await _col.limit(1).get();
    if (snap.docs.isNotEmpty) return; // already seeded

    final defaults = <String, List<String>>{
      'localCdsCatchmentSite': [
        'Armadale', 'Cannington', 'Fremantle', 'Midland', 'Rockingham',
      ],
      'paediatricianClinic': [
        'Paed-CNS Review Clinic',
        'Paed-CNS Rv Clinic',
        'Paediatrician Review',
        'Paed Clinic',
      ],
      'questionnairePlatform': [
        'WPS', 'Paper', 'Genie SMS', 'Optus SMS',
      ],
      'questionnaireType': [
        'Conners 4',
        'ASD Questionnaire',
        'ASD Admin Questionnaire',
        'RMOC Assessment',
        'Behaviour Questionnaire',
        'CP Follow-up Questionnaire',
        'Social Work Questionnaire',
      ],
      'completedBy': [
        'Parent',
        'Teacher',
        'Parent / Teacher',
        'Parent / carer',
        'Parent / carer / Teacher',
      ],
      'cpAsd': ['CP', 'ASD', 'SW'],
    };

    final batch = _db.batch();
    for (final entry in defaults.entries) {
      batch.set(_col.doc(entry.key), {'options': entry.value});
    }
    await batch.commit();
  }
}

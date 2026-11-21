import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// The list of companies (firms) plus the one currently selected in the app.
/// "all" means every company.
class Companies extends ChangeNotifier {
  Companies._();
  static final Companies instance = Companies._();

  List<Map<String, dynamic>> list = [];
  String selected = 'all';
  final Map<String, Map<String, dynamic>> _full = {};

  Map<String, dynamic>? byId(String? id) {
    for (final c in list) {
      if (c['_id'] == id) return c;
    }
    return null;
  }

  String nameOf(String? id) => byId(id)?['name'] ?? '';

  /// Company id to use as default for a new invoice.
  String? get defaultId => selected != 'all' && byId(selected) != null ? selected : (list.isNotEmpty ? list.first['_id'] : null);

  Future<void> load() async {
    final res = await Api.instance.get('/companies') as List;
    list = res.map((e) => Map<String, dynamic>.from(e)).toList();
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('company') ?? 'all';
    selected = saved == 'all' || byId(saved) != null ? saved : 'all';
    notifyListeners();
  }

  Future<void> ensure() async {
    if (list.isEmpty) await load();
  }

  Future<void> select(String id) async {
    selected = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('company', id);
    notifyListeners();
  }

  /// Company including logo and signature images, cached per update time.
  Future<Map<String, dynamic>> full(String id) async {
    final cached = _full[id];
    final listed = byId(id);
    if (cached != null && (listed == null || listed['updatedAt'] == cached['updatedAt'])) return cached;
    final res = Map<String, dynamic>.from(await Api.instance.get('/companies/$id'));
    _full[id] = res;
    return res;
  }

  void invalidate(String id) => _full.remove(id);
}

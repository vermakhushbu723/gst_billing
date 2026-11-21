import 'package:flutter/foundation.dart';

import 'api.dart';

/// Editable master lists (Settings → Masters), loaded from the server.
class Masters extends ChangeNotifier {
  Masters._();
  static final Masters instance = Masters._();

  List<String> units = ['KGS', 'NOS', 'PCS', 'BAGS', 'BOX', 'LTR', 'TON', 'MTR', 'DOZ', 'SET'];
  List<double> gstRates = [0, 0.25, 3, 5, 12, 18, 28, 40];
  List<String> paymentModes = ['Cash', 'UPI', 'Bank', 'Cheque', 'Card'];
  List<String> expenseCategories = ['Electricity', 'Salary', 'Rent', 'Diesel / Fuel', 'Transport', 'Repair & Maintenance', 'Packing Material', 'Water', 'Office', 'Other'];
  bool _loaded = false;

  void _apply(Map r) {
    List<String> s(dynamic v, List<String> d) => v is List && v.isNotEmpty ? v.map((e) => '$e').toList() : d;
    units = s(r['units'], units);
    paymentModes = s(r['paymentModes'], paymentModes);
    expenseCategories = s(r['expenseCategories'], expenseCategories);
    if (r['gstRates'] is List && (r['gstRates'] as List).isNotEmpty) {
      gstRates = (r['gstRates'] as List).map((e) => (e as num).toDouble()).toList();
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> load() async => _apply(Map.from(await Api.instance.get('/settings')));

  Future<void> ensure() async {
    if (_loaded) return;
    try {
      await load();
    } catch (_) {
      // keep defaults when offline
    }
  }

  Future<void> save(Map<String, dynamic> body) async => _apply(Map.from(await Api.instance.put('/settings', body)));
}

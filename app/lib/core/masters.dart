import 'package:flutter/foundation.dart';

import 'api.dart';
import 'companies.dart';

/// Editable master lists (Settings → Masters), per company, loaded from the server.
class Masters extends ChangeNotifier {
  Masters._();
  static final Masters instance = Masters._();

  static const _units = ['KGS', 'NOS', 'PCS', 'BAGS', 'BOX', 'LTR', 'TON', 'MTR', 'DOZ', 'SET'];
  static const _gst = [0.0, 0.25, 3.0, 5.0, 12.0, 18.0, 28.0, 40.0];
  static const _modes = ['Cash', 'UPI', 'Bank', 'Cheque', 'Card'];
  static const _expense = ['Electricity', 'Salary', 'Rent', 'Diesel / Fuel', 'Transport', 'Repair & Maintenance', 'Packing Material', 'Water', 'Office', 'Other'];
  static const _party = ['Retail', 'Wholesale', 'Hotel / Restaurant', 'Bar', 'Caterer', 'Distributor', 'Other'];

  List<String> units = [..._units];
  List<double> gstRates = [..._gst];
  List<String> paymentModes = [..._modes];
  List<String> expenseCategories = [..._expense];
  List<String> partyCategories = [..._party];
  bool _loaded = false;

  /// Which company's lists are shown ('all' = defaults for new companies).
  String get company => Companies.instance.selected;

  void _apply(Map r) {
    List<String> s(dynamic v, List<String> d) => v is List && v.isNotEmpty ? v.map((e) => '$e').toList() : [...d];
    units = s(r['units'], _units);
    paymentModes = s(r['paymentModes'], _modes);
    expenseCategories = s(r['expenseCategories'], _expense);
    partyCategories = s(r['partyCategories'], _party);
    gstRates = r['gstRates'] is List && (r['gstRates'] as List).isNotEmpty
        ? (r['gstRates'] as List).map((e) => (e as num).toDouble()).toList()
        : [..._gst];
    _loaded = true;
    notifyListeners();
  }

  Future<void> load() async => _apply(Map.from(await Api.instance.get('/settings', {'company': company})));

  Future<void> ensure() async {
    if (_loaded) return;
    try {
      await load();
    } catch (_) {
      // keep defaults when offline
    }
  }

  /// Called when the selected company changes or the user logs in/out.
  void reload() {
    _loaded = false;
    ensure();
  }

  Future<void> save(Map<String, dynamic> body) async =>
      _apply(Map.from(await Api.instance.put('/settings?company=${Uri.encodeQueryComponent(company)}', body)));
}

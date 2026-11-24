import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'companies.dart';

/// Which flow the app is in: with GST (tax invoices) or without GST (plain bills).
/// Lists, dashboard, reports, payments and new documents follow it.
class TaxMode extends ChangeNotifier {
  TaxMode._() {
    Companies.instance.addListener(_checkCompany);
  }
  static final TaxMode instance = TaxMode._();

  bool _gst = true;

  /// True = with GST.
  bool get gst => _gst && gstAllowed;

  /// The selected company is GST registered (always true for "All companies").
  bool get gstAllowed {
    final c = Companies.instance;
    if (c.selected == 'all') return true;
    return c.byId(c.selected)?['gstRegistered'] != false;
  }

  /// Value for the API's `gst` parameter.
  String get param => gst ? 'gst' : 'nongst';
  String get label => gst ? 'With GST' : 'Without GST';

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _gst = prefs.getString('taxMode') != 'nongst';
    } catch (_) {}
  }

  Future<void> set(bool gst) async {
    if (gst && !gstAllowed) return;
    if (_gst == gst) return;
    _gst = gst;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('taxMode', gst ? 'gst' : 'nongst');
    } catch (_) {}
  }

  bool _lastAllowed = true;
  void _checkCompany() {
    final allowed = gstAllowed;
    if (allowed != _lastAllowed) {
      _lastAllowed = allowed;
      notifyListeners();
    }
  }
}

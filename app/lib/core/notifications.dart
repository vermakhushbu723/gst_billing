import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';

/// In-app notifications: unread count (polled every minute) and the latest list.
class Notifications extends ChangeNotifier {
  Notifications._();
  static final Notifications instance = Notifications._();

  int unread = 0;
  List<Map<String, dynamic>> items = [];
  bool loading = false;
  String? error;
  Timer? _timer;

  void start() {
    _timer?.cancel();
    refreshCount();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => refreshCount());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    unread = 0;
    items = [];
    notifyListeners();
  }

  Future<void> refreshCount() async {
    try {
      final r = await Api.instance.get('/notifications/count');
      final n = (r['unread'] as num?)?.toInt() ?? 0;
      if (n != unread) {
        unread = n;
        notifyListeners();
      }
    } catch (_) {
      // offline or logged out: keep the last value
    }
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final r = await Api.instance.get('/notifications', {'limit': 50});
      items = List<Map<String, dynamic>>.from((r['items'] as List).map((e) => Map<String, dynamic>.from(e)));
      unread = (r['unread'] as num?)?.toInt() ?? 0;
    } catch (e) {
      error = '$e';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> markRead(Map<String, dynamic> n) async {
    if (n['read'] == true) return;
    n['read'] = true;
    if (unread > 0) unread--;
    notifyListeners();
    try {
      await Api.instance.post('/notifications/${n['_id']}/read');
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    for (final n in items) {
      n['read'] = true;
    }
    unread = 0;
    notifyListeners();
    try {
      await Api.instance.post('/notifications/read-all');
    } catch (_) {}
  }
}

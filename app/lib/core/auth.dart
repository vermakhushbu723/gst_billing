import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

class AuthState extends ChangeNotifier {
  AuthState._();
  static final AuthState instance = AuthState._();

  Map<String, dynamic>? user;
  bool get loggedIn => user != null;
  bool get isAdmin => user?['role'] == 'admin';

  /// Company login: tied to one company and sees only its data.
  String? get companyId => user?['company'] as String?;
  String? get companyName => user?['companyName'] as String?;
  bool get isCompanyLogin => companyId != null;

  /// Main admin of the whole software (all companies). Older cached users
  /// without the flag count as main admin when they have no company.
  bool get isSuperAdmin => isAdmin && !isCompanyLogin;

  String get roleLabel => isSuperAdmin ? 'Main Admin' : isAdmin ? 'Company Admin' : 'Staff';

  Future<void> init() async {
    Api.instance.onUnauthorized = () => logout();
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;
    Api.instance.token = token;
    final cached = prefs.getString('user');
    if (cached != null) {
      user = Map<String, dynamic>.from(jsonDecode(cached));
      // Open the app right away; confirm the session in the background.
      _refresh();
    } else {
      await _refresh();
    }
  }

  Future<void> _refresh() async {
    try {
      final res = await Api.instance.get('/auth/me');
      await _saveUser(Map<String, dynamic>.from(res['user']));
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) await logout();
      // Offline: keep the cached user so the app still opens.
    }
  }

  Future<void> login(String email, String password) async {
    final res = await Api.instance.post('/auth/login', {'email': email.trim(), 'password': password});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', res['token']);
    Api.instance.token = res['token'];
    await _saveUser(Map<String, dynamic>.from(res['user']));
  }

  Future<void> _saveUser(Map<String, dynamic> u) async {
    user = u;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(u));
    notifyListeners();
  }

  Future<void> updateProfile(String name, String phone) async {
    final res = await Api.instance.put('/auth/me', {'name': name, 'phone': phone});
    await _saveUser(Map<String, dynamic>.from(res['user']));
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user');
    Api.instance.token = null;
    user = null;
    notifyListeners();
  }
}

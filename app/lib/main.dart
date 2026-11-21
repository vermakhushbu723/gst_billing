import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'core/auth.dart';
import 'screens/companies_screen.dart';
import 'screens/company_form_screen.dart';
import 'screens/customer_detail_screen.dart';
import 'screens/customer_form_screen.dart';
import 'screens/customers_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/invoice_form_screen.dart';
import 'screens/invoice_view_screen.dart';
import 'screens/invoices_screen.dart';
import 'screens/login_screen.dart';
import 'screens/more_screen.dart';
import 'screens/product_form_screen.dart';
import 'screens/products_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shell.dart';
import 'screens/users_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await AuthState.instance.init();
  runApp(const GstBillingApp());
}

final _router = GoRouter(
  refreshListenable: AuthState.instance,
  redirect: (context, state) {
    final loggedIn = AuthState.instance.loggedIn;
    final atLogin = state.matchedLocation == '/login';
    if (!loggedIn && !atLogin) return '/login';
    if (loggedIn && atLogin) return '/';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    ShellRoute(
      builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
        GoRoute(
          path: '/invoices',
          builder: (_, _) => const InvoicesScreen(),
          routes: [
            GoRoute(
              path: 'new',
              builder: (_, s) => InvoiceFormScreen(
                customerId: s.uri.queryParameters['customer'],
                copyFromId: s.uri.queryParameters['from'],
              ),
            ),
            GoRoute(
              path: ':id',
              builder: (_, s) => InvoiceViewScreen(id: s.pathParameters['id']!),
              routes: [
                GoRoute(path: 'edit', builder: (_, s) => InvoiceFormScreen(invoiceId: s.pathParameters['id'])),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/customers',
          builder: (_, _) => const CustomersScreen(),
          routes: [
            GoRoute(path: 'new', builder: (_, _) => const CustomerFormScreen()),
            GoRoute(
              path: ':id',
              builder: (_, s) => CustomerDetailScreen(id: s.pathParameters['id']!),
              routes: [GoRoute(path: 'edit', builder: (_, s) => CustomerFormScreen(id: s.pathParameters['id']))],
            ),
          ],
        ),
        GoRoute(
          path: '/products',
          builder: (_, _) => const ProductsScreen(),
          routes: [
            GoRoute(path: 'new', builder: (_, _) => const ProductFormScreen()),
            GoRoute(path: ':id/edit', builder: (_, s) => ProductFormScreen(id: s.pathParameters['id'])),
          ],
        ),
        GoRoute(
          path: '/companies',
          builder: (_, _) => const CompaniesScreen(),
          routes: [
            GoRoute(path: 'new', builder: (_, _) => const CompanyFormScreen()),
            GoRoute(path: ':id/edit', builder: (_, s) => CompanyFormScreen(id: s.pathParameters['id'])),
          ],
        ),
        GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen()),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        GoRoute(path: '/users', builder: (_, _) => const UsersScreen()),
        GoRoute(path: '/more', builder: (_, _) => const MoreScreen()),
      ],
    ),
  ],
);

class GstBillingApp extends StatelessWidget {
  const GstBillingApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1F4E9C);
    final scheme = ColorScheme.fromSeed(seedColor: seed);
    return MaterialApp.router(
      title: 'GST Billing',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: ThemeData(
        colorScheme: scheme,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFFF4F6FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: false,
          titleTextStyle: TextStyle(fontFamily: 'Roboto', fontSize: 19, fontWeight: FontWeight.w700, color: Color(0xFF1B2333)),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE3E7EF))),
        ),
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFD5DAE3))),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    );
  }
}

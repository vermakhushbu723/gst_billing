import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'core/auth.dart';
import 'core/brand.dart';
import 'core/companies.dart';
import 'core/docs.dart';
import 'core/masters.dart';
import 'core/notifications.dart';
import 'screens/companies_screen.dart';
import 'screens/company_form_screen.dart';
import 'screens/customer_detail_screen.dart';
import 'screens/customer_form_screen.dart';
import 'screens/customers_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/expenses_screen.dart';
import 'screens/export_screen.dart';
import 'screens/invoice_form_screen.dart';
import 'screens/invoice_view_screen.dart';
import 'screens/invoices_screen.dart';
import 'screens/login_screen.dart';
import 'screens/masters_screen.dart';
import 'screens/more_screen.dart';
import 'screens/payments_screen.dart';
import 'screens/product_form_screen.dart';
import 'screens/products_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/share_screen.dart';
import 'screens/shell.dart';
import 'screens/users_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await AuthState.instance.init();
  // Fresh company list, masters and notifications whenever the logged-in user changes.
  void onAuth() {
    Companies.instance.reset();
    if (AuthState.instance.loggedIn) {
      Companies.instance.ensure().catchError((_) {}).whenComplete(Masters.instance.reload);
      Notifications.instance.start();
    } else {
      Notifications.instance.stop();
    }
  }

  onAuth();
  String? lastUser = AuthState.instance.user?['id']?.toString();
  AuthState.instance.addListener(() {
    final now = AuthState.instance.user?['id']?.toString();
    if (now != lastUser) {
      lastUser = now;
      onAuth();
    }
  });
  runApp(const GstBillingApp());
}

final _router = GoRouter(
  refreshListenable: AuthState.instance,
  redirect: (context, state) {
    if (state.matchedLocation.startsWith('/share/')) return null; // public invoice page
    final loggedIn = AuthState.instance.loggedIn;
    final atLogin = state.matchedLocation == '/login';
    if (!loggedIn && !atLogin) return '/login';
    if (loggedIn && atLogin) return '/';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    GoRoute(path: '/share/:token', builder: (_, s) => ShareScreen(token: s.pathParameters['token']!)),
    ShellRoute(
      builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
        GoRoute(
          path: '/invoices',
          builder: (_, _) => const InvoicesScreen(key: ValueKey('invoice')),
          routes: [
            GoRoute(
              path: 'new',
              builder: (_, s) => InvoiceFormScreen(
                customerId: s.uri.queryParameters['customer'],
                copyFromId: s.uri.queryParameters['from'],
                docType: DocType.of(s.uri.queryParameters['type']),
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
        GoRoute(path: '/quotations', builder: (_, _) => const InvoicesScreen(key: ValueKey('quotation'), docType: DocType.quotation)),
        GoRoute(path: '/challans', builder: (_, _) => const InvoicesScreen(key: ValueKey('challan'), docType: DocType.challan)),
        GoRoute(path: '/credit-notes', builder: (_, _) => const InvoicesScreen(key: ValueKey('credit_note'), docType: DocType.creditNote)),
        GoRoute(path: '/payments', builder: (_, _) => const PaymentsScreen()),
        GoRoute(path: '/expenses', builder: (_, _) => const ExpensesScreen()),
        GoRoute(path: '/masters', builder: (_, _) => const MastersScreen()),
        GoRoute(path: '/export', builder: (_, s) => ExportScreen(initialType: s.uri.queryParameters['type'])),
        GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen()),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        GoRoute(path: '/users', builder: (_, s) => UsersScreen(company: s.uri.queryParameters['company'])),
        GoRoute(path: '/more', builder: (_, _) => const MoreScreen()),
      ],
    ),
  ],
);

class GstBillingApp extends StatelessWidget {
  const GstBillingApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: Brand.teal).copyWith(
      primary: Brand.teal,
      onPrimary: Colors.white,
      primaryContainer: Brand.tealLight,
      onPrimaryContainer: Brand.tealDark,
      secondary: Brand.gold,
      onSecondary: Brand.navy,
      secondaryContainer: Brand.goldLight,
      onSecondaryContainer: Brand.navy,
      tertiary: Brand.navy,
      onSurface: Brand.navy,
      surfaceTint: Colors.transparent,
    );
    return MaterialApp.router(
      title: 'mybillwill — GST Billing',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: ThemeData(
        colorScheme: scheme,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: Brand.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Brand.navy,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          shape: Border(bottom: BorderSide(color: Brand.border)),
          centerTitle: false,
          titleTextStyle: TextStyle(fontFamily: 'Roboto', fontSize: 19, fontWeight: FontWeight.w700, color: Brand.navy),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Brand.border)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Brand.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Brand.teal, width: 1.6)),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Brand.gold,
          foregroundColor: Brand.navy,
        ),
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: Brand.goldLight,
          iconTheme: WidgetStateProperty.resolveWith(
            (s) => IconThemeData(color: s.contains(WidgetState.selected) ? Brand.teal : Brand.slate),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (s) => TextStyle(
              fontSize: 12,
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? Brand.teal : Brand.slate,
            ),
          ),
        ),
        navigationRailTheme: const NavigationRailThemeData(
          indicatorColor: Brand.goldLight,
          selectedIconTheme: IconThemeData(color: Brand.teal),
          unselectedIconTheme: IconThemeData(color: Brand.slate),
          selectedLabelTextStyle: TextStyle(color: Brand.teal, fontWeight: FontWeight.w700),
          unselectedLabelTextStyle: TextStyle(color: Brand.slate),
        ),
        chipTheme: ChipThemeData(
          selectedColor: Brand.tealLight,
          checkmarkColor: Brand.teal,
          side: const BorderSide(color: Brand.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: Brand.teal),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: Brand.teal,
            foregroundColor: Colors.white,
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

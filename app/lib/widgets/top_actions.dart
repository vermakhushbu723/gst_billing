import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth.dart';
import '../core/brand.dart';
import '../core/notifications.dart';
import 'common.dart';

/// Right side of every top bar: notification bell + profile menu.
List<Widget> topActions() => const [NotificationBell(), SizedBox(width: 4), ProfileMenu(), SizedBox(width: 12)];

String timeAgo(dynamic iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  if (diff.inDays < 7) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final n = Notifications.instance;
    return ListenableBuilder(
      listenable: n,
      builder: (context, _) => IconButton(
        tooltip: 'Notifications',
        onPressed: () => _open(context),
        icon: Badge(
          isLabelVisible: n.unread > 0,
          backgroundColor: Colors.red.shade600,
          label: Text(n.unread > 99 ? '99+' : '${n.unread}'),
          child: Icon(n.unread > 0 ? Icons.notifications_active_outlined : Icons.notifications_none, color: Brand.navy),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    Notifications.instance.load();
    final wide = MediaQuery.sizeOf(context).width >= 700;
    showDialog(
      context: context,
      barrierColor: Colors.black12,
      builder: (ctx) => Dialog(
        alignment: wide ? Alignment.topRight : Alignment.topCenter,
        insetPadding: EdgeInsets.only(top: 60, right: 12, left: wide ? 0 : 12, bottom: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: SizedBox(width: wide ? 420 : double.infinity, height: 560, child: _Panel(outer: context)),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.outer});
  final BuildContext outer;

  static (IconData, Color) _style(Map n) => switch ('${n['type']}') {
        'payment' => (Icons.payments_outlined, Colors.green.shade700),
        'overdue' => (Icons.warning_amber_rounded, Colors.red.shade700),
        'due_soon' => (Icons.schedule, Colors.orange.shade800),
        'quotation_expired' => (Icons.event_busy_outlined, Colors.orange.shade800),
        'quotation' => (Icons.request_quote_outlined, Brand.navy),
        'challan' => (Icons.local_shipping_outlined, Brand.navy),
        'credit_note' => (Icons.assignment_return_outlined, Colors.purple.shade700),
        'converted' => (Icons.transform, Brand.teal),
        'cancelled' => (Icons.block, Colors.grey.shade700),
        'expense' => (Icons.north_east, Colors.deepOrange),
        _ => (Icons.receipt_long_outlined, Brand.teal),
      };

  @override
  Widget build(BuildContext context) {
    final n = Notifications.instance;
    return ListenableBuilder(
      listenable: n,
      builder: (context, _) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(children: [
            const Text('Notifications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Brand.navy)),
            const SizedBox(width: 8),
            if (n.unread > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Brand.goldLight, borderRadius: BorderRadius.circular(10)),
                child: Text('${n.unread} new', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Brand.navy)),
              ),
            const Spacer(),
            if (n.unread > 0) TextButton(onPressed: n.markAllRead, child: const Text('Mark all read')),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: n.loading && n.items.isEmpty
              ? const LoadingView()
              : n.error != null && n.items.isEmpty
                  ? ErrorView(message: n.error!, onRetry: n.load)
                  : n.items.isEmpty
                      ? const EmptyView(icon: Icons.notifications_none, text: 'No notifications yet')
                      : ListView.separated(
                          itemCount: n.items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1, indent: 64),
                          itemBuilder: (_, i) {
                            final item = n.items[i];
                            final (icon, color) = _style(item);
                            final read = item['read'] == true;
                            return Material(
                              color: read ? Colors.white : Brand.tealLight.withValues(alpha: 0.55),
                              child: ListTile(
                                leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color, size: 20)),
                                title: Text('${item['title']}', style: TextStyle(fontWeight: read ? FontWeight.w500 : FontWeight.w700, fontSize: 14)),
                                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  if ('${item['body'] ?? ''}'.isNotEmpty) Text('${item['body']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                                  Text(timeAgo(item['createdAt']), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                ]),
                                trailing: read ? null : const CircleAvatar(radius: 4, backgroundColor: Brand.teal),
                                onTap: () {
                                  n.markRead(item);
                                  Navigator.pop(context);
                                  final link = '${item['link'] ?? ''}';
                                  if (link.isNotEmpty && outer.mounted) outer.push(link);
                                },
                              ),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}

class ProfileMenu extends StatelessWidget {
  const ProfileMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final u = AuthState.instance.user ?? {};
    final name = '${u['name'] ?? ''}';
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return PopupMenuButton<String>(
      tooltip: 'Profile',
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (v) async {
        switch (v) {
          case 'logout':
            if (await confirm(context, 'Logout?', 'You will need to login again.', ok: 'Logout')) {
              AuthState.instance.logout();
            }
          default:
            if (context.mounted) context.go(v);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.navy)),
            Text('${u['email'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Brand.goldLight, borderRadius: BorderRadius.circular(8)),
              child: Text(AuthState.instance.roleLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Brand.navy)),
            ),
            if (AuthState.instance.companyName != null) ...[
              const SizedBox(height: 4),
              Text(AuthState.instance.companyName!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Brand.teal)),
            ],
          ]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: '/settings', child: ListTile(dense: true, leading: Icon(Icons.person_outline), title: Text('My profile & password'))),
        PopupMenuItem(value: '/companies', child: ListTile(dense: true, leading: const Icon(Icons.business_outlined), title: Text(AuthState.instance.isCompanyLogin ? 'My Company' : 'Companies'))),
        const PopupMenuItem(value: '/export', child: ListTile(dense: true, leading: Icon(Icons.download_outlined), title: Text('Export / Download'))),
        if (AuthState.instance.isAdmin)
          const PopupMenuItem(value: '/users', child: ListTile(dense: true, leading: Icon(Icons.group_outlined), title: Text('Users & logins'))),
        const PopupMenuItem(value: '/masters', child: ListTile(dense: true, leading: Icon(Icons.tune), title: Text('Units, GST & lists'))),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          child: ListTile(dense: true, leading: Icon(Icons.logout, color: Colors.red.shade700), title: Text('Logout', style: TextStyle(color: Colors.red.shade700))),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Brand.teal,
            child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          if (wide) ...[
            const SizedBox(width: 8),
            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Brand.navy)),
              Text(AuthState.instance.companyName ?? AuthState.instance.roleLabel, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ]),
            const Icon(Icons.expand_more, size: 18, color: Brand.slate),
          ],
        ]),
      ),
    );
  }
}

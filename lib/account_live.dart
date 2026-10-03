import 'dart:async';
import 'package:flutter/material.dart';
import 'farsha_repository.dart';

/// Each page owns a listener; the repository shares one authenticated channel.
mixin AccountLive<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  StreamSubscription<void>? _accountSubscription;
  void startAccountLive(FarshaRepository repository, VoidCallback refresh) {
    _refresh = refresh;
    _accountSubscription = repository.accountChanges.listen((_) {
      if (mounted) refresh();
    });
    WidgetsBinding.instance.addObserver(this);
  }

  VoidCallback? _refresh;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _refresh?.call();
  }

  @override
  void dispose() {
    _accountSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class AccountNotifications extends StatefulWidget {
  const AccountNotifications({super.key, required this.repository});
  final FarshaRepository repository;
  @override
  State<AccountNotifications> createState() => _AccountNotificationsState();
}

class _AccountNotificationsState extends State<AccountNotifications>
    with WidgetsBindingObserver, AccountLive<AccountNotifications> {
  late Future<List<Map<String, dynamic>>> _data;
  @override
  void initState() {
    super.initState();
    _data = widget.repository.loadAccountNotifications();
    startAccountLive(
      widget.repository,
      () =>
          setState(() { _data = widget.repository.loadAccountNotifications(); }),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _data,
    builder: (context, snapshot) {
      final rows = snapshot.data ?? const <Map<String, dynamic>>[];
      final unread = rows.where((r) => r['read_at'] == null).length;
      return IconButton(
        tooltip: 'الإشعارات',
        icon: Badge(
          isLabelVisible: unread > 0,
          label: Text('$unread'),
          child: const Icon(Icons.notifications_outlined),
        ),
        onPressed: () async {
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (context) => SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .6,
                child: snapshot.hasError
                    ? const Center(child: Text('تعذر تحميل الإشعارات'))
                    : rows.isEmpty
                    ? const Center(child: Text('لا توجد إشعارات'))
                    : ListView(
                        children: rows
                            .map(
                              (r) => ListTile(
                                leading: Icon(
                                  r['read_at'] == null
                                      ? Icons.notifications_active
                                      : Icons.notifications_none,
                                ),
                                title: Text(r['title'] as String),
                                subtitle: Text(
                                  '${r['created_at']}\nمرجع العملية: ${r['event_id']}',
                                ),
                                onTap: () async {
                                  await widget.repository
                                      .markAccountNotificationRead(
                                        r['id'] as String,
                                      );
                                  if (context.mounted) Navigator.pop(context);
                                },
                              ),
                            )
                            .toList(),
                      ),
              ),
            ),
          );
          if (mounted)
            setState(
              () { _data = widget.repository.loadAccountNotifications(); },
            );
        },
      );
    },
  );
}

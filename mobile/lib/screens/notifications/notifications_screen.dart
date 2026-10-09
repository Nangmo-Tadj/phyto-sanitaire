import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

/// Notifications envoyées par le système (commande, paiement, livraison, message).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<(int, List<AppNotification>)> _data;

  Api get _api => context.read<Api>();

  @override
  void initState() {
    super.initState();
    _data = _api.notifications();
  }

  Future<void> _recharger() async {
    setState(() {
      _data = _api.notifications();
    });
    try {
      await _data;
    } catch (_) {}
  }

  static IconData _icone(String type) => switch (type) {
    'paiement' => Icons.payments_outlined,
    'livraison' => Icons.local_shipping_outlined,
    'message' => Icons.chat_bubble_outline,
    _ => Icons.receipt_long_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () async {
              await _api.toutesNotificationsLues().catchError((_) {});
              if (mounted) _recharger();
            },
            child: const Text('Tout marquer lu'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _recharger,
        child: AsyncView<(int, List<AppNotification>)>(
          future: _data,
          onRetry: _recharger,
          builder: (context, data) {
            final items = data.$2;
            if (items.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  EmptyState(icon: Icons.notifications_none, titre: 'Aucune notification'),
                ],
              );
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final n = items[i];
                return ListTile(
                  tileColor: n.lu
                      ? Colors.white
                      : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
                  leading: CircleAvatar(child: Icon(_icone(n.type), size: 20)),
                  title: Text(n.titre, style: TextStyle(fontWeight: n.lu ? FontWeight.normal : FontWeight.bold)),
                  subtitle: Text('${n.message}\n${dateHeure(n.date)}'),
                  isThreeLine: true,
                  onTap: n.lu
                      ? null
                      : () async {
                          await _api.notificationLue(n.id).catchError((_) {});
                          if (mounted) _recharger();
                        },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

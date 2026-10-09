import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import 'chat_screen.dart';

/// Liste des conversations (écrire des messages / discuter avec le client).
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  late Future<List<Conversation>> _conversations;

  Api get _api => context.read<Api>();

  @override
  void initState() {
    super.initState();
    _conversations = _api.conversations();
  }

  Future<void> _recharger() async {
    setState(() {
      _conversations = _api.conversations();
    });
    try {
      await _conversations;
    } catch (_) {}
  }

  Future<void> _ouvrir(int idUser, String nom, String? telephone) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(idUser: idUser, nom: nom, telephone: telephone),
      ),
    );
    if (mounted) _recharger();
  }

  Future<void> _contacterSupport() async {
    try {
      final s = await _api.support();
      if (!mounted) return;
      await _ouvrir(s['id_user'] as int, 'Service client AgroPhyto', s['telephone'] as String?);
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _contacterSupport,
        icon: const Icon(Icons.support_agent),
        label: const Text('Service client'),
      ),
      body: RefreshIndicator(
        onRefresh: _recharger,
        child: AsyncView<List<Conversation>>(
          future: _conversations,
          onRetry: _recharger,
          builder: (context, conversations) {
            if (conversations.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                    icon: Icons.forum_outlined,
                    titre: 'Aucune conversation',
                    message: 'Contactez un vendeur depuis la fiche d’un produit ou écrivez au service client.',
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: conversations.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, i) {
                final c = conversations[i];
                return ListTile(
                  tileColor: Colors.white,
                  leading: CircleAvatar(child: Text(c.nom.isEmpty ? '?' : c.nom[0].toUpperCase())),
                  title: Text(c.nom, style: TextStyle(fontWeight: c.nonLus > 0 ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text(c.dernierMessage ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_quand(c.date), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      if (c.nonLus > 0) ...[const SizedBox(height: 4), Badge(label: Text('${c.nonLus}'))],
                    ],
                  ),
                  onTap: () => _ouvrir(c.idUser, c.nom, c.telephone),
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _quand(DateTime? d) {
    if (d == null) return '';
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day ? heure(d) : dateCourte(d);
  }
}

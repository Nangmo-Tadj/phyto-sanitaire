import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../state/app_state.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

/// Fil de discussion avec rafraîchissement périodique et appel téléphonique direct.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.idUser, required this.nom, this.telephone});

  final int idUser;
  final String nom;
  final String? telephone;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _saisie = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <Message>[];
  Timer? _timer;
  bool _chargement = true;
  bool _envoi = false;
  bool _requeteEnCours = false;
  String? _telephone;

  /// Dernier identifiant reçu par le rafraîchissement : un message envoyé localement ne doit pas
  /// le faire avancer, sinon un message reçu juste avant (id inférieur) ne serait jamais récupéré.
  int _dernierIdRecu = 0;

  Api get _api => context.read<Api>();

  @override
  void initState() {
    super.initState();
    _telephone = widget.telephone;
    _charger();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _charger());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _saisie.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    // Évite d'empiler les requêtes si le serveur répond lentement.
    if (_requeteEnCours) return;
    _requeteEnCours = true;
    try {
      final (interlocuteur, nouveaux) = await _api.filMessages(widget.idUser, apres: _dernierIdRecu);
      if (!mounted) return;
      final ajoutes = nouveaux.where((m) => _messages.every((x) => x.id != m.id)).toList();
      setState(() {
        _telephone ??= interlocuteur['telephone'] as String?;
        for (final m in nouveaux) {
          if (m.id > _dernierIdRecu) _dernierIdRecu = m.id;
        }
        _messages
          ..addAll(ajoutes)
          ..sort((a, b) => a.id.compareTo(b.id));
        _chargement = false;
      });
      if (ajoutes.isNotEmpty) _defilerEnBas();
    } catch (e) {
      if (mounted && _chargement) {
        setState(() => _chargement = false);
        showMessage(context, e, erreur: true);
      }
    } finally {
      _requeteEnCours = false;
    }
  }

  void _defilerEnBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _envoyer() async {
    final texte = _saisie.text.trim();
    if (texte.isEmpty || _envoi) return;
    setState(() => _envoi = true);
    try {
      final m = await _api.envoyerMessage(widget.idUser, texte);
      if (!mounted) return;
      _saisie.clear();
      setState(() {
        if (_messages.every((x) => x.id != m.id)) {
          _messages
            ..add(m)
            ..sort((a, b) => a.id.compareTo(b.id));
        }
      });
      _defilerEnBas();
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // La session peut expirer pendant que l'écran est ouvert (user devient null).
    final monId = context.read<AuthState>().user?.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.nom),
        actions: [
          if (_telephone != null)
            IconButton(
              tooltip: 'Appeler',
              icon: const Icon(Icons.call),
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: _telephone)),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _chargement
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? const EmptyState(icon: Icons.chat_bubble_outline, titre: 'Démarrez la conversation')
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _Bulle(message: _messages[i], moi: _messages[i].idExpediteur == monId),
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _saisie,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(hintText: 'Votre message…'),
                      onSubmitted: (_) => _envoyer(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _envoi ? null : _envoyer,
                    icon: _envoi
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bulle extends StatelessWidget {
  const _Bulle({required this.message, required this.moi});

  final Message message;
  final bool moi;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: moi ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          color: moi ? scheme.primary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(moi ? 16 : 4),
            bottomRight: Radius.circular(moi ? 4 : 16),
          ),
          border: moi ? null : Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(message.contenu, style: TextStyle(color: moi ? Colors.white : Colors.black87)),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dateHeure(message.dateEnvoi),
                  style: TextStyle(fontSize: 10, color: moi ? Colors.white70 : Colors.grey),
                ),
                if (moi) ...[
                  const SizedBox(width: 4),
                  Icon(message.dateLecture != null ? Icons.done_all : Icons.done, size: 12, color: Colors.white70),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

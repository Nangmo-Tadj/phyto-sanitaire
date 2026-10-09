import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../commandes/order_detail_screen.dart';
import '../messages/chat_screen.dart';

/// Espace livreur (diagramme de séquence « Gestion des livraisons ») :
/// consulter les commandes à livrer, les prendre en charge, confirmer ou signaler un échec.
class DeliveriesScreen extends StatefulWidget {
  const DeliveriesScreen({super.key});

  @override
  State<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends State<DeliveriesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  Livraisons? _livraisons;
  Object? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final l = await context.read<Api>().livraisons();
      if (mounted) {
        setState(() {
          _livraisons = l;
          _erreur = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (_livraisons == null) {
        setState(() => _erreur = e);
      } else {
        showMessage(context, e, erreur: true);
      }
    }
  }

  void _reessayer() {
    setState(() => _erreur = null);
    _charger();
  }

  Future<void> _prendre(Commande c) async {
    try {
      await context.read<Api>().prendreLivraison(c.id);
      if (!mounted) return;
      showMessage(context, 'Commande #${c.id} prise en charge');
      await _charger();
      if (mounted) _tabs.animateTo(1);
    } on ApiException catch (e) {
      if (!mounted) return;
      // 409 : une autre personne a déjà pris la commande (ou elle n'est plus à livrer).
      showMessage(context, e.status == 409 ? 'Commande indisponible' : e.message, erreur: true);
      await _charger();
    }
  }

  Future<void> _confirmer(Commande c) async {
    final ok = await confirmer(
      context,
      'Confirmer la livraison',
      'Confirmez-vous avoir remis la commande #${c.id} (${fcfa(c.total)}) au client ?',
      action: 'Confirmer',
    );
    if (!ok || !mounted) return;
    try {
      await context.read<Api>().confirmerLivraison(c.id);
      if (!mounted) return;
      showMessage(context, 'Commande #${c.id} livrée');
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    }
    if (mounted) await _charger();
  }

  Future<void> _signalerEchec(Commande c) async {
    final motif = await showDialog<String>(
      context: context,
      builder: (_) => _MotifDialog(commande: c),
    );
    if (motif == null || !mounted) return;
    try {
      await context.read<Api>().signalerEchec(c.id, motif);
      if (!mounted) return;
      showMessage(context, 'Échec de livraison signalé pour la commande #${c.id}');
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    }
    if (mounted) await _charger();
  }

  Future<void> _appeler(String telephone) async {
    final ok = await launchUrl(Uri(scheme: 'tel', path: telephone.replaceAll(' ', '')));
    if (!ok && mounted) showMessage(context, 'Impossible de lancer l’appel vers $telephone', erreur: true);
  }

  Future<void> _ouvrirDetail(Commande c) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(commandeId: c.id)));
    if (mounted) _charger();
  }

  @override
  Widget build(BuildContext context) {
    final l = _livraisons;
    final enCours = l?.mesLivraisons.where((c) => c.statut == StatutCommande.enLivraison).length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Livraisons'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: l == null ? 'À livrer' : 'À livrer (${l.disponibles.length})'),
            Tab(text: enCours == 0 ? 'Mes livraisons' : 'Mes livraisons ($enCours)'),
          ],
        ),
      ),
      body: l == null
          ? (_erreur == null
                ? const Center(child: CircularProgressIndicator())
                : EmptyState(
                    icon: Icons.cloud_off,
                    titre: 'Une erreur est survenue',
                    message: '$_erreur',
                    action: OutlinedButton.icon(
                      onPressed: _reessayer,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                    ),
                  ))
          : TabBarView(
              controller: _tabs,
              children: [
                _Liste(
                  commandes: l.disponibles,
                  onRefresh: _charger,
                  vide: const EmptyState(
                    icon: Icons.local_shipping_outlined,
                    titre: 'Aucune commande à livrer',
                    message: 'Les commandes payées en attente de livreur apparaîtront ici.',
                  ),
                  itemBuilder: (c) => _LivraisonCard(
                    commande: c,
                    onTap: () => _ouvrirDetail(c),
                    actions: [
                      BusyButton(label: 'Prendre en charge', icon: Icons.local_shipping, onPressed: () => _prendre(c)),
                    ],
                  ),
                ),
                _Liste(
                  commandes: l.mesLivraisons,
                  onRefresh: _charger,
                  vide: const EmptyState(
                    icon: Icons.assignment_outlined,
                    titre: 'Aucune livraison prise en charge',
                    message: 'Prenez en charge une commande depuis l’onglet « À livrer ».',
                  ),
                  itemBuilder: (c) => _LivraisonCard(
                    commande: c,
                    afficherStatut: true,
                    onTap: () => _ouvrirDetail(c),
                    onAppeler: c.statut == StatutCommande.enLivraison && c.telephoneLivraison.isNotEmpty
                        ? () => _appeler(c.telephoneLivraison)
                        : null,
                    onMessage: c.statut == StatutCommande.enLivraison
                        ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                idUser: c.idUser,
                                nom: c.client ?? 'Client',
                                telephone: c.telephoneLivraison,
                              ),
                            ),
                          )
                        : null,
                    actions: c.statut != StatutCommande.enLivraison
                        ? const []
                        : [
                            BusyButton(
                              label: 'Confirmer la livraison',
                              icon: Icons.check_circle_outline,
                              onPressed: () => _confirmer(c),
                            ),
                            BusyButton(
                              label: 'Signaler un échec',
                              icon: Icons.report_problem_outlined,
                              outlined: true,
                              onPressed: () => _signalerEchec(c),
                            ),
                          ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _Liste extends StatelessWidget {
  const _Liste({required this.commandes, required this.onRefresh, required this.vide, required this.itemBuilder});

  final List<Commande> commandes;
  final Future<void> Function() onRefresh;
  final Widget vide;
  final Widget Function(Commande) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: commandes.isEmpty
          ? LayoutBuilder(
              builder: (context, c) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [SizedBox(height: c.maxHeight, child: vide)],
              ),
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: commandes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => itemBuilder(commandes[i]),
            ),
    );
  }
}

class _LivraisonCard extends StatelessWidget {
  const _LivraisonCard({
    required this.commande,
    required this.onTap,
    this.actions = const [],
    this.afficherStatut = false,
    this.onAppeler,
    this.onMessage,
  });

  final Commande commande;
  final VoidCallback onTap;
  final List<Widget> actions;
  final bool afficherStatut;
  final VoidCallback? onAppeler;
  final VoidCallback? onMessage;

  @override
  Widget build(BuildContext context) {
    final c = commande;
    final discret = TextStyle(color: Colors.grey.shade700);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Commande #${c.id}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  if (afficherStatut)
                    StatusChip(c.statut)
                  else
                    Text(
                      fcfa(c.total),
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.vert),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(dateHeure(c.date), style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              const Divider(height: 20),
              _Ligne(
                icon: Icons.location_city,
                child: Text(c.ville, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              _Ligne(
                icon: Icons.place_outlined,
                child: Text(c.adresse, style: discret),
              ),
              if (c.client != null)
                _Ligne(
                  icon: Icons.person_outline,
                  child: Text(c.client!, style: discret),
                ),
              if (c.telephoneLivraison.isNotEmpty)
                _Ligne(
                  icon: Icons.phone_outlined,
                  child: Row(
                    children: [
                      Expanded(child: Text(c.telephoneLivraison, style: discret)),
                      if (onMessage != null)
                        IconButton(
                          tooltip: 'Écrire au client',
                          visualDensity: VisualDensity.compact,
                          onPressed: onMessage,
                          icon: const Icon(Icons.chat_bubble_outline),
                        ),
                      if (onAppeler != null)
                        IconButton.filledTonal(
                          tooltip: 'Appeler le client',
                          visualDensity: VisualDensity.compact,
                          onPressed: onAppeler,
                          icon: const Icon(Icons.call),
                        ),
                    ],
                  ),
                ),
              if (afficherStatut)
                _Ligne(
                  icon: Icons.payments_outlined,
                  child: Text('Total : ${fcfa(c.total)}', style: discret),
                ),
              if (c.statut == StatutCommande.livree && c.dateLivraison != null)
                _Ligne(
                  icon: Icons.check_circle_outline,
                  child: Text('Livrée le ${dateHeure(c.dateLivraison)}', style: discret),
                ),
              if (c.statut == StatutCommande.echecLivraison && c.motifEchec != null)
                _Ligne(
                  icon: Icons.report_problem_outlined,
                  child: Text('Motif : ${c.motifEchec}', style: TextStyle(color: Colors.red.shade700)),
                ),
              for (final a in actions) ...[const SizedBox(height: 10), a],
            ],
          ),
        ),
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.icon, required this.child});
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    ),
  );
}

class _MotifDialog extends StatefulWidget {
  const _MotifDialog({required this.commande});
  final Commande commande;

  @override
  State<_MotifDialog> createState() => _MotifDialogState();
}

class _MotifDialogState extends State<_MotifDialog> {
  final _formKey = GlobalKey<FormState>();
  final _motif = TextEditingController();

  static const _suggestions = ['Client absent', 'Client injoignable', 'Adresse introuvable', 'Commande refusée'];

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  void _valider() {
    if (_formKey.currentState!.validate()) Navigator.pop(context, _motif.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Signaler un échec'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Commande #${widget.commande.id} — indiquez la raison de l’échec de livraison.'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in _suggestions)
                    ActionChip(label: Text(s), onPressed: () => setState(() => _motif.text = s)),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _motif,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Motif *'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Le motif est obligatoire' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700, minimumSize: const Size(0, 40)),
          onPressed: _valider,
          child: const Text('Signaler'),
        ),
      ],
    );
  }
}

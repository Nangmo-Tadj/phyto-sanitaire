import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../commandes/order_detail_screen.dart';

/// Transitions autorisées pour la mise à jour manuelle du statut (miroir de backend/src/routes/admin.js).
const transitionsStatutCommande = <String, List<String>>{
  StatutCommande.enAttentePaiement: [StatutCommande.annulee],
  StatutCommande.enCours: [StatutCommande.enLivraison, StatutCommande.annulee],
  StatutCommande.enLivraison: [StatutCommande.livree, StatutCommande.echecLivraison, StatutCommande.enCours],
  StatutCommande.echecLivraison: [StatutCommande.enCours, StatutCommande.enLivraison, StatutCommande.annulee],
  StatutCommande.livree: [],
  StatutCommande.annulee: [],
};

/// Consultation de toutes les commandes et mise à jour de leur statut.
class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  String? _statut;
  Future<List<Commande>>? _future;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  void _charger() => _future = context.read<Api>().toutesCommandes(statut: _statut);

  Future<void> _rafraichir() async {
    setState(_charger);
    try {
      await _future;
    } catch (_) {}
  }

  Future<void> _ouvrir(Commande c) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(commandeId: c.id)));
    if (mounted) _rafraichir();
  }

  Future<void> _changerStatut(Commande c) async {
    final cibles = transitionsStatutCommande[c.statut] ?? const [];
    if (cibles.isEmpty) return;

    final cible = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Commande #${c.id}', style: Theme.of(ctx).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(children: [const Text('Statut actuel : '), StatusChip(c.statut)]),
            ),
            const Divider(),
            for (final s in cibles)
              ListTile(
                leading: Icon(Icons.arrow_forward, color: couleurStatut(s)),
                title: Text(libelleStatut(s)),
                subtitle: switch (s) {
                  StatutCommande.enLivraison => const Text('Assigner un livreur'),
                  StatutCommande.enCours when c.statut == StatutCommande.enLivraison => const Text(
                    'Retirer le livreur assigné',
                  ),
                  StatutCommande.annulee => const Text('Le stock des produits sera restitué'),
                  _ => null,
                },
                onTap: () => Navigator.pop(ctx, s),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (cible == null || !mounted) return;

    int? idLivreur;
    String? motif;
    switch (cible) {
      case StatutCommande.enLivraison:
        final livreur = await showDialog<User>(
          context: context,
          builder: (_) => _ChoixLivreurDialog(actuel: c.idLivreur),
        );
        if (livreur == null) return;
        idLivreur = livreur.id;
      case StatutCommande.echecLivraison:
        motif = await showDialog<String>(context: context, builder: (_) => const _MotifDialog());
        if (motif == null) return;
      case StatutCommande.annulee:
        final ok = await confirmer(
          context,
          'Annuler la commande',
          'Annuler la commande #${c.id} ? Le stock sera restitué. Cette action est définitive.',
          action: 'Annuler la commande',
          danger: true,
        );
        if (!ok) return;
    }
    if (!mounted) return;

    try {
      await context.read<Api>().changerStatutCommande(c.id, cible, idLivreur: idLivreur, motif: motif);
      if (!mounted) return;
      showMessage(context, 'Commande #${c.id} : ${libelleStatut(cible)}');
      _rafraichir();
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Commandes')),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              children: [
                for (final s in [null, ...StatutCommande.tous])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s == null ? 'Toutes' : libelleStatut(s)),
                      selected: _statut == s,
                      onSelected: (_) => setState(() {
                        _statut = s;
                        _charger();
                      }),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _rafraichir,
              child: AsyncView<List<Commande>>(
                future: _future,
                onRetry: () => setState(_charger),
                builder: (context, commandes) {
                  if (commandes.isEmpty) {
                    return ListView(
                      children: const [
                        SizedBox(height: 60),
                        EmptyState(icon: Icons.receipt_long, titre: 'Aucune commande'),
                      ],
                    );
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: commandes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) =>
                        _CommandeCard(commande: commandes[i], onTap: _ouvrir, onChangerStatut: _changerStatut),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandeCard extends StatelessWidget {
  const _CommandeCard({required this.commande, required this.onTap, required this.onChangerStatut});

  final Commande commande;
  final void Function(Commande) onTap;
  final void Function(Commande) onChangerStatut;

  @override
  Widget build(BuildContext context) {
    final c = commande;
    final modifiable = (transitionsStatutCommande[c.statut] ?? const []).isNotEmpty;
    final gris = TextStyle(color: Colors.grey.shade600, fontSize: 13);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(c),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('#${c.id}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(dateHeure(c.date), style: gris)),
                  StatusChip(c.statut),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(child: Text(c.client ?? 'Client #${c.idUser}', overflow: TextOverflow.ellipsis)),
                  Text(
                    fcfa(c.total),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.vert),
                  ),
                ],
              ),
              if (c.ville.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(c.ville, style: gris, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.delivery_dining_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      c.livreur == null ? 'Aucun livreur assigné' : 'Livreur : ${c.livreur}',
                      style: gris,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (modifiable)
                    TextButton.icon(
                      onPressed: () => onChangerStatut(c),
                      icon: const Icon(Icons.sync_alt, size: 18),
                      label: const Text('Changer le statut'),
                    ),
                ],
              ),
              if (c.statut == StatutCommande.echecLivraison && c.motifEchec != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    'Motif : ${c.motifEchec}',
                    style: TextStyle(color: couleurStatut(c.statut), fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoixLivreurDialog extends StatefulWidget {
  const _ChoixLivreurDialog({this.actuel});
  final int? actuel;

  @override
  State<_ChoixLivreurDialog> createState() => _ChoixLivreurDialogState();
}

class _ChoixLivreurDialogState extends State<_ChoixLivreurDialog> {
  late Future<List<User>> _future;
  late int? _selection = widget.actuel;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  void _charger() => _future = context.read<Api>().livreurs();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Assigner un livreur'),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: SizedBox(
        width: double.maxFinite,
        height: 320,
        child: AsyncView<List<User>>(
          future: _future,
          onRetry: () => setState(_charger),
          builder: (context, users) {
            final livreurs = users.where((u) => u.actif).toList();
            if (livreurs.isEmpty) {
              return const EmptyState(icon: Icons.delivery_dining_outlined, titre: 'Aucun livreur actif');
            }
            return RadioGroup<int>(
              groupValue: _selection,
              onChanged: (v) => setState(() => _selection = v),
              child: ListView(
                children: [
                  for (final u in livreurs)
                    RadioListTile<int>(value: u.id, title: Text(u.nomComplet), subtitle: Text(u.telephone)),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FutureBuilder<List<User>>(
          future: _future,
          builder: (context, snap) {
            final livreur = snap.data?.where((u) => u.id == _selection).firstOrNull;
            return FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: livreur == null ? null : () => Navigator.pop(context, livreur),
              child: const Text('Assigner'),
            );
          },
        ),
      ],
    );
  }
}

class _MotifDialog extends StatefulWidget {
  const _MotifDialog();

  @override
  State<_MotifDialog> createState() => _MotifDialogState();
}

class _MotifDialogState extends State<_MotifDialog> {
  final _form = GlobalKey<FormState>();
  final _motif = TextEditingController();

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Échec de livraison'),
      content: Form(
        key: _form,
        child: TextFormField(
          controller: _motif,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Motif', hintText: 'ex. Client injoignable'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Indiquez le motif' : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: () {
            if (_form.currentState!.validate()) Navigator.pop(context, _motif.text.trim());
          },
          child: const Text('Valider'),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../commandes/order_detail_screen.dart';

/// Transitions autorisées pour la mise à jour manuelle du statut (miroir de backend/src/routes/admin.js).
const transitionsStatutCommande = <String, List<String>>{
  StatutCommande.enAttentePaiement: [StatutCommande.enCours, StatutCommande.annulee],
  StatutCommande.enCours: [StatutCommande.enPreparation, StatutCommande.enLivraison, StatutCommande.annulee],
  StatutCommande.enPreparation: [StatutCommande.enLivraison, StatutCommande.enCours, StatutCommande.annulee],
  StatutCommande.enLivraison: [StatutCommande.livree, StatutCommande.echecLivraison, StatutCommande.enPreparation],
  StatutCommande.echecLivraison: [StatutCommande.enPreparation, StatutCommande.enLivraison, StatutCommande.annulee],
  StatutCommande.livree: [StatutCommande.cloturee],
  StatutCommande.cloturee: [],
  StatutCommande.annulee: [],
};

/// Statuts où l'administrateur peut affecter un livreur sans démarrer la livraison.
const statutsAffectables = [StatutCommande.enCours, StatutCommande.enPreparation, StatutCommande.echecLivraison];

/// Consultation de toutes les commandes (filtres) et mise à jour de leur statut.
class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key, this.statutsInitiaux = const []});

  /// Filtre appliqué à l'ouverture (ex. depuis le tableau de bord).
  final List<String> statutsInitiaux;

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  late final Set<String> _statuts = {...widget.statutsInitiaux};
  final _recherche = TextEditingController();
  Timer? _delai;
  DateTimeRange? _periode;
  Future<List<Commande>>? _future;

  static final _jour = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _delai?.cancel();
    _recherche.dispose();
    super.dispose();
  }

  void _charger() => _future = context.read<Api>().toutesCommandes(
    statuts: _statuts.isEmpty ? null : _statuts.toList(),
    q: _recherche.text.trim(),
    du: _periode == null ? null : _jour.format(_periode!.start),
    au: _periode == null ? null : _jour.format(_periode!.end),
  );

  void _rechercher(String _) {
    _delai?.cancel();
    _delai = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(_charger);
    });
  }

  Future<void> _choisirPeriode() async {
    final maintenant = DateTime.now();
    final periode = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: maintenant,
      initialDateRange: _periode,
      helpText: 'Période des commandes',
    );
    if (periode == null || !mounted) return;
    setState(() {
      _periode = periode;
      _charger();
    });
  }

  void _basculerStatut(String? s) => setState(() {
    if (s == null) {
      _statuts.clear();
    } else if (!_statuts.remove(s)) {
      _statuts.add(s);
    }
    _charger();
  });

  Future<void> _affecter(Commande c) async {
    final choix = await showDialog<({User? livreur})>(
      context: context,
      builder: (_) => _ChoixLivreurDialog(actuel: c.idLivreur, affectation: true),
    );
    if (choix == null || !mounted) return;
    try {
      await context.read<Api>().affecterLivreur(c.id, choix.livreur?.id);
      if (!mounted) return;
      showMessage(
        context,
        choix.livreur == null
            ? 'Livreur retiré de la commande #${c.id}'
            : 'Commande #${c.id} affectée à ${choix.livreur!.nomComplet}',
      );
      _rafraichir();
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    }
  }

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
                title: Text(
                  s == StatutCommande.enCours && c.statut == StatutCommande.enAttentePaiement
                      ? 'Valider (paiement à la livraison)'
                      : libelleStatut(s),
                ),
                subtitle: switch (s) {
                  StatutCommande.enLivraison => const Text('Assigner un livreur et démarrer la livraison'),
                  StatutCommande.enPreparation when c.statut == StatutCommande.enLivraison => const Text(
                    'Retirer le livreur assigné',
                  ),
                  StatutCommande.cloturee => const Text('Clôturer sans attendre la confirmation du client'),
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
        final choix = await showDialog<({User? livreur})>(
          context: context,
          builder: (_) => _ChoixLivreurDialog(actuel: c.idLivreur),
        );
        if (choix?.livreur == null) return;
        idLivreur = choix!.livreur!.id;
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _recherche,
                    onChanged: _rechercher,
                    onSubmitted: (_) => setState(_charger),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'N° (#12), client ou téléphone',
                      suffixIcon: _recherche.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(() {
                                _recherche.clear();
                                _charger();
                              }),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Période',
                  onPressed: _choisirPeriode,
                  icon: const Icon(Icons.date_range),
                ),
              ],
            ),
          ),
          if (_periode != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  avatar: const Icon(Icons.event, size: 18),
                  label: Text('Du ${dateCourte(_periode!.start)} au ${dateCourte(_periode!.end)}'),
                  onDeleted: () => setState(() {
                    _periode = null;
                    _charger();
                  }),
                ),
              ),
            ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Toutes'),
                    selected: _statuts.isEmpty,
                    onSelected: (_) => _basculerStatut(null),
                  ),
                ),
                for (final s in StatutCommande.tous)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(libelleStatut(s)),
                      selected: _statuts.contains(s),
                      onSelected: (_) => _basculerStatut(s),
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
                    itemBuilder: (context, i) => _CommandeCard(
                      commande: commandes[i],
                      onTap: _ouvrir,
                      onChangerStatut: _changerStatut,
                      onAffecter: _affecter,
                    ),
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
  const _CommandeCard({
    required this.commande,
    required this.onTap,
    required this.onChangerStatut,
    required this.onAffecter,
  });

  final Commande commande;
  final void Function(Commande) onTap;
  final void Function(Commande) onChangerStatut;
  final void Function(Commande) onAffecter;

  @override
  Widget build(BuildContext context) {
    final c = commande;
    final modifiable = (transitionsStatutCommande[c.statut] ?? const []).isNotEmpty;
    final affectable = statutsAffectables.contains(c.statut);
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
                      style: c.livreur == null ? gris : gris.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (modifiable || affectable)
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 4,
                    children: [
                      if (affectable)
                        TextButton.icon(
                          onPressed: () => onAffecter(c),
                          icon: const Icon(Icons.person_add_alt, size: 18),
                          label: Text(c.idLivreur == null ? 'Affecter un livreur' : 'Changer de livreur'),
                        ),
                      if (modifiable)
                        TextButton.icon(
                          onPressed: () => onChangerStatut(c),
                          icon: const Icon(Icons.sync_alt, size: 18),
                          label: const Text('Changer le statut'),
                        ),
                    ],
                  ),
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
  const _ChoixLivreurDialog({this.actuel, this.affectation = false});
  final int? actuel;

  /// Affectation seule : propose aussi de retirer le livreur actuel.
  final bool affectation;

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
      title: Text(widget.affectation ? 'Affecter un livreur' : 'Assigner un livreur'),
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
        if (widget.affectation && widget.actuel != null)
          TextButton(
            onPressed: () => Navigator.pop(context, (livreur: null)),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Retirer le livreur'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FutureBuilder<List<User>>(
          future: _future,
          builder: (context, snap) {
            final livreur = snap.data?.where((u) => u.id == _selection).firstOrNull;
            return FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: livreur == null ? null : () => Navigator.pop(context, (livreur: livreur)),
              child: Text(widget.affectation ? 'Affecter' : 'Assigner'),
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

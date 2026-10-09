import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import 'admin_categories_screen.dart';
import 'admin_delivery_rules_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_payments_screen.dart';
import 'admin_products_screen.dart';
import 'admin_roles_screen.dart';
import 'admin_users_screen.dart';

/// Tableau de bord de l'administrateur : statistiques des ventes et accès aux outils de gestion.
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  Future<Statistiques>? _future;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  void _charger() {
    context.read<ParametresState>().charger().catchError((_) {});
    final user = context.read<AuthState>().user;
    if (user != null && user.can(Perm.statistiquesVoir)) {
      _future = context.read<Api>().statistiques();
    }
  }

  Future<void> _rafraichir() async {
    setState(_charger);
    try {
      await _future;
    } catch (_) {
      // L'erreur est affichée par AsyncView.
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthState>().user;
    final entrees = _entreesMenu.where((e) => user?.can(e.permission) ?? false).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Administration')),
      body: RefreshIndicator(
        onRefresh: _rafraichir,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (user != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  'Bonjour ${user.prenom}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            if (entrees.isNotEmpty) ...[
              const SectionTitle('Gestion'),
              _MenuGrid(entrees: entrees, onRetour: _rafraichir),
            ],
            if (user?.can(Perm.utilisateursGerer) ?? false) ...[
              const SectionTitle('Paramètres de la plateforme'),
              const _ParametresCard(),
            ],
            if (_future != null)
              AsyncView<Statistiques>(
                future: _future,
                onRetry: () => setState(_charger),
                builder: (context, stats) => _Tableau(stats: stats),
              ),
          ],
        ),
      ),
    );
  }
}

/// Réglages globaux : ouverture de boutiques par les utilisateurs.
class _ParametresCard extends StatefulWidget {
  const _ParametresCard();

  @override
  State<_ParametresCard> createState() => _ParametresCardState();
}

class _ParametresCardState extends State<_ParametresCard> {
  bool _enCours = false;

  Future<void> _changer(bool autorise) async {
    final ok = await confirmer(
      context,
      autorise ? 'Autoriser la création de boutiques' : 'Désactiver la création de boutiques',
      autorise
          ? 'Les utilisateurs pourront de nouveau ouvrir une boutique et s’inscrire comme vendeur.'
          : 'Les utilisateurs ne pourront plus ouvrir de boutique ni s’inscrire comme vendeur. '
                'Les boutiques existantes restent actives.',
      action: autorise ? 'Autoriser' : 'Désactiver',
      danger: !autorise,
    );
    if (!ok || !mounted) return;
    setState(() => _enCours = true);
    try {
      await context.read<ParametresState>().autoriserCreationBoutique(autorise);
      if (mounted) {
        showMessage(context, autorise ? 'Création de boutiques autorisée' : 'Création de boutiques désactivée');
      }
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final autorise = context.watch<ParametresState>().creationBoutique;
    return Card(
      child: SwitchListTile(
        secondary: const Icon(Icons.add_business_outlined, color: AppColors.vert),
        title: const Text('Création de boutiques'),
        subtitle: Text(
          autorise
              ? 'Les utilisateurs peuvent ouvrir leur boutique'
              : 'Désactivée : seuls les administrateurs peuvent créer une boutique',
        ),
        value: autorise,
        onChanged: _enCours ? null : _changer,
      ),
    );
  }
}

class _EntreeMenu {
  const _EntreeMenu(this.titre, this.icon, this.permission, this.builder);
  final String titre;
  final IconData icon;
  final String permission;
  final WidgetBuilder builder;
}

final _entreesMenu = <_EntreeMenu>[
  _EntreeMenu('Commandes', Icons.receipt_long, Perm.commandesGerer, (_) => const AdminOrdersScreen()),
  _EntreeMenu('Paiements', Icons.payments_outlined, Perm.paiementsVoir, (_) => const AdminPaymentsScreen()),
  _EntreeMenu('Produits', Icons.inventory_2_outlined, Perm.produitsModerer, (_) => const AdminProductsScreen()),
  _EntreeMenu('Catégories', Icons.category_outlined, Perm.categoriesGerer, (_) => const AdminCategoriesScreen()),
  _EntreeMenu(
    'Utilisateurs & boutiques',
    Icons.people_outline,
    Perm.utilisateursGerer,
    (_) => const AdminUsersScreen(),
  ),
  _EntreeMenu(
    'Rôles & permissions',
    Icons.admin_panel_settings_outlined,
    Perm.rolesGerer,
    (_) => const AdminRolesScreen(),
  ),
  _EntreeMenu(
    'Règles de livraison',
    Icons.local_shipping_outlined,
    Perm.livraisonRegles,
    (_) => const AdminDeliveryRulesScreen(),
  ),
];

class _MenuGrid extends StatelessWidget {
  const _MenuGrid({required this.entrees, required this.onRetour});
  final List<_EntreeMenu> entrees;
  final Future<void> Function() onRetour;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final colonnes = constraints.maxWidth >= 600 ? 4 : 2;
        return GridView.count(
          crossAxisCount: colonnes,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.9,
          children: [
            for (final e in entrees)
              Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: e.builder));
                    if (context.mounted) onRetour();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(e.icon, color: AppColors.vert),
                        Text(
                          e.titre,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Tableau extends StatelessWidget {
  const _Tableau({required this.stats});
  final Statistiques stats;

  @override
  Widget build(BuildContext context) {
    final statuts = [
      ...StatutCommande.tous.where(stats.commandesParStatut.containsKey),
      ...stats.commandesParStatut.keys.where((s) => !StatutCommande.tous.contains(s)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Statistiques des ventes'),
        _Kpis(stats: stats),
        const SectionTitle('Ventes des 30 derniers jours'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: stats.ventesParJour.isEmpty
                ? const Text('Aucune vente payée sur la période.', style: TextStyle(color: Colors.grey))
                : _BarChart(ventes: stats.ventesParJour),
          ),
        ),
        const SectionTitle('Commandes par statut'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: statuts.isEmpty
                ? const Text('Aucune commande.', style: TextStyle(color: Colors.grey))
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in statuts)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StatusChip(s),
                            const SizedBox(width: 4),
                            Text('${stats.commandesParStatut[s]}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                    ],
                  ),
          ),
        ),
        const SectionTitle('Meilleures ventes'),
        Card(
          child: stats.topProduits.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Aucune vente.', style: TextStyle(color: Colors.grey)),
                )
              : Column(
                  children: [
                    for (final (i, p) in stats.topProduits.indexed)
                      ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.vertClair,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(color: AppColors.vert, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(p.nom, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${p.quantite} vendu(s)'),
                        trailing: Text(fcfa(p.montant), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
        ),
        SectionTitle(
          'Alertes de stock bas',
          trailing: stats.stockBas.isEmpty ? null : Tag('${stats.stockBas.length}', color: AppColors.terre),
        ),
        Card(
          child: stats.stockBas.isEmpty
              ? const ListTile(
                  leading: Icon(Icons.check_circle_outline, color: AppColors.vert),
                  title: Text('Aucun produit en stock bas'),
                )
              : Column(
                  children: [
                    for (final p in stats.stockBas)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.warning_amber_rounded,
                          color: p.stock == 0 ? Colors.red.shade700 : AppColors.terre,
                        ),
                        title: Text(p.nom, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Text(
                          p.stock == 0 ? 'Rupture' : '${p.stock} en stock',
                          style: TextStyle(
                            color: p.stock == 0 ? Colors.red.shade700 : AppColors.terre,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.stats});
  final Statistiques stats;

  @override
  Widget build(BuildContext context) {
    final kpis = [
      ('Chiffre d\'affaires', fcfa(stats.chiffreAffaires), Icons.trending_up, AppColors.vert),
      ('Commandes', '${stats.nbCommandes}', Icons.receipt_long, const Color(0xFF1565C0)),
      ('Utilisateurs', '${stats.nbClients}', Icons.people, const Color(0xFF6A1B9A)),
      ('Produits publiés', '${stats.nbProduits}', Icons.inventory_2, AppColors.elevage),
      ('Panier moyen', fcfa(stats.panierMoyen), Icons.shopping_basket, AppColors.terre),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final colonnes = constraints.maxWidth >= 600 ? 3 : 2;
        final largeur = (constraints.maxWidth - (colonnes - 1) * 10) / colonnes;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (i, (label, valeur, icon, couleur)) in kpis.indexed)
              SizedBox(
                // Le chiffre d'affaires occupe toute la largeur.
                width: i == 0 ? constraints.maxWidth : largeur,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: couleur.withValues(alpha: 0.12),
                          child: Icon(icon, color: couleur),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(valeur, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Histogramme simple des ventes par jour, dessiné avec des widgets.
class _BarChart extends StatelessWidget {
  const _BarChart({required this.ventes});
  final List<({String jour, int commandes, int montant})> ventes;

  static const _hauteur = 150.0;

  String _jourMois(String jour) {
    final d = DateTime.tryParse(jour);
    return d == null ? jour : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final max = ventes.map((v) => v.montant).fold(0, math.max);
    final total = ventes.fold(0, (s, v) => s + v.montant);
    // Afficher au plus ~6 libellés sous l'axe.
    final pas = math.max(1, (ventes.length / 6).ceil());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Total : ${fcfa(total)}', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('Maximum journalier : ${fcfa(max)}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        const SizedBox(height: 12),
        SizedBox(
          height: _hauteur,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final v in ventes)
                Expanded(
                  child: Tooltip(
                    message:
                        '${_jourMois(v.jour)} : ${fcfa(v.montant)} (${v.commandes} commande${v.commandes > 1 ? 's' : ''})',
                    triggerMode: TooltipTriggerMode.tap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: max == 0 ? 2 : math.max(2, _hauteur * v.montant / max),
                          decoration: const BoxDecoration(
                            color: AppColors.vert,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final (i, v) in ventes.indexed)
              Expanded(
                child: i % pas == 0
                    ? Text(
                        _jourMois(v.jour),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      ],
    );
  }
}

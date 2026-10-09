import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../commandes/order_detail_screen.dart';
import 'product_form_screen.dart';

/// Seuil à partir duquel le stock est signalé comme bas.
const _seuilStockBas = 5;

/// Espace vendeur : créer la boutique, gérer les produits et le stock, suivre les ventes.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  Boutique? _boutique;
  Object? _erreur;
  bool _chargement = true;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  void _reessayer() {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    _charger();
  }

  Future<void> _charger() async {
    final parametres = context.read<ParametresState>();
    try {
      // Paramètres à jour : l'administrateur a pu fermer la création de boutiques entre-temps.
      unawaited(parametres.charger().catchError((_) {}));
      final b = await context.read<Api>().maBoutique();
      if (mounted) setState(() => _boutique = b);
    } catch (e) {
      if (mounted) setState(() => _erreur = e);
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _creer(Map<String, dynamic> data) async {
    final api = context.read<Api>();
    final auth = context.read<AuthState>();
    final b = await api.creerBoutique(data);
    // La création attribue le rôle vendeur : on recharge les permissions.
    // Un échec ici ne doit pas masquer la boutique créée (sinon « Vous avez déjà une boutique » au réessai).
    try {
      await auth.rafraichir();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _boutique = b);
    showMessage(context, 'Boutique « ${b.nom} » créée. Ajoutez vos premiers produits !');
  }

  @override
  Widget build(BuildContext context) {
    if (_chargement && _boutique == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ma boutique')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_erreur != null && _boutique == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ma boutique')),
        body: EmptyState(
          icon: Icons.cloud_off,
          titre: 'Une erreur est survenue',
          message: '$_erreur',
          action: OutlinedButton.icon(
            onPressed: _reessayer,
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        ),
      );
    }
    final boutique = _boutique;
    final creationFermee =
        !context.watch<ParametresState>().creationBoutique &&
        !(context.watch<AuthState>().user?.can(Perm.utilisateursGerer) ?? false);
    if (boutique == null && creationFermee) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ma boutique')),
        body: const EmptyState(
          icon: Icons.storefront_outlined,
          titre: 'Création de boutiques fermée',
          message:
              'L’administrateur a temporairement désactivé l’ouverture de nouvelles boutiques. Réessayez plus tard.',
        ),
      );
    }
    if (boutique == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Créer ma boutique')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _Intro(),
            const SizedBox(height: 20),
            _BoutiqueForm(labelAction: 'Créer la boutique', icon: Icons.storefront, onSubmit: _creer),
          ],
        ),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(boutique.nom),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Produits'),
              Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Ventes'),
              Tab(icon: Icon(Icons.storefront_outlined), text: 'Boutique'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (!boutique.active)
              Container(
                width: double.infinity,
                color: Colors.red.shade50,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.red.shade700),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Votre boutique a été désactivée par l’administrateur : vos produits ne sont plus visibles.',
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  const _ProduitsTab(),
                  const _VentesTab(),
                  _BoutiqueTab(boutique: boutique, onChanged: (b) => setState(() => _boutique = b)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.vertClair,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.storefront, size: 40, color: AppColors.vert),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vendez vos produits',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Créez votre boutique pour publier vos produits phytosanitaires et aliments pour élevage.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Liste scrollable occupant toute la hauteur (permet le « tirer pour actualiser » sur un état vide).
Widget _pleineHauteur(Widget child) => LayoutBuilder(
  builder: (context, c) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [SizedBox(height: c.maxHeight, child: child)],
  ),
);

// --- Onglet Produits ------------------------------------------------------------------

class _ProduitsTab extends StatefulWidget {
  const _ProduitsTab();

  @override
  State<_ProduitsTab> createState() => _ProduitsTabState();
}

class _ProduitsTabState extends State<_ProduitsTab> with AutomaticKeepAliveClientMixin {
  List<Produit>? _produits;
  Object? _erreur;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final produits = await context.read<Api>().produitsGestion(tous: false);
      if (mounted) {
        setState(() {
          _produits = produits;
          _erreur = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (_produits == null) {
        setState(() => _erreur = e);
      } else {
        showMessage(context, e, erreur: true);
      }
    }
  }

  void _remplacer(Produit p) {
    setState(() => _produits = [for (final x in _produits!) x.id == p.id ? p : x]);
  }

  Future<void> _ouvrirFormulaire([Produit? produit]) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ProductFormScreen(produit: produit)),
    );
    if (ok == true && mounted) await _charger();
  }

  Future<void> _ajusterStock(Produit p) async {
    final stock = await showDialog<int>(
      context: context,
      builder: (_) => _StockDialog(produit: p),
    );
    if (stock == null || stock == p.stock || !mounted) return;
    try {
      final maj = await context.read<Api>().majStock(p.id, stock);
      if (!mounted) return;
      _remplacer(maj);
      showMessage(context, 'Stock de « ${maj.nom} » : ${maj.stock}');
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    }
  }

  Future<void> _changerStatut(Produit p, String statut) async {
    try {
      final maj = await context.read<Api>().majStatutProduit(p.id, statut);
      if (!mounted) return;
      _remplacer(maj);
      showMessage(context, '« ${maj.nom} » : ${libelleStatutProduit(maj.statut).toLowerCase()}');
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    }
  }

  Future<void> _supprimer(Produit p) async {
    final ok = await confirmer(
      context,
      'Supprimer le produit',
      'Voulez-vous vraiment supprimer « ${p.nom} » ?',
      action: 'Supprimer',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      final retire = await context.read<Api>().supprimerProduit(p.id);
      if (!mounted) return;
      if (retire) {
        showMessage(context, 'Produit déjà commandé : retiré du catalogue');
        await _charger();
      } else {
        setState(() => _produits = _produits!.where((x) => x.id != p.id).toList());
        showMessage(context, 'Produit supprimé');
      }
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final produits = _produits;
    Widget body;
    if (produits == null && _erreur == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (produits == null) {
      body = RefreshIndicator(
        onRefresh: _charger,
        child: _pleineHauteur(
          EmptyState(
            icon: Icons.cloud_off,
            titre: 'Une erreur est survenue',
            message: '$_erreur',
            action: OutlinedButton.icon(
              onPressed: _charger,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ),
        ),
      );
    } else if (produits.isEmpty) {
      body = RefreshIndicator(
        onRefresh: _charger,
        child: _pleineHauteur(
          EmptyState(
            icon: Icons.inventory_2_outlined,
            titre: 'Aucun produit',
            message: 'Ajoutez votre premier produit pour le proposer aux clients.',
            action: FilledButton.icon(
              onPressed: _ouvrirFormulaire,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un produit'),
            ),
          ),
        ),
      );
    } else {
      final rupture = produits.where((p) => p.stock == 0).length;
      final bas = produits.where((p) => p.stock > 0 && p.stock <= _seuilStockBas).length;
      final publies = produits.where((p) => p.statut == 'publie').length;
      body = RefreshIndicator(
        onRefresh: _charger,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: produits.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            if (i == 0) {
              return Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  Tag('${produits.length} produit${produits.length > 1 ? 's' : ''}', color: Colors.blueGrey),
                  Tag('$publies publié${publies > 1 ? 's' : ''}'),
                  if (bas > 0) Tag('$bas stock bas', color: AppColors.terre),
                  if (rupture > 0) Tag('$rupture en rupture', color: Colors.red.shade700),
                ],
              );
            }
            final p = produits[i - 1];
            return _ProduitCard(
              produit: p,
              onTap: () => _ouvrirFormulaire(p),
              onStock: () => _ajusterStock(p),
              onStatut: (s) => _changerStatut(p, s),
              onSupprimer: () => _supprimer(p),
            );
          },
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: body,
      floatingActionButton: produits == null
          ? null
          : FloatingActionButton.extended(
              heroTag: 'ajouter_produit',
              onPressed: _ouvrirFormulaire,
              icon: const Icon(Icons.add),
              label: const Text('Produit'),
            ),
    );
  }
}

class _ProduitCard extends StatelessWidget {
  const _ProduitCard({
    required this.produit,
    required this.onTap,
    required this.onStock,
    required this.onStatut,
    required this.onSupprimer,
  });

  final Produit produit;
  final VoidCallback onTap;
  final VoidCallback onStock;
  final ValueChanged<String> onStatut;
  final VoidCallback onSupprimer;

  @override
  Widget build(BuildContext context) {
    final p = produit;
    final (libelleStock, couleurStock) = p.stock == 0
        ? ('Rupture de stock', Colors.red.shade700)
        : p.stock <= _seuilStockBas
        ? ('Stock bas : ${p.stock}', AppColors.terre)
        : ('Stock : ${p.stock}', Colors.blueGrey);
    final couleurStatut = switch (p.statut) {
      'publie' => AppColors.vert,
      'brouillon' => const Color(0xFFB26A00),
      _ => Colors.grey.shade700,
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductImage(path: p.image, type: p.typeCategorie, size: 72),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.nom,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [p.categorie, if (p.unite != null && p.unite!.isNotEmpty) p.unite].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fcfa(p.prix),
                      style: const TextStyle(color: AppColors.vert, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Tag(libelleStatutProduit(p.statut), color: couleurStatut),
                        Tag(libelleStock, color: couleurStock),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Actions',
                onSelected: (action) => switch (action) {
                  'modifier' => onTap(),
                  'stock' => onStock(),
                  'supprimer' => onSupprimer(),
                  _ => onStatut(action),
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'modifier',
                    child: ListTile(leading: Icon(Icons.edit), title: Text('Modifier')),
                  ),
                  const PopupMenuItem(
                    value: 'stock',
                    child: ListTile(leading: Icon(Icons.inventory), title: Text('Ajuster le stock')),
                  ),
                  const PopupMenuDivider(),
                  if (p.statut != 'publie')
                    const PopupMenuItem(
                      value: 'publie',
                      child: ListTile(leading: Icon(Icons.public), title: Text('Publier')),
                    ),
                  if (p.statut != 'brouillon')
                    const PopupMenuItem(
                      value: 'brouillon',
                      child: ListTile(leading: Icon(Icons.edit_note), title: Text('Mettre en brouillon')),
                    ),
                  if (p.statut != 'retire')
                    const PopupMenuItem(
                      value: 'retire',
                      child: ListTile(leading: Icon(Icons.block), title: Text('Retirer du catalogue')),
                    ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'supprimer',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: Colors.red.shade700),
                      title: Text('Supprimer', style: TextStyle(color: Colors.red.shade700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockDialog extends StatefulWidget {
  const _StockDialog({required this.produit});
  final Produit produit;

  @override
  State<_StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<_StockDialog> {
  late final _controller = TextEditingController(text: '${widget.produit.stock}');

  int? get _valeur {
    final n = int.tryParse(_controller.text.trim());
    return n == null || n < 0 ? null : n;
  }

  void _ajouter(int delta) {
    final n = (_valeur ?? 0) + delta;
    _controller.text = '${n < 0 ? 0 : n}';
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajuster le stock'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.produit.nom, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton.outlined(onPressed: () => _ajouter(-1), icon: const Icon(Icons.remove)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Quantité en stock',
                    errorText: _valeur == null ? 'Quantité invalide' : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(onPressed: () => _ajouter(1), icon: const Icon(Icons.add)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final d in [10, 50, 100]) ActionChip(label: Text('+$d'), onPressed: () => _ajouter(d)),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: _valeur == null ? null : () => Navigator.pop(context, _valeur),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

// --- Onglet Ventes --------------------------------------------------------------------

class _VentesTab extends StatefulWidget {
  const _VentesTab();

  @override
  State<_VentesTab> createState() => _VentesTabState();
}

class _VentesTabState extends State<_VentesTab> with AutomaticKeepAliveClientMixin {
  List<Vente>? _ventes;
  Object? _erreur;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final ventes = await context.read<Api>().mesVentes();
      if (mounted) {
        setState(() {
          _ventes = ventes;
          _erreur = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (_ventes == null) {
        setState(() => _erreur = e);
      } else {
        showMessage(context, e, erreur: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ventes = _ventes;
    if (ventes == null && _erreur == null) return const Center(child: CircularProgressIndicator());
    if (ventes == null) {
      return RefreshIndicator(
        onRefresh: _charger,
        child: _pleineHauteur(
          EmptyState(
            icon: Icons.cloud_off,
            titre: 'Une erreur est survenue',
            message: '$_erreur',
            action: OutlinedButton.icon(
              onPressed: _charger,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ),
        ),
      );
    }
    if (ventes.isEmpty) {
      return RefreshIndicator(
        onRefresh: _charger,
        child: _pleineHauteur(
          const EmptyState(
            icon: Icons.receipt_long_outlined,
            titre: 'Aucune vente pour le moment',
            message: 'Les commandes payées contenant vos produits apparaîtront ici.',
          ),
        ),
      );
    }

    // Regroupement par commande (l'API renvoie une ligne par article, triées par date).
    final commandes = <int, List<Vente>>{};
    for (final v in ventes) {
      commandes.putIfAbsent(v.idCommande, () => []).add(v);
    }
    final total = ventes.fold<int>(0, (s, v) => s + v.montant);
    final encaisse = ventes.where((v) => v.statut == StatutCommande.livree).fold<int>(0, (s, v) => s + v.montant);
    final articles = ventes.fold<int>(0, (s, v) => s + v.quantite);

    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: AppColors.vert,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Chiffre d’affaires', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(
                    fcfa(total),
                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${commandes.length} commande${commandes.length > 1 ? 's' : ''} · $articles article${articles > 1 ? 's' : ''} · '
                    'livré : ${fcfa(encaisse)}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('Commandes'),
          for (final entry in commandes.entries) ...[
            _VenteCard(idCommande: entry.key, lignes: entry.value),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _VenteCard extends StatelessWidget {
  const _VenteCard({required this.idCommande, required this.lignes});

  final int idCommande;
  final List<Vente> lignes;

  @override
  Widget build(BuildContext context) {
    final premiere = lignes.first;
    final total = lignes.fold<int>(0, (s, v) => s + v.montant);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(commandeId: idCommande))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Commande #$idCommande', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  StatusChip(premiere.statut),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                [dateHeure(premiere.date), if (premiere.ville.isNotEmpty) premiere.ville].join(' · '),
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const Divider(height: 20),
              for (final l in lignes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('${l.produit} × ${l.quantite}', maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Text(fcfa(l.montant)),
                    ],
                  ),
                ),
              if (lignes.length > 1) ...[const Divider(height: 16), AmountRow('Total', fcfa(total), bold: true)],
            ],
          ),
        ),
      ),
    );
  }
}

// --- Onglet Boutique ------------------------------------------------------------------

class _BoutiqueTab extends StatelessWidget {
  const _BoutiqueTab({required this.boutique, required this.onChanged});

  final Boutique boutique;
  final ValueChanged<Boutique> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _BoutiqueForm(
          key: ValueKey(boutique.id),
          initiale: boutique,
          labelAction: 'Enregistrer',
          icon: Icons.check,
          onSubmit: (data) async {
            final api = context.read<Api>();
            final auth = context.read<AuthState>();
            final b = await api.modifierBoutique(data);
            onChanged(b);
            if (context.mounted) showMessage(context, 'Boutique mise à jour');
            // Met à jour le résumé de boutique du compte (nom affiché ailleurs).
            try {
              await auth.rafraichir();
            } catch (_) {}
          },
        ),
      ],
    );
  }
}

/// Formulaire d'informations de boutique (création et modification).
class _BoutiqueForm extends StatefulWidget {
  const _BoutiqueForm({
    super.key,
    this.initiale,
    required this.labelAction,
    required this.icon,
    required this.onSubmit,
  });

  final Boutique? initiale;
  final String labelAction;
  final IconData icon;
  final Future<void> Function(Map<String, dynamic> data) onSubmit;

  @override
  State<_BoutiqueForm> createState() => _BoutiqueFormState();
}

class _BoutiqueFormState extends State<_BoutiqueForm> {
  final _formKey = GlobalKey<FormState>();
  late final _nom = TextEditingController(text: widget.initiale?.nom);
  late final _description = TextEditingController(text: widget.initiale?.description);
  late final _adresse = TextEditingController(text: widget.initiale?.adresse);
  late final _ville = TextEditingController(text: widget.initiale?.ville);
  late final _telephone = TextEditingController(text: widget.initiale?.telephone);

  @override
  void dispose() {
    for (final c in [_nom, _description, _adresse, _ville, _telephone]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _texte(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _valider() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await widget.onSubmit({
      'nom': _nom.text.trim(),
      'description': _texte(_description),
      'adresse': _texte(_adresse),
      'ville': _texte(_ville),
      'telephone': _texte(_telephone),
    });
  }

  @override
  Widget build(BuildContext context) {
    const espace = SizedBox(height: 12);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _nom,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nom de la boutique *', prefixIcon: Icon(Icons.storefront)),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Nom obligatoire' : null,
          ),
          espace,
          TextFormField(
            controller: _description,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true),
          ),
          espace,
          TextFormField(
            controller: _adresse,
            decoration: const InputDecoration(labelText: 'Adresse', prefixIcon: Icon(Icons.place_outlined)),
          ),
          espace,
          TextFormField(
            controller: _ville,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Ville', prefixIcon: Icon(Icons.location_city)),
          ),
          espace,
          TextFormField(
            controller: _telephone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Téléphone',
              prefixIcon: const Icon(Icons.phone_outlined),
              helperText: widget.initiale == null ? 'Par défaut : le numéro de votre compte' : null,
            ),
          ),
          const SizedBox(height: 24),
          BusyButton(label: widget.labelAction, icon: widget.icon, onPressed: _valider),
        ],
      ),
    );
  }
}

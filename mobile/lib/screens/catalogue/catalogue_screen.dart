import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../auth/auth_gate.dart';
import '../notifications/notifications_screen.dart';
import 'product_detail_screen.dart';

/// Consulter le catalogue, rechercher des produits, des catégories et des prix.
class CatalogueScreen extends StatefulWidget {
  const CatalogueScreen({super.key, this.onOpenCart});

  final VoidCallback? onOpenCart;

  @override
  State<CatalogueScreen> createState() => _CatalogueScreenState();
}

class _Filtres {
  String? type;
  int? categorie;
  int? prixMin;
  int? prixMax;
  bool enStock = false;
  String? tri;

  int get actifs => [prixMin, prixMax, tri].where((e) => e != null).length + (enStock ? 1 : 0);
}

class _CatalogueScreenState extends State<CatalogueScreen> {
  final _recherche = TextEditingController();
  final _filtres = _Filtres();
  Timer? _debounce;
  late Future<List<Produit>> _produits;
  List<Categorie> _categories = [];
  int _notifications = 0;

  Api get _api => context.read<Api>();

  @override
  void initState() {
    super.initState();
    _produits = _chargerProduits();
    _api.categories().then((c) => mounted ? setState(() => _categories = c) : null).catchError((_) {});
    _chargerNotifications();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _chargerNotifications() async {
    if (!context.read<AuthState>().connecte) return;
    try {
      final (n, _) = await _api.notifications();
      if (mounted) setState(() => _notifications = n);
    } catch (_) {}
  }

  Future<List<Produit>> _chargerProduits() => _api.produits(
    q: _recherche.text.trim(),
    type: _filtres.type,
    categorie: _filtres.categorie,
    prixMin: _filtres.prixMin,
    prixMax: _filtres.prixMax,
    enStock: _filtres.enStock,
    tri: _filtres.tri,
  );

  void _actualiser() => setState(() {
    _produits = _chargerProduits();
  });

  void _onRecherche(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _actualiser);
  }

  Future<void> _ouvrirFiltres() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FiltresSheet(filtres: _filtres),
    );
    if (ok == true) _actualiser();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesVisibles = _categories.where((c) => _filtres.type == null || c.type == _filtres.type).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AgroPhyto',
          style: TextStyle(color: AppColors.vert, fontWeight: FontWeight.w800),
        ),
        actions: [
          if (!context.watch<AuthState>().connecte)
            TextButton.icon(
              onPressed: () => exigerConnexion(context),
              icon: const Icon(Icons.login),
              label: const Text('Se connecter'),
            )
          else
            IconButton(
              tooltip: 'Notifications',
              icon: Badge(
                isLabelVisible: _notifications > 0,
                label: Text('$_notifications'),
                child: const Icon(Icons.notifications_outlined),
              ),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                if (mounted) _chargerNotifications();
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _actualiser();
          _chargerNotifications();
          await _produits.catchError((_) => <Produit>[]);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _recherche,
                        onChanged: _onRecherche,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Rechercher un produit, une catégorie…',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _recherche.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _recherche.clear();
                                    _actualiser();
                                  },
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Filtres et tri',
                      onPressed: _ouvrirFiltres,
                      icon: Badge(
                        isLabelVisible: _filtres.actifs > 0,
                        label: Text('${_filtres.actifs}'),
                        child: const Icon(Icons.tune),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  children: [
                    for (final (type, label) in [
                      (null, 'Tout'),
                      ('phytosanitaire', 'Phytosanitaires'),
                      ('elevage', 'Élevage'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: _filtres.type == type,
                          onSelected: (_) {
                            _filtres
                              ..type = type
                              ..categorie = null;
                            _actualiser();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (categoriesVisibles.isNotEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final c in categoriesVisibles)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text('${c.nom} (${c.nbProduits})'),
                            selected: _filtres.categorie == c.id,
                            onSelected: (s) {
                              _filtres.categorie = s ? c.id : null;
                              _actualiser();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            FutureBuilder<List<Produit>>(
              future: _produits,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
                }
                if (snap.hasError) {
                  return SliverFillRemaining(
                    child: EmptyState(
                      icon: Icons.cloud_off,
                      titre: 'Catalogue indisponible',
                      message: '${snap.error}',
                      action: OutlinedButton(onPressed: _actualiser, child: const Text('Réessayer')),
                    ),
                  );
                }
                final produits = snap.data!;
                if (produits.isEmpty) {
                  return const SliverFillRemaining(
                    child: EmptyState(
                      icon: Icons.search_off,
                      titre: 'Aucun produit trouvé',
                      message: 'Modifiez votre recherche ou vos filtres.',
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 240,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.62,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => ProductCard(produit: produits[i]),
                      childCount: produits.length,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.produit});

  final Produit produit;

  Future<void> _ajouter(BuildContext context) async {
    if (!await exigerConnexion(context, raison: 'Connectez-vous pour ajouter des produits au panier')) return;
    if (!context.mounted) return;
    try {
      await context.read<CartState>().ajouter(produit.id);
      if (context.mounted) showMessage(context, '${produit.nom} ajouté au panier');
    } catch (e) {
      if (context.mounted) showMessage(context, e, erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(produitId: produit.id))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductImage(path: produit.image, type: produit.typeCategorie, radius: 0),
                  if (!produit.enStock) const Positioned(left: 8, top: 8, child: Tag('Rupture', color: Colors.red)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(produit.categorie, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  const SizedBox(height: 2),
                  Text(
                    produit.nom,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (produit.nbAvis > 0)
                    Row(
                      children: [
                        RatingStars(note: produit.noteMoyenne, size: 12),
                        Text(' (${produit.nbAvis})', style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      fcfa(produit.prix),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.vert),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ajouter au panier',
                    visualDensity: VisualDensity.compact,
                    onPressed: produit.enStock ? () => _ajouter(context) : null,
                    icon: const Icon(Icons.add_shopping_cart),
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

class _FiltresSheet extends StatefulWidget {
  const _FiltresSheet({required this.filtres});
  final _Filtres filtres;

  @override
  State<_FiltresSheet> createState() => _FiltresSheetState();
}

class _FiltresSheetState extends State<_FiltresSheet> {
  late final _min = TextEditingController(text: widget.filtres.prixMin?.toString() ?? '');
  late final _max = TextEditingController(text: widget.filtres.prixMax?.toString() ?? '');
  late String? _tri = widget.filtres.tri;
  late bool _enStock = widget.filtres.enStock;

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Filtres', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          const Text('Prix (FCFA)'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _min,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Minimum'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _max,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Maximum'),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Uniquement les produits en stock'),
            value: _enStock,
            onChanged: (v) => setState(() => _enStock = v),
          ),
          DropdownButtonFormField<String?>(
            initialValue: _tri,
            decoration: const InputDecoration(labelText: 'Trier par'),
            items: const [
              DropdownMenuItem(value: null, child: Text('Nouveautés')),
              DropdownMenuItem(value: 'prix_asc', child: Text('Prix croissant')),
              DropdownMenuItem(value: 'prix_desc', child: Text('Prix décroissant')),
              DropdownMenuItem(value: 'note', child: Text('Mieux notés')),
              DropdownMenuItem(value: 'nom', child: Text('Nom (A-Z)')),
            ],
            onChanged: (v) => setState(() => _tri = v),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    widget.filtres
                      ..prixMin = null
                      ..prixMax = null
                      ..enStock = false
                      ..tri = null;
                    Navigator.pop(context, true);
                  },
                  child: const Text('Réinitialiser'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    widget.filtres
                      ..prixMin = int.tryParse(_min.text)
                      ..prixMax = int.tryParse(_max.text)
                      ..enStock = _enStock
                      ..tri = _tri;
                    Navigator.pop(context, true);
                  },
                  child: const Text('Appliquer'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

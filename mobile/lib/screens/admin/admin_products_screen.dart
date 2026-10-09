import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../vendeur/product_form_screen.dart';

const _statutsProduit = ['publie', 'brouillon', 'retire'];

Color _couleurStatutProduit(String statut) => switch (statut) {
  'publie' => AppColors.vert,
  'brouillon' => const Color(0xFFB26A00),
  _ => Colors.grey.shade700,
};

/// Supervision des produits de toutes les boutiques.
class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> {
  final _recherche = TextEditingController();
  Future<List<Produit>>? _future;
  String? _statut;

  @override
  void initState() {
    super.initState();
    _charger();
    _recherche.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  void _charger() => _future = context.read<Api>().produitsGestion();

  Future<void> _rafraichir() async {
    setState(_charger);
    try {
      await _future;
    } catch (_) {}
  }

  List<Produit> _filtrer(List<Produit> produits) {
    final q = _recherche.text.trim().toLowerCase();
    return produits.where((p) {
      if (_statut != null && p.statut != _statut) return false;
      if (q.isEmpty) return true;
      return [p.nom, p.categorie, p.boutique ?? '', p.villeBoutique ?? ''].any((s) => s.toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _formulaire([Produit? produit]) async {
    final enregistre = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ProductFormScreen(produit: produit)),
    );
    if (enregistre == true && mounted) _rafraichir();
  }

  Future<void> _changerStatut(Produit p, String statut) async {
    try {
      await context.read<Api>().majStatutProduit(p.id, statut);
      if (!mounted) return;
      showMessage(context, '« ${p.nom} » : ${libelleStatutProduit(statut).toLowerCase()}');
      _rafraichir();
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    }
  }

  Future<void> _supprimer(Produit p) async {
    final ok = await confirmer(
      context,
      'Supprimer le produit',
      'Supprimer « ${p.nom} » ? Un produit déjà commandé sera seulement retiré du catalogue.',
      action: 'Supprimer',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      final retire = await context.read<Api>().supprimerProduit(p.id);
      if (!mounted) return;
      showMessage(context, retire ? 'Produit déjà commandé : retiré du catalogue' : 'Produit supprimé');
      _rafraichir();
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Produits')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _formulaire(),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _recherche,
              decoration: InputDecoration(
                hintText: 'Produit, catégorie, boutique…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _recherche.text.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.clear), onPressed: _recherche.clear),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                for (final s in [null, ..._statutsProduit])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s == null ? 'Tous' : libelleStatutProduit(s)),
                      selected: _statut == s,
                      onSelected: (_) => setState(() => _statut = s),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _rafraichir,
              child: AsyncView<List<Produit>>(
                future: _future,
                onRetry: () => setState(_charger),
                builder: (context, tous) {
                  final produits = _filtrer(tous);
                  if (produits.isEmpty) {
                    return ListView(
                      children: [
                        const SizedBox(height: 60),
                        EmptyState(
                          icon: Icons.inventory_2_outlined,
                          titre: tous.isEmpty ? 'Aucun produit' : 'Aucun produit ne correspond',
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: produits.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Text(
                          '${produits.length} produit${produits.length > 1 ? 's' : ''}',
                          style: TextStyle(color: Colors.grey.shade600),
                        );
                      }
                      return _ProduitCard(
                        produit: produits[i - 1],
                        onModifier: _formulaire,
                        onStatut: _changerStatut,
                        onSupprimer: _supprimer,
                      );
                    },
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

class _ProduitCard extends StatelessWidget {
  const _ProduitCard({
    required this.produit,
    required this.onModifier,
    required this.onStatut,
    required this.onSupprimer,
  });

  final Produit produit;
  final void Function(Produit) onModifier;
  final void Function(Produit, String) onStatut;
  final void Function(Produit) onSupprimer;

  @override
  Widget build(BuildContext context) {
    final p = produit;
    final stockCouleur = p.stock == 0 ? Colors.red.shade700 : (p.stock <= 5 ? AppColors.terre : Colors.grey.shade700);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onModifier(p),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 0, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductImage(path: p.image, type: p.typeCategorie, size: 64, radius: 10),
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
                      [p.boutique ?? 'Sans boutique', p.categorie].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          fcfa(p.prix),
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.vert),
                        ),
                        Text(
                          'Stock : ${p.stock}${p.unite == null ? '' : ' ${p.unite}'}',
                          style: TextStyle(color: stockCouleur, fontSize: 12),
                        ),
                        Tag(libelleStatutProduit(p.statut), color: _couleurStatutProduit(p.statut)),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Actions',
                onSelected: (v) => switch (v) {
                  'modifier' => onModifier(p),
                  'supprimer' => onSupprimer(p),
                  _ => onStatut(p, v),
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'modifier',
                    child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Modifier')),
                  ),
                  const PopupMenuDivider(),
                  for (final s in _statutsProduit.where((s) => s != p.statut))
                    PopupMenuItem(
                      value: s,
                      child: ListTile(
                        leading: Icon(switch (s) {
                          'publie' => Icons.public,
                          'brouillon' => Icons.edit_note,
                          _ => Icons.visibility_off_outlined,
                        }, color: _couleurStatutProduit(s)),
                        title: Text(switch (s) {
                          'publie' => 'Publier',
                          'brouillon' => 'Passer en brouillon',
                          _ => 'Retirer du catalogue',
                        }),
                      ),
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

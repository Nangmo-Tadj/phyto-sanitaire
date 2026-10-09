import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../catalogue/product_detail_screen.dart';
import 'checkout_screen.dart';

/// Cas « Gestion du panier » : ajout, modification de quantité, suppression, total.
class CartScreen extends StatelessWidget {
  const CartScreen({super.key, this.onBrowse});

  final VoidCallback? onBrowse;

  Future<void> _action(BuildContext context, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (context.mounted) showMessage(context, e, erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartState>();
    final panier = cart.panier;
    return Scaffold(
      appBar: AppBar(
        title: Text('Mon panier${panier.nombreArticles > 0 ? ' (${panier.nombreArticles})' : ''}'),
        actions: [
          if (!panier.estVide)
            IconButton(
              tooltip: 'Vider le panier',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                if (await confirmer(
                  context,
                  'Vider le panier',
                  'Retirer tous les produits du panier ?',
                  action: 'Vider',
                  danger: true,
                )) {
                  if (context.mounted) await _action(context, cart.vider);
                }
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _action(context, cart.charger),
        child: panier.estVide
            ? ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.6,
                    child: cart.chargement
                        ? const Center(child: CircularProgressIndicator())
                        : EmptyState(
                            icon: Icons.shopping_cart_outlined,
                            titre: 'Votre panier est vide',
                            message: 'Parcourez le catalogue pour trouver vos produits.',
                            action: onBrowse == null
                                ? null
                                : FilledButton(onPressed: onBrowse, child: const Text('Voir le catalogue')),
                          ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: panier.items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _CartItemTile(item: panier.items[i], onAction: (f) => _action(context, f)),
              ),
      ),
      bottomNavigationBar: panier.estVide
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AmountRow('Sous-total', fcfa(panier.sousTotal)),
                    Text(
                      'Frais de livraison calculés selon la ville à l’étape suivante',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: panier.items.every((i) => i.disponible && i.quantite <= i.stock)
                            ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutScreen()))
                            : null,
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Procéder au paiement'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({required this.item, required this.onAction});

  final PanierItem item;
  final Future<void> Function(Future<void> Function()) onAction;

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartState>();
    final probleme = !item.disponible
        ? 'Produit indisponible'
        : item.quantite > item.stock
        ? 'Stock insuffisant (${item.stock} disponible(s))'
        : null;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(produitId: item.idProduit))),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductImage(path: item.image, size: 76),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.nom,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${fcfa(item.prix)}${item.unite != null ? ' / ${item.unite}' : ''}',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                    ),
                    if (probleme != null) Text(probleme, style: const TextStyle(color: Colors.red, fontSize: 12)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        QuantitySelector(
                          value: item.quantite,
                          max: item.stock,
                          onChanged: (q) => onAction(() => cart.modifier(item.idProduit, q)),
                        ),
                        const Spacer(),
                        Text(fcfa(item.totalLigne), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Retirer',
                icon: const Icon(Icons.close),
                onPressed: () => onAction(() => cart.retirer(item.idProduit)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

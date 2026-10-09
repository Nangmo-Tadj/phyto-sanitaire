import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../auth/auth_gate.dart';
import '../messages/chat_screen.dart';

/// Voir les détails d'un produit, ses avis, l'ajouter au panier, contacter le vendeur.
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.produitId});

  final int produitId;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Future<(Produit, List<Avis>)> _data;
  int _quantite = 1;

  Api get _api => context.read<Api>();

  @override
  void initState() {
    super.initState();
    _data = _charger();
  }

  Future<(Produit, List<Avis>)> _charger() async {
    final res = await Future.wait([_api.produit(widget.produitId), _api.avisProduit(widget.produitId)]);
    return (res[0] as Produit, res[1] as List<Avis>);
  }

  void _recharger() => setState(() {
    _data = _charger();
  });

  Future<void> _ajouterAuPanier(Produit p) async {
    if (!await exigerConnexion(context, raison: 'Connectez-vous pour ajouter des produits au panier')) return;
    if (!mounted) return;
    await context.read<CartState>().ajouter(p.id, _quantite);
    if (mounted) showMessage(context, '$_quantite × ${p.nom} ajouté au panier');
  }

  Future<void> _contacterVendeur(Produit p) async {
    if (!await exigerConnexion(context, raison: 'Connectez-vous pour écrire au vendeur')) return;
    if (!mounted) return;
    int? id = p.idVendeur;
    String nom = p.boutique ?? 'Vendeur';
    String? tel = p.telephoneBoutique;
    if (id == null) {
      try {
        final support = await _api.support();
        id = support['id_user'] as int;
        nom = 'Service client AgroPhyto';
        tel = support['telephone'] as String?;
      } catch (e) {
        if (mounted) showMessage(context, e, erreur: true);
        return;
      }
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(idUser: id!, nom: nom, telephone: tel),
      ),
    );
  }

  Future<void> _donnerAvis(Produit p) async {
    if (!await exigerConnexion(context, raison: 'Connectez-vous pour donner votre avis')) return;
    if (!mounted) return;
    final result = await showDialog<(int, String)>(
      context: context,
      builder: (_) => const AvisDialog(titre: 'Votre avis sur ce produit'),
    );
    if (result == null) return;
    try {
      await _api.donnerAvisProduit(p.id, result.$1, result.$2);
      if (!mounted) return;
      showMessage(context, 'Merci pour votre avis !');
      _recharger();
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monId = context.watch<AuthState>().user?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Détails du produit')),
      body: AsyncView<(Produit, List<Avis>)>(
        future: _data,
        onRetry: _recharger,
        builder: (context, data) {
          final (p, avis) = data;
          final estMonProduit = monId != null && p.idVendeur == monId;
          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    _recharger();
                    await _data.then((_) {}, onError: (_) {});
                  },
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      AspectRatio(
                        aspectRatio: 1.4,
                        child: ProductImage(path: p.image, type: p.typeCategorie),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        children: [
                          Tag(p.categorie, color: p.typeCategorie == 'elevage' ? AppColors.elevage : AppColors.vert),
                          if (p.unite != null) Tag(p.unite!, color: Colors.blueGrey),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        p.nom,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          RatingStars(note: p.noteMoyenne),
                          const SizedBox(width: 6),
                          Text(p.nbAvis == 0 ? 'Aucun avis' : '${p.noteMoyenne} · ${p.nbAvis} avis'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        fcfa(p.prix),
                        style: Theme.of(
                          context,
                        ).textTheme.headlineSmall?.copyWith(color: AppColors.vert, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.enStock ? '${p.stock} disponible(s)' : 'Rupture de stock',
                        style: TextStyle(
                          color: p.enStock
                              ? (p.stock <= 5 ? Colors.orange.shade800 : Colors.grey.shade700)
                              : Colors.red,
                        ),
                      ),
                      if (p.description != null && p.description!.isNotEmpty) ...[
                        const SectionTitle('Description'),
                        Text(p.description!, style: const TextStyle(height: 1.4)),
                      ],
                      const SectionTitle('Vendu par'),
                      Card(
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.storefront)),
                          title: Text(p.boutique ?? 'AgroPhyto (plateforme)'),
                          subtitle: p.villeBoutique == null ? null : Text(p.villeBoutique!),
                          trailing: estMonProduit
                              ? null
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (p.telephoneBoutique != null)
                                      IconButton(
                                        tooltip: 'Appeler',
                                        icon: const Icon(Icons.call),
                                        onPressed: () => launchUrl(Uri(scheme: 'tel', path: p.telephoneBoutique)),
                                      ),
                                    IconButton(
                                      tooltip: 'Écrire',
                                      icon: const Icon(Icons.chat_outlined),
                                      onPressed: () => _contacterVendeur(p),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      SectionTitle(
                        'Avis des clients',
                        trailing: TextButton.icon(
                          onPressed: () => _donnerAvis(p),
                          icon: const Icon(Icons.rate_review_outlined),
                          label: const Text('Donner mon avis'),
                        ),
                      ),
                      if (avis.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            'Soyez le premier à donner votre avis après achat.',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      for (final a in avis)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(a.auteur, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      const Spacer(),
                                      Text(
                                        dateCourte(a.date),
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  RatingStars(note: a.note.toDouble(), size: 14),
                                  if (a.commentaire != null && a.commentaire!.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(a.commentaire!),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    children: [
                      QuantitySelector(
                        value: _quantite,
                        max: p.stock < 1 ? 1 : p.stock,
                        onChanged: p.enStock ? (v) => setState(() => _quantite = v) : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: BusyButton(
                          label: p.enStock ? 'Ajouter au panier' : 'Indisponible',
                          icon: Icons.add_shopping_cart,
                          onPressed: p.enStock ? () => _ajouterAuPanier(p) : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Saisie d'une note (1 à 5) et d'un commentaire. Renvoie (note, commentaire).
class AvisDialog extends StatefulWidget {
  const AvisDialog({super.key, required this.titre});
  final String titre;

  @override
  State<AvisDialog> createState() => _AvisDialogState();
}

class _AvisDialogState extends State<AvisDialog> {
  int _note = 0;
  final _commentaire = TextEditingController();

  @override
  void dispose() {
    _commentaire.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titre),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RatingStars(note: _note.toDouble(), size: 32, onChanged: (n) => setState(() => _note = n)),
          const SizedBox(height: 12),
          TextField(
            controller: _commentaire,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Commentaire (facultatif)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: _note == 0 ? null : () => Navigator.pop(context, (_note, _commentaire.text.trim())),
          child: const Text('Envoyer'),
        ),
      ],
    );
  }
}

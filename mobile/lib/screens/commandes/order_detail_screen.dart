import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../state/app_state.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../catalogue/product_detail_screen.dart';
import '../panier/payment_screen.dart';

/// Suivre une commande : statut, articles, paiements, livraison, avis.
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.commandeId});

  final int commandeId;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late Future<Commande> _commande;

  Api get _api => context.read<Api>();

  @override
  void initState() {
    super.initState();
    _commande = _api.commande(widget.commandeId);
  }

  Future<void> _recharger() async {
    setState(() {
      _commande = _api.commande(widget.commandeId);
    });
    try {
      await _commande;
    } catch (_) {
      // L'erreur est affichée par AsyncView.
    }
  }

  Future<void> _annuler(Commande c) async {
    if (!await confirmer(
      context,
      'Annuler la commande',
      'Voulez-vous vraiment annuler la commande #${c.id} ?',
      action: 'Annuler la commande',
      danger: true,
    )) {
      return;
    }
    if (!mounted) return;
    try {
      await _api.annulerCommande(c.id);
      if (mounted) {
        showMessage(context, 'Commande annulée');
        _recharger();
      }
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    }
  }

  Future<void> _noter(Commande c) async {
    final r = await showDialog<(int, String)>(
      context: context,
      builder: (_) => const AvisDialog(titre: 'Notez votre commande'),
    );
    if (r == null || !mounted) return;
    try {
      await _api.noterCommande(c.id, r.$1, r.$2);
      if (mounted) {
        showMessage(context, 'Merci pour votre avis !');
        _recharger();
      }
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monId = context.read<AuthState>().user?.id;
    return Scaffold(
      appBar: AppBar(title: Text('Commande #${widget.commandeId}')),
      body: RefreshIndicator(
        onRefresh: _recharger,
        child: AsyncView<Commande>(
          future: _commande,
          onRetry: _recharger,
          builder: (context, c) {
            final estClient = c.idUser == monId;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Passée le ${dateHeure(c.date)}',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ),
                            StatusChip(c.statut),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _Suivi(commande: c),
                        if (c.motifEchec != null && c.statut == StatutCommande.echecLivraison) ...[
                          const SizedBox(height: 8),
                          Text('Motif : ${c.motifEchec}', style: const TextStyle(color: Colors.red)),
                        ],
                      ],
                    ),
                  ),
                ),
                if (estClient && c.payable) ...[
                  const SizedBox(height: 12),
                  if (c.paiementEnCours)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.hourglass_top),
                        title: Text('Paiement en cours de confirmation…'),
                      ),
                    )
                  else
                    FilledButton.icon(
                      onPressed: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentScreen(commande: c, depuisDetail: true)));
                        if (mounted) _recharger();
                      },
                      icon: const Icon(Icons.payments_outlined),
                      label: Text('Payer ${fcfa(c.total)}'),
                    ),
                ],
                const SectionTitle('Livraison'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.location_on_outlined),
                        title: Text(c.adresse),
                        subtitle: Text(c.ville),
                      ),
                      ListTile(
                        leading: const Icon(Icons.phone_outlined),
                        title: Text(c.telephoneLivraison),
                        subtitle: c.client == null ? null : Text('Client : ${c.client}'),
                        trailing: estClient
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.call),
                                onPressed: () => launchUrl(Uri(scheme: 'tel', path: c.telephoneLivraison)),
                              ),
                      ),
                      if (c.livreur != null)
                        ListTile(
                          leading: const Icon(Icons.delivery_dining),
                          title: Text('Livreur : ${c.livreur}'),
                          subtitle: c.dateLivraison == null ? null : Text('Livrée le ${dateHeure(c.dateLivraison)}'),
                          trailing: c.livreurTelephone == null || !estClient
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.call),
                                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: c.livreurTelephone)),
                                ),
                        ),
                    ],
                  ),
                ),
                const SectionTitle('Articles'),
                Card(
                  child: Column(
                    children: [
                      for (final i in c.items)
                        ListTile(
                          leading: ProductImage(path: i.image, size: 44, radius: 8),
                          title: Text(i.nom),
                          subtitle: Text('${i.quantite} × ${fcfa(i.prixUnitaire)}'),
                          trailing: Text(fcfa(i.totalLigne), style: const TextStyle(fontWeight: FontWeight.w600)),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ProductDetailScreen(produitId: i.idProduit)),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Column(
                          children: [
                            const Divider(),
                            AmountRow('Sous-total', fcfa(c.sousTotal)),
                            AmountRow('Frais de livraison', c.fraisLivraison == 0 ? 'Offerts' : fcfa(c.fraisLivraison)),
                            AmountRow('Total', fcfa(c.total), bold: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (c.paiements.isNotEmpty) ...[
                  const SectionTitle('Paiements'),
                  Card(
                    child: Column(
                      children: [
                        for (final p in c.paiements)
                          ListTile(
                            leading: Icon(
                              p.statut == 'reussi'
                                  ? Icons.check_circle
                                  : p.statut == 'echoue'
                                  ? Icons.cancel
                                  : Icons.hourglass_top,
                              color: p.statut == 'reussi'
                                  ? Colors.green
                                  : p.statut == 'echoue'
                                  ? Colors.red
                                  : Colors.orange,
                            ),
                            title: Text('${libelleModePaiement(p.mode)} · ${fcfa(p.montant)}'),
                            subtitle: Text(
                              [
                                dateHeure(p.date),
                                if (p.numeroFacture != null) 'Facture ${p.numeroFacture}',
                                if (p.statut == 'echoue' && p.message != null) p.message!,
                              ].join('\n'),
                            ),
                            isThreeLine: p.numeroFacture != null || p.statut == 'echoue',
                          ),
                      ],
                    ),
                  ),
                ],
                if (estClient) ...[
                  const SizedBox(height: 16),
                  if (c.statut == StatutCommande.livree)
                    c.noteAvis == null
                        ? OutlinedButton.icon(
                            onPressed: () => _noter(c),
                            icon: const Icon(Icons.star_outline),
                            label: const Text('Noter cette commande'),
                          )
                        : Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Votre note : '),
                                RatingStars(note: c.noteAvis!.toDouble()),
                              ],
                            ),
                          ),
                  if (c.payable && !c.paiementEnCours)
                    TextButton.icon(
                      onPressed: () => _annuler(c),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Annuler la commande'),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Frise de suivi : commande → payée → en livraison → livrée.
class _Suivi extends StatelessWidget {
  const _Suivi({required this.commande});
  final Commande commande;

  @override
  Widget build(BuildContext context) {
    if (commande.statut == StatutCommande.annulee) {
      return const Row(
        children: [
          Icon(Icons.block, color: Colors.grey),
          SizedBox(width: 8),
          Text('Cette commande a été annulée.'),
        ],
      );
    }
    const etapes = [
      (StatutCommande.enAttentePaiement, 'Commandée', Icons.receipt_long),
      (StatutCommande.enCours, 'Payée', Icons.payments),
      (StatutCommande.enLivraison, 'En route', Icons.local_shipping),
      (StatutCommande.livree, 'Livrée', Icons.home),
    ];
    final echec = commande.statut == StatutCommande.echecLivraison;
    final courant = echec ? 2 : etapes.indexWhere((e) => e.$1 == commande.statut);
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        for (var i = 0; i < etapes.length; i++) ...[
          Column(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: i <= courant ? (echec && i == courant ? Colors.red : primary) : Colors.grey.shade300,
                child: Icon(echec && i == courant ? Icons.error_outline : etapes[i].$3, size: 18, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(echec && i == courant ? 'Échec' : etapes[i].$2, style: const TextStyle(fontSize: 11)),
            ],
          ),
          if (i < etapes.length - 1)
            Expanded(
              child: Container(
                height: 3,
                margin: const EdgeInsets.only(bottom: 18),
                color: i < courant ? primary : Colors.grey.shade300,
              ),
            ),
        ],
      ],
    );
  }
}

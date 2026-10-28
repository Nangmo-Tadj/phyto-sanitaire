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
import 'receipt_screen.dart';

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

  Future<void> _confirmerReception(Commande c) async {
    if (!await confirmer(
      context,
      'Confirmer la réception',
      'Avez-vous bien reçu tous les articles de la commande #${c.id} ?',
      action: 'Oui, j’ai tout reçu',
    )) {
      return;
    }
    if (!mounted) return;
    try {
      await _api.confirmerReception(c.id);
      if (mounted) {
        showMessage(context, 'Merci ! Commande clôturée.');
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
      appBar: AppBar(title: Text('Suivi de la commande #${widget.commandeId}')),
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
                        if (c.historique.length > 1) _Historique(etapes: c.historique),
                      ],
                    ),
                  ),
                ),
                if (estClient && c.statut == StatutCommande.livree) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _confirmerReception(c),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Confirmer la réception'),
                  ),
                ],
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
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => PaymentScreen(commande: c, depuisDetail: true)),
                        );
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
                if (!c.payable && c.statut != StatutCommande.annulee) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptScreen(commande: c))),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: Text(c.paiementReussi?.numeroFacture != null ? 'Voir la facture' : 'Voir le reçu'),
                  ),
                ],
                if (estClient) ...[
                  const SizedBox(height: 16),
                  if (c.livreeOuCloturee)
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

/// Suivi : Reçue → Confirmée → En préparation → En cours de livraison → Livrée → Clôturée,
/// avec la date de chaque étape franchie.
class _Suivi extends StatelessWidget {
  const _Suivi({required this.commande});
  final Commande commande;

  static const _icones = {
    StatutCommande.enAttentePaiement: Icons.receipt_long,
    StatutCommande.enCours: Icons.verified_outlined,
    StatutCommande.enPreparation: Icons.inventory_2_outlined,
    StatutCommande.enLivraison: Icons.local_shipping_outlined,
    StatutCommande.livree: Icons.home_outlined,
    StatutCommande.cloturee: Icons.task_alt,
  };

  /// Date de la dernière entrée de l'historique pour ce statut.
  DateTime? _dateDe(String statut) => commande.historique
      .lastWhere(
        (e) => e.statut == statut,
        orElse: () => EtapeCommande(statut: '', libelle: ''),
      )
      .date;

  @override
  Widget build(BuildContext context) {
    if (commande.statut == StatutCommande.annulee) {
      return Row(
        children: [
          const Icon(Icons.block, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Cette commande a été annulée${_dateDe(StatutCommande.annulee) == null ? '' : ' le ${dateHeure(_dateDe(StatutCommande.annulee))}'}.',
            ),
          ),
        ],
      );
    }
    final echec = commande.statut == StatutCommande.echecLivraison;
    // En échec, la tournée (étape « En cours de livraison ») est l'étape en erreur.
    final courant = echec
        ? StatutCommande.etapes.indexOf(StatutCommande.enLivraison)
        : StatutCommande.etapes.indexOf(commande.statut);
    final primary = Theme.of(context).colorScheme.primary;
    final etapes = StatutCommande.etapes;
    return Column(
      children: [
        for (var i = 0; i < etapes.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 36,
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: echec && i == courant
                            ? Colors.red
                            : i <= courant
                            ? primary
                            : Colors.grey.shade300,
                        child: Icon(
                          echec && i == courant ? Icons.error_outline : _icones[etapes[i]],
                          size: 17,
                          color: Colors.white,
                        ),
                      ),
                      if (i < etapes.length - 1)
                        Expanded(child: Container(width: 3, color: i < courant ? primary : Colors.grey.shade300)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          echec && i == courant ? 'Échec de livraison' : libelleStatut(etapes[i]),
                          style: TextStyle(
                            fontWeight: i == courant ? FontWeight.bold : FontWeight.w500,
                            color: i <= courant ? null : Colors.grey,
                          ),
                        ),
                        if (i <= courant && _dateDe(echec && i == courant ? commande.statut : etapes[i]) != null)
                          Text(
                            dateHeure(_dateDe(echec && i == courant ? commande.statut : etapes[i])),
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                      ],
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

/// Historique détaillé (commentaires, auteur de chaque changement).
class _Historique extends StatelessWidget {
  const _Historique({required this.etapes});
  final List<EtapeCommande> etapes;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Historique détaillé', style: TextStyle(fontSize: 14)),
        children: [
          for (final e in etapes.reversed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.circle, size: 10, color: couleurStatut(e.statut)),
              minLeadingWidth: 10,
              title: Text(e.libelle),
              subtitle: Text(
                [
                  dateHeure(e.date),
                  if (e.commentaire != null) e.commentaire!,
                  if (e.auteur != null) 'par ${e.auteur}',
                ].join(' · '),
              ),
            ),
        ],
      ),
    );
  }
}

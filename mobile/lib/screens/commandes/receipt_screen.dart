import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/models.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

/// Reçu de commande, ou facture lorsque le paiement en ligne a réussi.
class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({super.key, required this.commande});

  final Commande commande;

  String _texte() {
    final c = commande;
    final p = c.paiementReussi;
    return [
      'fonction Phyto — ${p?.numeroFacture != null ? 'Facture ${p!.numeroFacture}' : 'Reçu de commande'}',
      'Commande #${c.id} du ${dateHeure(c.date)}',
      if (c.client != null) 'Client : ${c.client}',
      'Livraison : ${c.adresse}, ${c.ville} · ${c.telephoneLivraison}',
      '',
      for (final i in c.items) '${i.quantite} × ${i.nom} (${fcfa(i.prixUnitaire)}) = ${fcfa(i.totalLigne)}',
      '',
      'Sous-total : ${fcfa(c.sousTotal)}',
      'Frais de livraison : ${c.fraisLivraison == 0 ? 'offerts' : fcfa(c.fraisLivraison)}',
      'Total : ${fcfa(c.total)}',
      if (p != null) 'Payé par ${libelleModePaiement(p.mode)} le ${dateHeure(p.date)} · réf. ${p.reference ?? '-'}',
      'Statut : ${libelleStatut(c.statut)}',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final c = commande;
    final p = c.paiementReussi;
    final facture = p?.numeroFacture;
    final gris = TextStyle(color: Colors.grey.shade700);
    return Scaffold(
      appBar: AppBar(
        title: Text(facture != null ? 'Facture' : 'Reçu'),
        actions: [
          IconButton(
            tooltip: 'Copier',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _texte()));
              if (context.mounted) showMessage(context, 'Reçu copié : collez-le dans un message ou un e-mail');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.agriculture, color: Theme.of(context).colorScheme.primary, size: 32),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('fonction Phyto', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ),
                      StatusChip(c.statut),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    facture != null ? 'Facture n° $facture' : 'Reçu de commande',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  Text('Commande #${c.id} du ${dateHeure(c.date)}', style: gris),
                  const Divider(height: 28),
                  if (c.client != null) Text('Client : ${c.client}'),
                  Text('Livraison : ${c.adresse}, ${c.ville}'),
                  Text('Téléphone : ${c.telephoneLivraison}'),
                  const Divider(height: 28),
                  for (final i in c.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Text('${i.quantite} × ${i.nom}\n${fcfa(i.prixUnitaire)} l’unité')),
                          Text(fcfa(i.totalLigne)),
                        ],
                      ),
                    ),
                  const Divider(height: 28),
                  AmountRow('Sous-total', fcfa(c.sousTotal)),
                  AmountRow('Frais de livraison', c.fraisLivraison == 0 ? 'Offerts' : fcfa(c.fraisLivraison)),
                  AmountRow('Total', fcfa(c.total), bold: true),
                  const Divider(height: 28),
                  if (p != null) ...[
                    Text('Payé par ${libelleModePaiement(p.mode)} le ${dateHeure(p.date)}'),
                    if (p.reference != null) Text('Référence : ${p.reference}', style: gris),
                  ] else
                    Text('Paiement à la livraison', style: gris),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

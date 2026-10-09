import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import 'order_detail_screen.dart';

/// Consulter l'historique des commandes.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late Future<List<Commande>> _commandes;

  @override
  void initState() {
    super.initState();
    _commandes = context.read<Api>().mesCommandes();
  }

  Future<void> _recharger() async {
    setState(() {
      _commandes = context.read<Api>().mesCommandes();
    });
    await _commandes.catchError((_) => <Commande>[]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes commandes')),
      body: RefreshIndicator(
        onRefresh: _recharger,
        child: AsyncView<List<Commande>>(
          future: _commandes,
          onRetry: _recharger,
          builder: (context, commandes) {
            if (commandes.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                    icon: Icons.receipt_long_outlined,
                    titre: 'Aucune commande',
                    message: 'Vos commandes apparaîtront ici.',
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: commandes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final c = commandes[i];
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => OrderDetailScreen(commandeId: c.id)),
                      );
                      if (mounted) _recharger();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Commande #${c.id}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const Spacer(),
                              StatusChip(c.statut),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${dateHeure(c.date)} · ${c.nbArticles} article(s) · ${c.ville}',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(fcfa(c.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                              const Spacer(),
                              if (c.payable)
                                Text(
                                  'À payer',
                                  style: TextStyle(color: couleurStatut(c.statut), fontWeight: FontWeight.w600),
                                ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

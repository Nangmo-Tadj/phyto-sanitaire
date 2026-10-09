import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

const _statutsPaiement = {'en_attente': 'En attente', 'reussi': 'Réussi', 'echoue': 'Échoué'};

Color _couleurPaiement(String statut) => switch (statut) {
  'reussi' => AppColors.vert,
  'echoue' => const Color(0xFFC62828),
  _ => const Color(0xFFB26A00),
};

/// Consultation de tous les paiements Mobile Money.
class AdminPaymentsScreen extends StatefulWidget {
  const AdminPaymentsScreen({super.key});

  @override
  State<AdminPaymentsScreen> createState() => _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends State<AdminPaymentsScreen> {
  // Tous les paiements sont chargés une fois (le serveur renvoie les 200 derniers) puis filtrés localement,
  // ce qui permet d'afficher le total encaissé quel que soit le filtre.
  Future<List<Paiement>>? _future;
  String? _statut;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  void _charger() => _future = context.read<Api>().tousPaiements();

  Future<void> _rafraichir() async {
    setState(_charger);
    try {
      await _future;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paiements')),
      body: RefreshIndicator(
        onRefresh: _rafraichir,
        child: AsyncView<List<Paiement>>(
          future: _future,
          onRetry: () => setState(_charger),
          builder: (context, tous) {
            final reussis = tous.where((p) => p.statut == 'reussi');
            final totalEncaisse = reussis.fold(0, (s, p) => s + p.montant);
            final paiements = _statut == null ? tous : tous.where((p) => p.statut == _statut).toList();

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Card(
                  color: AppColors.vert,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 32),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Total encaissé', style: TextStyle(color: Colors.white70)),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  fcfa(totalEncaisse),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                '${reussis.length} paiement${reussis.length > 1 ? 's' : ''} réussi${reussis.length > 1 ? 's' : ''}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final s in [null, ..._statutsPaiement.keys])
                      ChoiceChip(
                        label: Text(
                          s == null
                              ? 'Tous (${tous.length})'
                              : '${_statutsPaiement[s]} (${tous.where((p) => p.statut == s).length})',
                        ),
                        selected: _statut == s,
                        onSelected: (_) => setState(() => _statut = s),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (paiements.isEmpty)
                  const EmptyState(icon: Icons.payments_outlined, titre: 'Aucun paiement')
                else
                  for (final p in paiements)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PaiementCard(paiement: p),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PaiementCard extends StatelessWidget {
  const _PaiementCard({required this.paiement});
  final Paiement paiement;

  @override
  Widget build(BuildContext context) {
    final p = paiement;
    final couleur = _couleurPaiement(p.statut);
    final orange = p.mode == 'ORANGE_MONEY';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(fcfa(p.montant), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: couleur.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statutsPaiement[p.statut] ?? p.statut,
                    style: TextStyle(color: couleur, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Tag(libelleModePaiement(p.mode), color: orange ? const Color(0xFFE65100) : const Color(0xFFB8860B)),
                const SizedBox(width: 8),
                Text(p.telephone, style: TextStyle(color: Colors.grey.shade700)),
              ],
            ),
            const SizedBox(height: 8),
            _Ligne(Icons.person_outline, p.client ?? '—'),
            _Ligne(Icons.receipt_long_outlined, 'Commande #${p.idCommande}'),
            if (p.reference != null && p.reference!.isNotEmpty) _Ligne(Icons.tag, 'Réf. ${p.reference}'),
            if (p.numeroFacture != null && p.numeroFacture!.isNotEmpty)
              _Ligne(Icons.description_outlined, 'Facture ${p.numeroFacture}'),
            if (p.date != null) _Ligne(Icons.schedule, dateHeure(p.date)),
            if (p.statut == 'echoue' && p.message != null && p.message!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(p.message!, style: TextStyle(color: couleur, fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne(this.icon, this.texte);
  final IconData icon;
  final String texte;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            texte,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

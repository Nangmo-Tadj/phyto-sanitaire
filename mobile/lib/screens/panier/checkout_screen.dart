import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../state/app_state.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import 'payment_screen.dart';

const villesCameroun = [
  'Yaoundé',
  'Douala',
  'Bafoussam',
  'Bamenda',
  'Garoua',
  'Maroua',
  'Ngaoundéré',
  'Bertoua',
  'Ebolowa',
  'Buea',
  'Kribi',
  'Dschang',
];

/// Diagramme de séquence « Passer la commande » : récapitulatif, confirmation de l'adresse, création.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _adresse;
  late final TextEditingController _telephone;
  String _ville = villesCameroun.first;
  Future<Panier>? _recap;

  Api get _api => context.read<Api>();

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthState>().user!;
    _adresse = TextEditingController(text: user.adresse ?? '');
    _telephone = TextEditingController(text: user.telephone);
    final villeProfil = villesCameroun.where((v) => (user.adresse ?? '').toLowerCase().contains(v.toLowerCase()));
    if (villeProfil.isNotEmpty) _ville = villeProfil.first;
    _recap = _api.recapitulatif(_ville);
  }

  @override
  void dispose() {
    _adresse.dispose();
    _telephone.dispose();
    super.dispose();
  }

  void _changerVille(String? v) {
    if (v == null) return;
    setState(() {
      _ville = v;
      _recap = _api.recapitulatif(v);
    });
  }

  Future<void> _placerCommande() async {
    if (!_form.currentState!.validate()) return;
    final ok = await confirmer(
      context,
      'Confirmer l’adresse',
      'Livraison à : ${_adresse.text.trim()}, $_ville\nContact : ${_telephone.text.trim()}',
      action: 'Placer la commande',
    );
    if (!ok || !mounted) return;
    final cart = context.read<CartState>();
    final navigator = Navigator.of(context);
    final commande = await _api.passerCommande(
      adresse: _adresse.text.trim(),
      ville: _ville,
      telephone: _telephone.text.trim(),
    );
    unawaited(cart.charger().catchError((_) {}));
    navigator.pushReplacement(MaterialPageRoute(builder: (_) => PaymentScreen(commande: commande)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Livraison & récapitulatif')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionTitle('Adresse de livraison'),
            DropdownButtonFormField<String>(
              initialValue: _ville,
              decoration: const InputDecoration(labelText: 'Ville', prefixIcon: Icon(Icons.location_city)),
              items: [for (final v in villesCameroun) DropdownMenuItem(value: v, child: Text(v))],
              onChanged: _changerVille,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _adresse,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Quartier, repère', prefixIcon: Icon(Icons.home_outlined)),
              validator: (v) => v == null || v.trim().length < 3 ? 'Précisez l’adresse de livraison' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _telephone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Téléphone du destinataire', prefixIcon: Icon(Icons.phone)),
              validator: (v) => v == null || v.trim().length < 8 ? 'Numéro invalide' : null,
            ),
            const SectionTitle('Récapitulatif'),
            FutureBuilder<Panier>(
              future: _recap,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  final e = snap.error;
                  final details = e is ApiException && e.details is List
                      ? (e.details as List).map((d) => '• ${d['nom']} : ${d['disponible']} disponible(s)').join('\n')
                      : null;
                  return Card(
                    color: Colors.red.shade50,
                    child: ListTile(
                      leading: const Icon(Icons.error_outline, color: Colors.red),
                      title: Text('$e'),
                      subtitle: details == null ? null : Text(details),
                    ),
                  );
                }
                final p = snap.data!;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        for (final i in p.items)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(child: Text('${i.quantite} × ${i.nom}')),
                                Text(fcfa(i.totalLigne)),
                              ],
                            ),
                          ),
                        const Divider(height: 20),
                        AmountRow('Sous-total', fcfa(p.sousTotal)),
                        AmountRow(
                          'Frais de livraison ($_ville)',
                          p.fraisLivraison == 0 ? 'Offerts' : fcfa(p.fraisLivraison),
                        ),
                        const Divider(height: 20),
                        AmountRow('Total à payer', fcfa(p.total), bold: true),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FutureBuilder<Panier>(
            future: _recap,
            builder: (context, snap) => BusyButton(
              label: 'Placer la commande',
              icon: Icons.check_circle_outline,
              onPressed: snap.hasData ? _placerCommande : null,
            ),
          ),
        ),
      ),
    );
  }
}

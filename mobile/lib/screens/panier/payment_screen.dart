import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../state/app_state.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../commandes/order_detail_screen.dart';

enum _Etape { saisie, attente, reussi, echoue, expire }

/// Diagramme de séquence « Paiement de la commande » via MTN MoMo / Orange Money.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.commande, this.depuisDetail = false});

  final Commande commande;

  /// Ouvert depuis le détail de la commande : on y revient au lieu d'en empiler un second.
  final bool depuisDetail;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _form = GlobalKey<FormState>();
  late final _telephone = TextEditingController(text: context.read<AuthState>().user?.telephone ?? '');
  String _mode = 'MTN_MOMO';
  _Etape _etape = _Etape.saisie;
  Paiement? _paiement;
  Timer? _poll;
  int _verifications = 0;

  /// Au-delà (≈ 2 min), on cesse d'attendre pour ne pas bloquer l'utilisateur sur cet écran.
  static const _maxVerifications = 60;

  Api get _api => context.read<Api>();

  @override
  void dispose() {
    _poll?.cancel();
    _telephone.dispose();
    super.dispose();
  }

  Future<void> _payer() async {
    if (!_form.currentState!.validate()) return;
    final p = await _api.payer(widget.commande.id, _mode, _telephone.text.replaceAll(' ', ''));
    if (!mounted) return;
    setState(() {
      _paiement = p;
      _etape = _Etape.attente;
    });
    _verifications = 0;
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _verifier());
  }

  // Le système attend la confirmation de l'opérateur (le client valide sur son téléphone).
  Future<void> _verifier() async {
    if (++_verifications > _maxVerifications) {
      _poll?.cancel();
      if (!mounted) return;
      setState(() {
        _etape = _Etape.expire;
      });
      return;
    }
    try {
      final p = await _api.paiement(_paiement!.id);
      if (!mounted || p.statut == 'en_attente') return;
      _poll?.cancel();
      setState(() {
        _paiement = p;
        _etape = p.statut == 'reussi' ? _Etape.reussi : _Etape.echoue;
      });
    } catch (_) {
      // Erreur réseau passagère : on réessaie au prochain tick.
    }
  }

  void _suivreCommande() => widget.depuisDetail
      ? Navigator.pop(context)
      : Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => OrderDetailScreen(commandeId: widget.commande.id)),
        );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _etape != _Etape.attente,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Paiement · commande #${widget.commande.id}'),
          automaticallyImplyLeading: _etape != _Etape.attente,
        ),
        body: SafeArea(
          child: switch (_etape) {
            _Etape.saisie => _saisie(),
            _Etape.attente => _resultat(
              icon: const SizedBox(width: 64, height: 64, child: CircularProgressIndicator(strokeWidth: 5)),
              titre: 'En attente de confirmation',
              message:
                  'Une demande de ${fcfa(widget.commande.total)} a été envoyée au ${_paiement?.telephone}.\n'
                  'Validez le paiement sur votre téléphone ${_mode == 'MTN_MOMO' ? '(*126#)' : '(#150#)'} avec votre code secret.',
            ),
            _Etape.reussi => _resultat(
              icon: const Icon(Icons.check_circle, color: Colors.green, size: 80),
              titre: 'Paiement réussi',
              message:
                  'Reçu ${_paiement?.numeroFacture ?? ''}\nRéférence : ${_paiement?.reference ?? ''}\n'
                  'Votre commande est en préparation.',
              actions: [FilledButton(onPressed: _suivreCommande, child: const Text('Suivre ma commande'))],
            ),
            _Etape.echoue => _resultat(
              icon: const Icon(Icons.cancel, color: Colors.red, size: 80),
              titre: 'Paiement échoué',
              message: _paiement?.message ?? 'La transaction a été refusée.',
              actions: [
                FilledButton(onPressed: () => setState(() => _etape = _Etape.saisie), child: const Text('Réessayer')),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _suivreCommande, child: const Text('Payer plus tard')),
              ],
            ),
            _Etape.expire => _resultat(
              icon: const Icon(Icons.hourglass_empty, color: Colors.orange, size: 80),
              titre: 'Confirmation non reçue',
              message:
                  'Nous n’avons pas encore reçu la confirmation de l’opérateur.\n'
                  'Si vous avez validé le paiement, la commande sera mise à jour automatiquement.',
              actions: [FilledButton(onPressed: _suivreCommande, child: const Text('Voir ma commande'))],
            ),
          },
        ),
      ),
    );
  }

  Widget _saisie() {
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  AmountRow('Sous-total', fcfa(widget.commande.sousTotal)),
                  AmountRow('Livraison', fcfa(widget.commande.fraisLivraison)),
                  const Divider(),
                  AmountRow('Montant à payer', fcfa(widget.commande.total), bold: true),
                ],
              ),
            ),
          ),
          const SectionTitle('Mode de paiement'),
          RadioGroup<String>(
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v!),
            child: Column(
              children: [
                for (final (code, libelle, couleur) in [
                  ('MTN_MOMO', 'MTN Mobile Money', const Color(0xFFFFCC00)),
                  ('ORANGE_MONEY', 'Orange Money', const Color(0xFFFF7900)),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: _mode == code ? Theme.of(context).colorScheme.primary : Colors.grey.shade200,
                          width: _mode == code ? 2 : 1,
                        ),
                      ),
                      child: RadioListTile<String>(
                        value: code,
                        title: Text(libelle, style: const TextStyle(fontWeight: FontWeight.w600)),
                        secondary: CircleAvatar(
                          backgroundColor: couleur,
                          child: const Icon(Icons.phone_android, color: Colors.black),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _telephone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Numéro ${libelleModePaiement(_mode)}',
              prefixText: '+237 ',
              prefixIcon: const Icon(Icons.phone),
            ),
            validator: (v) => RegExp(r'^\d{9}$').hasMatch((v ?? '').replaceAll(' ', '')) ? null : 'Numéro à 9 chiffres',
          ),
          const SizedBox(height: 24),
          BusyButton(label: 'Payer ${fcfa(widget.commande.total)}', icon: Icons.lock, onPressed: _payer),
        ],
      ),
    );
  }

  Widget _resultat({
    required Widget icon,
    required String titre,
    required String message,
    List<Widget> actions = const [],
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: icon),
            const SizedBox(height: 24),
            Text(
              titre,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(height: 1.5)),
            const SizedBox(height: 28),
            ...actions,
          ],
        ),
      ),
    );
  }
}

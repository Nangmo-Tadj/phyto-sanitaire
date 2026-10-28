import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Double authentification : un code à 6 chiffres (Google Authenticator,
/// Microsoft Authenticator…) est demandé en plus du mot de passe.
class TwoFactorScreen extends StatefulWidget {
  const TwoFactorScreen({super.key});

  @override
  State<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends State<TwoFactorScreen> {
  final _motDePasse = TextEditingController();
  final _code = TextEditingController();

  /// Clé générée, en attente de confirmation par un premier code.
  String? _secret;
  String? _otpauth;

  @override
  void dispose() {
    _motDePasse.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _initier() async {
    if (_motDePasse.text.isEmpty) throw 'Saisissez votre mot de passe';
    final r = await context.read<AuthState>().api.initier2fa(_motDePasse.text);
    setState(() {
      _secret = r.secret;
      _otpauth = r.otpauth;
    });
  }

  Future<void> _activer() async {
    final auth = context.read<AuthState>();
    final u = await auth.api.activer2fa(_code.text.replaceAll(' ', ''));
    auth.majUtilisateur(u);
    if (!mounted) return;
    _motDePasse.clear();
    _code.clear();
    setState(() => _secret = null);
    showMessage(context, 'Double authentification activée');
  }

  Future<void> _desactiver() async {
    if (_motDePasse.text.isEmpty || _code.text.isEmpty) throw 'Saisissez votre mot de passe et un code';
    final auth = context.read<AuthState>();
    final u = await auth.api.desactiver2fa(_motDePasse.text, _code.text.replaceAll(' ', ''));
    auth.majUtilisateur(u);
    if (!mounted) return;
    _motDePasse.clear();
    _code.clear();
    showMessage(context, 'Double authentification désactivée');
  }

  Widget _champMotDePasse() => TextField(
    controller: _motDePasse,
    obscureText: true,
    decoration: const InputDecoration(labelText: 'Mot de passe actuel', prefixIcon: Icon(Icons.lock_outline)),
  );

  Widget _champCode() => TextField(
    controller: _code,
    keyboardType: TextInputType.number,
    maxLength: 6,
    autofillHints: const [AutofillHints.oneTimeCode],
    decoration: const InputDecoration(
      labelText: 'Code à 6 chiffres',
      prefixIcon: Icon(Icons.pin_outlined),
      counterText: '',
    ),
  );

  @override
  Widget build(BuildContext context) {
    final actif = context.watch<AuthState>().user?.totpActif ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Double authentification')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: actif ? AppColors.vertClair : null,
            child: ListTile(
              leading: Icon(actif ? Icons.verified_user : Icons.shield_outlined, color: actif ? AppColors.vert : null),
              title: Text(actif ? 'Activée' : 'Désactivée'),
              subtitle: const Text(
                'À chaque connexion, un code à 6 chiffres généré par votre téléphone est demandé '
                'en plus du mot de passe.',
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (actif) ...[
            const Text('Pour désactiver, confirmez avec votre mot de passe et un code actuel.'),
            const SizedBox(height: 12),
            _champMotDePasse(),
            const SizedBox(height: 12),
            _champCode(),
            const SizedBox(height: 12),
            BusyButton(label: 'Désactiver', onPressed: _desactiver),
          ] else if (_secret == null) ...[
            const Text(
              '1. Installez une application d’authentification (Google Authenticator, Microsoft Authenticator, 2FAS…).\n'
              '2. Confirmez votre mot de passe pour générer votre clé.',
            ),
            const SizedBox(height: 12),
            _champMotDePasse(),
            const SizedBox(height: 12),
            BusyButton(label: 'Générer ma clé', onPressed: _initier),
          ] else ...[
            const Text(
              'Dans l’application d’authentification, choisissez « Saisir une clé de configuration » '
              'puis entrez la clé ci-dessous (type : basé sur l’heure).',
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                title: SelectableText(
                  _secret!.replaceAllMapped(RegExp(r'.{4}'), (m) => '${m[0]} ').trim(),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Compte : fonction Phyto'),
                trailing: IconButton(
                  tooltip: 'Copier la clé',
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _secret!));
                    if (context.mounted) showMessage(context, 'Clé copiée');
                  },
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _otpauth!));
                if (context.mounted) showMessage(context, 'Lien otpauth copié');
              },
              icon: const Icon(Icons.link),
              label: const Text('Copier le lien de configuration'),
            ),
            const SizedBox(height: 8),
            const Text('3. Saisissez le code affiché par l’application pour terminer.'),
            const SizedBox(height: 12),
            _champCode(),
            const SizedBox(height: 12),
            BusyButton(label: 'Activer', onPressed: _activer),
            const SizedBox(height: 8),
            const Text(
              'Conservez cette clé en lieu sûr : elle permet de réinstaller le code sur un nouveau téléphone.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'register_screen.dart';

/// Diagramme de séquence « Authentification utilisateur ».
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.raison});

  /// Explication affichée quand la connexion est demandée pour une action (panier, avis...).
  final String? raison;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _identifiant = TextEditingController();
  final _motDePasse = TextEditingController();
  bool _masquer = true;

  @override
  void dispose() {
    _identifiant.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  Future<void> _connexion() async {
    if (!_form.currentState!.validate()) return;
    await context.read<AuthState>().connexion(_identifiant.text.trim(), _motDePasse.text);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _demo(String profil) async {
    await context.read<AuthState>().connexionDemo(profil);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _creerCompte() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const RegisterScreen()));
    if (ok == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Logo(),
                    const SizedBox(height: 32),
                    Text(
                      'Connexion',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.raison ?? 'Produits phytosanitaires et aliments pour éleveurs',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _identifiant,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                        labelText: 'Téléphone ou email',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Champ obligatoire' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _motDePasse,
                      obscureText: _masquer,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _connexion().catchError((Object e) {
                        if (context.mounted) showMessage(context, e, erreur: true);
                      }),
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_masquer ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _masquer = !_masquer),
                        ),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Champ obligatoire' : null,
                    ),
                    const SizedBox(height: 24),
                    BusyButton(label: 'Se connecter', onPressed: _connexion),
                    const SizedBox(height: 12),
                    TextButton(onPressed: _creerCompte, child: const Text('Pas encore de compte ? Créer un compte')),
                    const SizedBox(height: 16),
                    _DemoAccounts(onSelect: _demo),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Comptes de démonstration : découvrir chaque espace sans s'inscrire.
class _DemoAccounts extends StatefulWidget {
  const _DemoAccounts({required this.onSelect});

  final Future<void> Function(String profil) onSelect;

  @override
  State<_DemoAccounts> createState() => _DemoAccountsState();
}

class _DemoAccountsState extends State<_DemoAccounts> {
  String? _enCours;

  static const _profils = [
    ('client', 'Client', Icons.shopping_basket_outlined),
    ('vendeur', 'Vendeur', Icons.storefront_outlined),
    ('livreur', 'Livreur', Icons.delivery_dining_outlined),
    ('admin', 'Admin', Icons.admin_panel_settings_outlined),
  ];

  Future<void> _choisir(String profil) async {
    setState(() => _enCours = profil);
    try {
      await widget.onSelect(profil);
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    } finally {
      if (mounted) setState(() => _enCours = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.vertClair,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.play_circle_outline, color: AppColors.vert),
                SizedBox(width: 8),
                Text('Compte de démonstration', style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Essayez l’application sans créer de compte.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (profil, libelle, icone) in _profils)
                  ActionChip(
                    avatar: _enCours == profil
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(icone, size: 18, color: AppColors.vert),
                    label: Text(libelle),
                    backgroundColor: Colors.white,
                    onPressed: _enCours == null ? () => _choisir(profil) : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(color: AppColors.vert, borderRadius: BorderRadius.circular(24)),
          child: const Icon(Icons.agriculture, color: Colors.white, size: 48),
        ),
        const SizedBox(height: 12),
        Text(
          'AgroPhyto',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(color: AppColors.vert, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

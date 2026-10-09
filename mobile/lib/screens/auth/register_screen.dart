import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// Créer un compte (client ou vendeur).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _nom = TextEditingController();
  final _prenom = TextEditingController();
  final _telephone = TextEditingController();
  final _email = TextEditingController();
  final _adresse = TextEditingController();
  final _motDePasse = TextEditingController();
  String _type = 'client';
  bool _newsletter = false;

  @override
  void dispose() {
    for (final c in [_nom, _prenom, _telephone, _email, _adresse, _motDePasse]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _obligatoire(String? v) => v == null || v.trim().isEmpty ? 'Champ obligatoire' : null;

  Future<void> _inscrire() async {
    if (!_form.currentState!.validate()) return;
    final auth = context.read<AuthState>();
    final navigator = Navigator.of(context);
    await auth.inscription({
      'nom': _nom.text.trim(),
      'prenom': _prenom.text.trim(),
      'telephone': _telephone.text.trim(),
      'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
      'adresse': _adresse.text.trim().isEmpty ? null : _adresse.text.trim(),
      'mot_de_passe': _motDePasse.text,
      'type_compte': context.read<ParametresState>().creationBoutique ? _type : 'client',
    });
    if (_newsletter && _email.text.trim().isNotEmpty) {
      await auth.api.newsletterCompte(true).catchError((_) {});
    }
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Créer un compte')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (context.watch<ParametresState>().creationBoutique) ...[
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'client', icon: Icon(Icons.shopping_basket_outlined), label: Text('Acheter')),
                  ButtonSegment(value: 'vendeur', icon: Icon(Icons.storefront_outlined), label: Text('Vendre')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 20),
            ],
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _prenom,
                    decoration: const InputDecoration(labelText: 'Prénom *'),
                    validator: _obligatoire,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _nom,
                    decoration: const InputDecoration(labelText: 'Nom *'),
                    validator: _obligatoire,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _telephone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Téléphone *',
                prefixText: '+237 ',
                prefixIcon: Icon(Icons.phone),
              ),
              validator: (v) {
                if (_obligatoire(v) != null) return 'Champ obligatoire';
                return RegExp(r'^\d{9}$').hasMatch(v!.trim()) ? null : 'Numéro à 9 chiffres (ex. 690000000)';
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
              validator: (v) => v == null || v.trim().isEmpty || v.contains('@') ? null : 'Email invalide',
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _adresse,
              decoration: const InputDecoration(
                labelText: 'Adresse (ville, quartier)',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _motDePasse,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mot de passe *', prefixIcon: Icon(Icons.lock_outline)),
              validator: (v) => v == null || v.length < 6 ? '6 caractères minimum' : null,
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _newsletter,
              onChanged: (v) => setState(() => _newsletter = v ?? false),
              title: const Text('Recevoir la newsletter (promotions, conseils agricoles)'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 12),
            BusyButton(label: 'Créer mon compte', onPressed: _inscrire),
          ],
        ),
      ),
    );
  }
}

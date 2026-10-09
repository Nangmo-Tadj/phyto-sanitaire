import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// Éditer et modifier son compte.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _prenom, _nom, _telephone, _email, _adresse;

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthState>().user!;
    _prenom = TextEditingController(text: u.prenom);
    _nom = TextEditingController(text: u.nom);
    _telephone = TextEditingController(text: u.telephone);
    _email = TextEditingController(text: u.email ?? '');
    _adresse = TextEditingController(text: u.adresse ?? '');
  }

  @override
  void dispose() {
    for (final c in [_prenom, _nom, _telephone, _email, _adresse]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _obligatoire(String? v) => v == null || v.trim().isEmpty ? 'Champ obligatoire' : null;

  Future<void> _enregistrer() async {
    if (!_form.currentState!.validate()) return;
    final auth = context.read<AuthState>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final user = await auth.api.modifierCompte({
      'prenom': _prenom.text.trim(),
      'nom': _nom.text.trim(),
      'telephone': _telephone.text.trim(),
      'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
      'adresse': _adresse.text.trim().isEmpty ? null : _adresse.text.trim(),
    });
    auth.majUtilisateur(user);
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('Profil mis à jour'), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Modifier mon profil')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _prenom,
              decoration: const InputDecoration(labelText: 'Prénom'),
              validator: _obligatoire,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nom,
              decoration: const InputDecoration(labelText: 'Nom'),
              validator: _obligatoire,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _telephone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Téléphone'),
              validator: _obligatoire,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) => v == null || v.trim().isEmpty || v.contains('@') ? null : 'Email invalide',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _adresse,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Adresse de livraison par défaut'),
            ),
            const SizedBox(height: 24),
            BusyButton(label: 'Enregistrer', onPressed: _enregistrer),
          ],
        ),
      ),
    );
  }
}

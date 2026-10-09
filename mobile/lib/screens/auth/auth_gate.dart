import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// Navigation en invité : ouvre l'écran de connexion si nécessaire.
/// Renvoie true si une session est ouverte au retour.
Future<bool> exigerConnexion(BuildContext context, {String? raison}) async {
  final auth = context.read<AuthState>();
  if (auth.connecte) return true;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => LoginScreen(raison: raison)));
  return auth.connecte;
}

/// Onglet réservé aux utilisateurs connectés, affiché aux invités.
class ConnexionRequise extends StatelessWidget {
  const ConnexionRequise({super.key, required this.titre, required this.icon, required this.message});

  final String titre;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titre)),
      body: EmptyState(
        icon: icon,
        titre: 'Connectez-vous pour continuer',
        message: message,
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: () => exigerConnexion(context),
              icon: const Icon(Icons.login),
              label: const Text('Se connecter'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
              child: const Text('Créer un compte'),
            ),
          ],
        ),
      ),
    );
  }
}

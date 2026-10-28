import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/home_shell.dart';
import 'services/api.dart';
import 'state/app_state.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = Api();
  runApp(
    MultiProvider(
      providers: [
        Provider<Api>.value(value: api),
        ChangeNotifierProvider(create: (_) => AuthState(api)..restaurer()),
        ChangeNotifierProvider(create: (_) => CartState(api)),
        ChangeNotifierProvider(create: (_) => ParametresState(api)..charger().catchError((_) {})),
      ],
      child: const FonctionPhytoApp(),
    ),
  );
}

final _navigatorKey = GlobalKey<NavigatorState>();

class FonctionPhytoApp extends StatelessWidget {
  const FonctionPhytoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'fonction Phyto',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Root(),
    );
  }
}

/// L'application est accessible en invité ; la connexion est demandée pour les actions qui l'exigent.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  int? _idPrecedent;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final id = auth.user?.id;
    // Déconnexion ou session expirée : on referme les écrans réservés (boutique, admin, chat...).
    // À la connexion, la pile est conservée pour reprendre l'action en cours (ajout au panier...).
    if (_idPrecedent != null && id != _idPrecedent) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _navigatorKey.currentState?.popUntil((r) => r.isFirst));
    }
    _idPrecedent = id;
    if (!auth.initialise) return const _Demarrage();
    // La clé force la reconstruction complète (et le retour à la racine) au changement d'utilisateur.
    return HomeShell(key: ValueKey(auth.user?.id));
  }
}

/// Écran de démarrage pendant la restauration de la session.
class _Demarrage extends StatelessWidget {
  const _Demarrage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: AppColors.vert, borderRadius: BorderRadius.circular(22)),
              child: const Icon(Icons.agriculture, color: Colors.white, size: 56),
            ),
            const SizedBox(height: 12),
            const Text(
              'fonction Phyto',
              style: TextStyle(color: AppColors.vert, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 32),
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
          ],
        ),
      ),
    );
  }
}

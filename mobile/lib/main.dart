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
      child: const AgroPhytoApp(),
    ),
  );
}

final _navigatorKey = GlobalKey<NavigatorState>();

class AgroPhytoApp extends StatelessWidget {
  const AgroPhytoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgroPhyto',
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
    if (!auth.initialise) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // La clé force la reconstruction complète (et le retour à la racine) au changement d'utilisateur.
    return HomeShell(key: ValueKey(auth.user?.id));
  }
}

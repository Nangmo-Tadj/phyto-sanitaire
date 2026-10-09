import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'auth/auth_gate.dart';
import 'catalogue/catalogue_screen.dart';
import 'commandes/orders_screen.dart';
import 'compte/account_screen.dart';
import 'messages/conversations_screen.dart';
import 'panier/cart_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _visites = <int>{0};

  @override
  void initState() {
    super.initState();
    // Après la première frame : charger() notifie les écouteurs, interdit pendant le build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cart = context.read<CartState>();
      context.read<AuthState>().connecte ? cart.charger().catchError((_) {}) : cart.reinitialiser();
    });
  }

  void _aller(int i) => setState(() {
    _index = i;
    _visites.add(i);
  });

  @override
  Widget build(BuildContext context) {
    final articles = context.select<CartState, int>((c) => c.nombreArticles);
    final connecte = context.select<AuthState, bool>((a) => a.connecte);
    final pages = <Widget>[
      CatalogueScreen(onOpenCart: () => _aller(1)),
      if (connecte) ...[
        CartScreen(onBrowse: () => _aller(0)),
        const OrdersScreen(),
        const ConversationsScreen(),
        const AccountScreen(),
      ] else ...const [
        ConnexionRequise(
          titre: 'Mon panier',
          icon: Icons.shopping_cart_outlined,
          message: 'Connectez-vous ou créez un compte pour ajouter des produits au panier et commander.',
        ),
        ConnexionRequise(
          titre: 'Mes commandes',
          icon: Icons.receipt_long_outlined,
          message: 'Connectez-vous pour suivre vos commandes et vos livraisons.',
        ),
        ConnexionRequise(
          titre: 'Messages',
          icon: Icons.chat_bubble_outline,
          message: 'Connectez-vous pour échanger avec les vendeurs et le service client.',
        ),
        ConnexionRequise(
          titre: 'Mon compte',
          icon: Icons.person_outline,
          message: 'Connectez-vous ou créez un compte gratuitement. Le catalogue reste consultable sans compte.',
        ),
      ],
    ];
    return Scaffold(
      // Les onglets ne sont construits qu'à la première visite, puis conservés.
      body: IndexedStack(
        index: _index,
        children: [for (var i = 0; i < pages.length; i++) _visites.contains(i) ? pages[i] : const SizedBox.shrink()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _aller,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Catalogue',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: articles > 0,
              label: Text('$articles'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: articles > 0,
              label: Text('$articles'),
              child: const Icon(Icons.shopping_cart),
            ),
            label: 'Panier',
          ),
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Commandes',
          ),
          const NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Messages',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Compte',
          ),
        ],
      ),
    );
  }
}

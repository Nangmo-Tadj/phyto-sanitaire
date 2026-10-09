// Parcours de bout en bout contre l'API locale (npm run seed && npm start).
//   flutter test integration_test/parcours_test.dart -d <simulateur>
import 'package:agrophyto/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Laisse l'application vivre (requêtes réseau, timers) pendant [d].
  Future<void> attendre(WidgetTester tester, [Duration d = const Duration(milliseconds: 800)]) async {
    final fin = DateTime.now().add(d);
    while (DateTime.now().isBefore(fin)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> attendreQue(WidgetTester tester, Finder finder, {int secondes = 20}) async {
    final fin = DateTime.now().add(Duration(seconds: secondes));
    while (DateTime.now().isBefore(fin)) {
      await tester.pump(const Duration(milliseconds: 200));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('Introuvable après ${secondes}s : $finder');
  }

  /// Point de capture d'écran (le script externe photographie le simulateur).
  Future<void> capture(WidgetTester tester, String nom) async {
    debugPrint('CAPTURE:$nom');
    await attendre(tester, const Duration(seconds: 3));
  }

  Future<void> toucher(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await attendre(tester);
  }

  /// L'application s'ouvre en invité sur le catalogue : connexion depuis la barre du haut.
  Future<void> connexion(WidgetTester tester, String identifiant) async {
    await attendreQue(tester, find.text('Se connecter'));
    await toucher(tester, find.text('Se connecter').first);
    await attendreQue(tester, find.byType(TextFormField));
    await tester.enterText(find.byType(TextFormField).at(0), identifiant);
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await toucher(tester, find.widgetWithText(FilledButton, 'Se connecter'));
    // L'écran de connexion se ferme une fois la session ouverte.
    final fin = DateTime.now().add(const Duration(seconds: 20));
    while (find.text('Mot de passe').evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(fin)) fail('Connexion de $identifiant non aboutie');
      await tester.pump(const Duration(milliseconds: 200));
    }
    await attendre(tester);
  }

  Future<void> deconnexion(WidgetTester tester) async {
    await toucher(tester, find.text('Compte'));
    await toucher(tester, find.text('Se déconnecter').first);
    await toucher(tester, find.widgetWithText(FilledButton, 'Se déconnecter'));
    await attendreQue(tester, find.text('Se connecter'));
  }

  testWidgets('client, livreur puis administrateur', (tester) async {
    (await SharedPreferences.getInstance()).clear();
    app.main();
    await attendre(tester, const Duration(seconds: 2));

    // --- Client : catalogue, panier, commande, paiement -----------------------
    await connexion(tester, '690000004');
    await attendreQue(tester, find.text('Ivermectine 1 %'));
    await capture(tester, '01_catalogue');

    await tester.enterText(find.byType(TextField).first, 'provende');
    await attendre(tester, const Duration(seconds: 2));
    await capture(tester, '02_recherche');
    await toucher(tester, find.textContaining('Provende démarrage').first);
    await attendreQue(tester, find.text('Ajouter au panier'));
    await toucher(tester, find.byIcon(Icons.add).last);
    await capture(tester, '03_fiche_produit');
    await toucher(tester, find.text('Ajouter au panier'));
    await toucher(tester, find.byType(BackButton).last);
    await attendre(tester);

    await toucher(tester, find.text('Panier'));
    await attendreQue(tester, find.text('Procéder au paiement'));
    await capture(tester, '04_panier');
    await toucher(tester, find.text('Procéder au paiement'));
    await attendreQue(tester, find.text('Total à payer'));
    await capture(tester, '05_recapitulatif');
    await toucher(tester, find.widgetWithText(FilledButton, 'Placer la commande'));
    await toucher(tester, find.widgetWithText(FilledButton, 'Placer la commande').last);
    await attendreQue(tester, find.text('Mode de paiement'));
    await capture(tester, '06_paiement');
    await toucher(tester, find.textContaining('Payer '));
    await attendreQue(tester, find.text('En attente de confirmation'));
    await capture(tester, '07_attente_operateur');
    await attendreQue(tester, find.text('Paiement réussi'));
    await capture(tester, '08_paiement_reussi');
    await toucher(tester, find.text('Suivre ma commande'));
    await attendreQue(tester, find.text('Articles'));
    await capture(tester, '09_suivi_commande');
    await toucher(tester, find.byType(BackButton).last);
    await attendre(tester);
    await deconnexion(tester);

    // --- Livreur : prise en charge et confirmation --------------------------
    await connexion(tester, '690000003');
    await toucher(tester, find.text('Compte'));
    await toucher(tester, find.text('Mes livraisons'));
    await attendreQue(tester, find.text('Prendre en charge'));
    await capture(tester, '10_livraisons_disponibles');
    await toucher(tester, find.text('Prendre en charge').first);
    await attendreQue(tester, find.text('Confirmer la livraison'));
    await capture(tester, '11_mes_livraisons');
    await toucher(tester, find.text('Confirmer la livraison').first);
    await toucher(tester, find.widgetWithText(FilledButton, 'Confirmer'));
    await attendreQue(tester, find.textContaining('Livrée le'));
    await capture(tester, '12_livree');
    await toucher(tester, find.byType(BackButton).last);
    await attendre(tester);
    await deconnexion(tester);

    // --- Administrateur : tableau de bord ----------------------------------------
    await connexion(tester, '690000001');
    await toucher(tester, find.text('Compte'));
    await toucher(tester, find.text('Administration'));
    await attendreQue(tester, find.textContaining('Bonjour'));
    await attendre(tester, const Duration(seconds: 2));
    await capture(tester, '13_admin_dashboard');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await attendre(tester);
    await capture(tester, '14_admin_menu');
  });
}

// Mode démo hors ligne : l'application fonctionne sans serveur joignable.
//   flutter test integration_test/demo_mode_test.dart --dart-define=API_URL=http://127.0.0.1:9 -d <simulateur>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fonction_phyto/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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

  Future<void> quitterDemo(WidgetTester tester) async {
    await toucher(tester, find.text('Compte'));
    await toucher(tester, find.text('Quitter le mode démo').first);
    await toucher(tester, find.widgetWithText(FilledButton, 'Quitter'));
    await attendreQue(tester, find.text('Catalogue indisponible'));
  }

  testWidgets('mode démo sans serveur : administrateur puis client', (tester) async {
    (await SharedPreferences.getInstance()).clear();
    app.main();

    // Serveur injoignable : le catalogue propose le mode démo.
    await attendreQue(tester, find.text('Essayer le mode démo'));
    await capture(tester, 'd01_serveur_injoignable');
    await toucher(tester, find.text('Essayer le mode démo'));
    await attendreQue(tester, find.text('Mode démo'));
    await capture(tester, 'd02_connexion');

    // --- Administrateur ---
    await toucher(tester, find.text('Admin'));
    await attendreQue(tester, find.text('Ivermectine 1 %'));
    await capture(tester, 'd03_catalogue_admin');
    await toucher(tester, find.text('Compte'));
    await attendreQue(tester, find.text('Réinitialiser les données'));
    await capture(tester, 'd04_compte_demo');
    await toucher(tester, find.text('Administration'));
    await attendreQue(tester, find.text('Tableau de bord'));
    await attendre(tester, const Duration(seconds: 2));
    await capture(tester, 'd05_tableau_de_bord');
    await toucher(tester, find.text('Commandes').last);
    await attendreQue(tester, find.textContaining('#'));
    await capture(tester, 'd06_admin_commandes');
    await toucher(tester, find.byType(BackButton).last);
    await toucher(tester, find.byType(BackButton).last);
    await quitterDemo(tester);

    // --- Client : suivi et confirmation de réception ---
    await toucher(tester, find.text('Essayer le mode démo'));
    await toucher(tester, find.text('Client'));
    await attendreQue(tester, find.text('Ivermectine 1 %'));
    await toucher(tester, find.text('Commandes'));
    await attendreQue(tester, find.text('Confirmez la réception'));
    await capture(tester, 'd07_mes_commandes');
    await toucher(tester, find.text('Confirmez la réception').first);
    await attendreQue(tester, find.text('Confirmer la réception'));
    await capture(tester, 'd08_suivi');
    await toucher(tester, find.text('Confirmer la réception'));
    await toucher(tester, find.text('Oui, j’ai tout reçu'));
    await attendreQue(tester, find.text('Clôturée'));
    await capture(tester, 'd09_cloturee');
  });
}

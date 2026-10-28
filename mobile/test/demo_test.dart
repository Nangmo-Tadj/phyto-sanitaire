import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fonction_phyto/models/models.dart';
import 'package:fonction_phyto/services/api.dart';
import 'package:fonction_phyto/services/demo/demo_client.dart';
import 'package:fonction_phyto/services/demo/demo_server.dart';

/// Le mode démo doit répondre à tous les appels de l'application, comme le vrai serveur.
void main() {
  late DemoServer serveur;

  Future<(Api, User)> session(String profil) async {
    final api = Api(client: DemoClient(serveur));
    final (token, user) = await api.connexionDemo(profil);
    api.token = token;
    return (api, user);
  }

  setUp(() => serveur = DemoServer());

  test('catalogue en invité', () async {
    final api = Api(client: DemoClient(serveur));
    expect(await api.categories(), hasLength(7));
    final produits = await api.produits();
    expect(produits, hasLength(15));
    expect((await api.produits(q: 'glypho')).single.nom, 'Glyphosate 360 SL');
    expect(await api.produits(type: 'elevage', tri: 'prix_asc'), isNotEmpty);
    final p = await api.produit(1);
    expect(p.noteMoyenne, greaterThan(0));
    expect(await api.avisProduit(1), isNotEmpty);
    expect(await api.fraisLivraison('Yaoundé', 5000), 1500);
    expect((await api.parametres())['comptes_demo'], true);
    await expectLater(api.panier(), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
  });

  test('parcours client complet : panier, commande, paiement, suivi, réception, avis', () async {
    final (client, marie) = await session('client');
    expect(marie.prenom, 'Marie');
    expect(await client.mesCommandes(), isNotEmpty);

    await client.viderPanier();
    await client.ajouterAuPanier(3, 2);
    final panier = await client.modifierQuantite(3, 3);
    expect(panier.nombreArticles, 3);
    expect((await client.recapitulatif('Yaoundé')).fraisLivraison, 1500);
    final commande = await client.passerCommande(adresse: 'Essos', ville: 'Yaoundé', telephone: '690000004');
    expect(commande.statut, StatutCommande.enAttentePaiement);
    expect((await client.panier()).estVide, isTrue);

    final paiement = await client.payer(commande.id, 'MTN_MOMO', '690000004');
    expect(paiement.statut, 'en_attente');
    await Future<void>.delayed(const Duration(milliseconds: 3200));
    expect((await client.paiement(paiement.id)).statut, 'reussi');
    expect((await client.commande(commande.id)).statut, StatutCommande.enCours);

    final (admin, _) = await session('admin');
    await admin.changerStatutCommande(commande.id, StatutCommande.enPreparation);
    final livreurs = await admin.livreurs();
    await admin.affecterLivreur(commande.id, livreurs.firstWhere((l) => l.prenom == 'Jean').id);

    final (livreur, _) = await session('livreur');
    final tournee = await livreur.livraisons();
    expect(tournee.mesLivraisons.map((c) => c.id), contains(commande.id));
    await livreur.prendreLivraison(commande.id);
    await livreur.confirmerLivraison(commande.id);

    final livree = await client.confirmerReception(commande.id);
    expect(livree.statut, StatutCommande.cloturee);
    expect(livree.historique.map((e) => e.statut), containsAllInOrder(StatutCommande.etapes));
    expect(livree.paiementReussi?.numeroFacture, startsWith('FAC-'));
    await client.noterCommande(commande.id, 5, 'Parfait');
    await client.donnerAvisProduit(3, 4, 'Bien');
    final (_, notifications) = await client.notifications();
    expect(notifications.first.titre, contains('Clôturée'));
  });

  test('paiement refusé pour un numéro finissant par 0000, puis annulation', () async {
    final (client, _) = await session('client');
    await client.ajouterAuPanier(1, 1);
    final commande = await client.passerCommande(adresse: 'Essos', ville: 'Yaoundé', telephone: '690000004');
    final paiement = await client.payer(commande.id, 'ORANGE_MONEY', '690000000');
    await Future<void>.delayed(const Duration(milliseconds: 3200));
    expect((await client.paiement(paiement.id)).statut, 'echoue');
    expect((await client.annulerCommande(commande.id)).statut, StatutCommande.annulee);
  });

  test('espace administrateur', () async {
    final (admin, user) = await session('admin');
    expect(user.can(Perm.journalVoir), isTrue);
    final stats = await admin.statistiques();
    expect(stats.commandesJour, greaterThan(0));
    expect(stats.livraisonsEnCours, 1);
    expect(stats.ventesParJour, isNotEmpty);
    expect(stats.topProduits, isNotEmpty);
    expect(stats.stockBas, isNotEmpty);

    expect(await admin.toutesCommandes(), hasLength(14));
    expect(await admin.toutesCommandes(statuts: [StatutCommande.enLivraison]), hasLength(1));
    expect((await admin.toutesCommandes(q: '#9')).single.statut, StatutCommande.echecLivraison);
    expect(await admin.toutesCommandes(q: 'Brice'), isNotEmpty);
    // Échec de livraison : réaffectation, la commande repart en préparation.
    final reprise = await admin.affecterLivreur(9, (await admin.livreurs()).firstWhere((l) => l.prenom == 'Jean').id);
    expect(reprise.statut, StatutCommande.enPreparation);
    await expectLater(
      admin.changerStatutCommande(1, StatutCommande.enCours),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)),
    );

    final utilisateurs = await admin.utilisateurs();
    expect(utilisateurs, hasLength(7));
    expect(await admin.utilisateurs(role: 'livreur'), hasLength(1));
    final brice = utilisateurs.firstWhere((u) => u.prenom == 'Brice');
    await admin.activerUtilisateur(brice.id, false);
    await admin.attribuerRoles(brice.id, ['client', 'livreur']);
    final roles = await admin.roles();
    expect(roles, hasLength(4));
    final role = await admin.creerRole('magasinier', 'Gère le stock');
    await admin.permissionsRole(role.id, [Perm.produitsGerer]);
    expect(await admin.permissions(), hasLength(12));

    final cat = await admin.creerCategorie({'nom': 'Semences', 'type': 'phytosanitaire'});
    await admin.modifierCategorie(cat.id, {'nom': 'Semences certifiées', 'type': 'phytosanitaire'});
    await admin.supprimerCategorie(cat.id);
    expect(await admin.produitsGestion(), hasLength(15));
    await admin.majStatutProduit(2, 'retire');
    expect(await admin.produits(), hasLength(14));

    expect(await admin.tousPaiements(), isNotEmpty);
    final boutiques = await admin.boutiques();
    expect(boutiques, hasLength(2));
    await admin.activerBoutique(boutiques.first.id, false);
    await admin.enregistrerRegle('Dschang', 2000, 90000);
    final regles = await admin.reglesLivraison();
    expect(regles.first.ville, '*');
    await admin.supprimerRegle(regles.firstWhere((r) => r.ville == 'Dschang').id);
    expect((await admin.modifierParametres({'creation_boutique': false}))['creation_boutique'], false);

    final journal = await admin.journal();
    expect(journal.first.action, 'parametres.modifier');
    expect(await admin.journal(action: 'connexion'), isNotEmpty);
  });

  test('vendeur : boutique, produits, ventes', () async {
    final (vendeur, user) = await session('vendeur');
    expect(user.boutique, isNotNull);
    expect((await vendeur.maBoutique())!.nom, 'Agro-Intrants de l’Ouest');
    await vendeur.modifierBoutique({'description': 'Intrants homologués'});
    expect(await vendeur.mesVentes(), isNotEmpty);
    final mes = await vendeur.produitsGestion(tous: false);
    expect(mes, hasLength(8));
    final p = await vendeur.creerProduit({'nom': 'Atrazine', 'id_categorie': 1, 'prix_produit': 5000});
    await vendeur.modifierProduit(p.id, {'prix_produit': 5500});
    expect((await vendeur.majStock(p.id, 12)).stock, 12);
    expect(await vendeur.supprimerProduit(p.id), isFalse);
    // Produit déjà commandé : seulement retiré du catalogue.
    expect(await vendeur.supprimerProduit(1), isTrue);
    await expectLater(vendeur.majStock(9, 1), throwsA(isA<ApiException>()));
  });

  test('messagerie et compte', () async {
    final (client, _) = await session('client');
    final support = await client.support();
    final conversations = await client.conversations();
    expect(conversations.single.nonLus, 1);
    final (_, messages) = await client.filMessages(support['id_user']);
    expect(messages, hasLength(2));
    expect(await client.messagesNonLus(), 0);
    await client.envoyerMessage(support['id_user'], 'Merci !');
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    final (_, suite) = await client.filMessages(support['id_user'], apres: messages.last.id);
    expect(suite, hasLength(2)); // message envoyé + réponse automatique

    final modifie = await client.modifierCompte({'adresse': 'Yaoundé, Ngousso'});
    expect(modifie.adresse, 'Yaoundé, Ngousso');
    await client.newsletterCompte(true);
    await expectLater(client.initier2fa('password123'), throwsA(isA<ApiException>()));
    await expectLater(client.supprimerCompte('password123'), throwsA(isA<ApiException>()));
    final token = await client.changerMotDePasse('password123', 'nouveau123');
    client.token = token;
    expect((await client.moi()).prenom, 'Marie');
    await client.toutesNotificationsLues();
    expect((await client.notifications()).$1, 0);
    await client.deconnexion();
  });

  test('inscription puis connexion par mot de passe', () async {
    final api = Api(client: DemoClient(serveur));
    final (token, user) = await api.inscription({
      'nom': 'Voukeng',
      'prenom': 'Junior',
      'telephone': '677000000',
      'email': 'junior@exemple.cm',
      'adresse': 'Dschang',
      'mot_de_passe': 'secret12',
      'type_compte': 'vendeur',
    });
    expect(user.hasRole('vendeur'), isTrue);
    api.token = token;
    await api.creerBoutique({'nom': 'Boutique de Junior', 'ville': 'Dschang'});
    expect((await api.connexion('junior@exemple.cm', 'secret12'))!.$2.boutique?.nom, 'Boutique de Junior');
    await expectLater(api.connexion('677000000', 'faux'), throwsA(isA<ApiException>()));
    // Compte créé en démo : il peut être supprimé.
    await api.supprimerCompte('secret12');
  });

  test('les données survivent à un aller-retour JSON (sauvegarde sur le téléphone)', () async {
    final (client, _) = await session('client');
    await client.ajouterAuPanier(5, 2);
    final copie = DemoServer(etat: jsonDecode(jsonEncode(serveur.db)) as Map<String, dynamic>);
    final api = Api(client: DemoClient(copie))..token = client.token;
    expect((await api.panier()).nombreArticles, 2);
    expect((await api.ajouterAuPanier(6, 1)).nombreArticles, 3);
    final commande = await api.passerCommande(adresse: 'Essos', ville: 'Yaoundé', telephone: '690000004');
    expect(commande.id, 15);
  });
}

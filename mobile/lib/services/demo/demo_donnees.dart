import 'demo_server.dart';

/// Mot de passe des comptes de démonstration (comme « npm run seed »).
const motDePasseDemo = 'password123';

/// Données de départ du mode démo : celles de backend/src/seed.js, complétées par des
/// commandes à tous les stades pour que chaque espace (client, admin, livreur, vendeur) soit vivant.
J donneesInitiales() {
  final maintenant = DateTime.now();
  String il(Duration d) => horodatage(maintenant.subtract(d));
  Duration j(num jours, [num heures = 0]) => Duration(minutes: ((jours * 24 + heures) * 60).round());

  final db = <String, dynamic>{
    'seq': <String, dynamic>{},
    'parametres': <String, dynamic>{'creation_boutique': true},
    for (final t in [
      'users',
      'roles',
      'permissions',
      'user_roles',
      'role_permissions',
      'boutiques',
      'categories',
      'produits',
      'panier_items',
      'commandes',
      'commande_items',
      'commande_historique',
      'payements',
      'factures',
      'avis',
      'messagerie',
      'notifications',
      'regles_livraison',
      'journal_activite',
    ])
      t: <Map<String, dynamic>>[],
  };
  final seq = db['seq'] as J;
  J ins(String table, String cle, J ligne) {
    final n = ((seq[table] as int?) ?? 0) + 1;
    seq[table] = n;
    final l = {cle: n, ...ligne};
    (db[table] as List).add(l);
    return l;
  }

  // --- Rôles et permissions (backend/src/constants.js) ---
  const permissions = {
    'produits.gerer': 'Ajouter, modifier, supprimer ses produits et gérer le stock',
    'produits.moderer': 'Gérer les produits de toutes les boutiques',
    'categories.gerer': 'Créer et organiser les catégories',
    'utilisateurs.gerer': 'Lister, activer ou désactiver les comptes',
    'roles.gerer': 'Attribuer les rôles et permissions',
    'commandes.gerer': 'Consulter toutes les commandes et changer leur statut',
    'paiements.voir': 'Consulter les paiements',
    'livraisons.effectuer': 'Prendre en charge et confirmer les livraisons',
    'livraison.regles': 'Configurer les règles de livraison',
    'boutique.gerer': 'Créer et gérer sa boutique',
    'statistiques.voir': 'Consulter les lots et statistiques des ventes',
    'journal.voir': 'Consulter le journal d’activité',
  };
  permissions.forEach(
    (nom, description) => ins('permissions', 'id_permission', {'nom': nom, 'description': description}),
  );
  final roles = {
    'client': ('Achète des produits', <String>[]),
    'vendeur': ('Gère sa boutique et ses stocks', ['boutique.gerer', 'produits.gerer']),
    'livreur': ('Livre les commandes', ['livraisons.effectuer']),
    'admin': ('Gestionnaire principal de la plateforme', permissions.keys.toList()),
  };
  roles.forEach((nom, r) {
    ins('roles', 'id_role', {'nom': nom, 'description': r.$1});
    for (final p in r.$2) {
      (db['role_permissions'] as List).add({'role': nom, 'permission': p});
    }
  });

  // --- Utilisateurs ---
  int user(String nom, String prenom, String email, String tel, String adresse, List<String> rolesUser, num ancien) {
    final u = ins('users', 'id_user', {
      'nom': nom,
      'prenom': prenom,
      'email': email,
      'telephone': tel,
      'adresse': adresse,
      'profil': null,
      'mdp': motDePasseDemo,
      'actif': true,
      'newsletter': false,
      'token_version': 0,
      'derniere_connexion': il(j(0, 5)),
      'date_creation': il(j(ancien)),
      'fictif': true,
    });
    for (final r in rolesUser) {
      (db['user_roles'] as List).add({'id_user': u['id_user'], 'role': r});
    }
    return u['id_user'];
  }

  final admin = user('Voukeng', 'Charles', 'admin@fonctionphyto.cm', '690000001', 'Yaoundé, Bastos', [
    'client',
    'vendeur',
    'admin',
  ], 90);
  final paul = user('Nkeng', 'Paul', 'vendeur@fonctionphyto.cm', '690000002', 'Bafoussam, Marché A', [
    'client',
    'vendeur',
  ], 80);
  final alice = user('Mbarga', 'Alice', 'alice@fonctionphyto.cm', '690000005', 'Douala, Ndokoti', [
    'client',
    'vendeur',
  ], 75);
  final jean = user('Fotso', 'Jean', 'livreur@fonctionphyto.cm', '690000003', 'Yaoundé, Mvog-Mbi', [
    'client',
    'livreur',
  ], 70);
  final marie = user('Ngo', 'Marie', 'client@fonctionphyto.cm', '690000004', 'Yaoundé, Essos', ['client'], 60);
  final brice = user('Kamga', 'Brice', 'brice@exemple.cm', '690000006', 'Dschang, Foto', ['client'], 30);
  final estelle = user('Tchoua', 'Estelle', 'estelle@exemple.cm', '690000007', 'Douala, Akwa', ['client'], 20);

  // --- Boutiques, catégories, produits (backend/src/seed.js) ---
  int boutique(int vendeur, String nom, String desc, String ville, String tel) => ins('boutiques', 'id_boutique', {
    'id_vendeur': vendeur,
    'nom': nom,
    'description': desc,
    'adresse': 'Marché central',
    'ville': ville,
    'telephone': tel,
    'active': true,
    'date_creation': il(j(75)),
  })['id_boutique'];
  final b1 = boutique(
    paul,
    'Agro-Intrants de l’Ouest',
    'Produits phytosanitaires homologués',
    'Bafoussam',
    '690000002',
  );
  final b2 = boutique(alice, 'Élevage Plus Douala', 'Provende et produits vétérinaires', 'Douala', '690000005');

  int cat(String nom, String description, String type) =>
      ins('categories', 'id_categorie', {'nom': nom, 'description': description, 'type': type})['id_categorie'];
  final herbicides = cat('Herbicides', 'Désherbants sélectifs et totaux', 'phytosanitaire');
  final insecticides = cat('Insecticides', 'Protection contre les ravageurs', 'phytosanitaire');
  final fongicides = cat('Fongicides', 'Traitement des maladies fongiques', 'phytosanitaire');
  final engrais = cat('Engrais', 'Fertilisants minéraux et organiques', 'phytosanitaire');
  final volaille = cat('Aliments volaille', 'Provendes poulets de chair et pondeuses', 'elevage');
  final porcs = cat('Aliments porcs', 'Provendes croissance et finition', 'elevage');
  final veto = cat('Produits vétérinaires', 'Vitamines, vaccins et antiparasitaires', 'elevage');

  final produits = [
    (
      herbicides,
      b1,
      'Glyphosate 360 SL',
      'Herbicide systémique total non sélectif. Dose : 3 à 6 L/ha.',
      4500,
      40,
      'bidon 1 L',
    ),
    (herbicides, b1, 'Nicosulfuron 40 SC', 'Herbicide sélectif du maïs, post-levée.', 6000, 25, 'flacon 1 L'),
    (
      insecticides,
      b1,
      'Cypercal 50 EC',
      'Insecticide à base de cyperméthrine pour cultures maraîchères.',
      3800,
      60,
      'flacon 1 L',
    ),
    (insecticides, b1, 'Emamectine 19 EC', 'Contre la chenille légionnaire d’automne.', 5200, 4, 'flacon 250 mL'),
    (
      fongicides,
      b1,
      'Mancozèbe 80 WP',
      'Fongicide de contact contre le mildiou (tomate, pomme de terre, cacao).',
      3500,
      80,
      'sachet 1 kg',
    ),
    (
      fongicides,
      b1,
      'Ridomil Gold Plus',
      'Fongicide systémique pour cacaoyer contre la pourriture brune.',
      2500,
      120,
      'sachet 50 g',
    ),
    (engrais, b1, 'NPK 20-10-10', 'Engrais complet pour maïs et cultures vivrières.', 22000, 30, 'sac 50 kg'),
    (engrais, b1, 'Urée 46 %', 'Engrais azoté pour la croissance végétative.', 20000, 3, 'sac 50 kg'),
    (
      volaille,
      b2,
      'Provende démarrage poulet de chair',
      'Aliment complet 0 à 21 jours, 22 % de protéines.',
      17500,
      50,
      'sac 50 kg',
    ),
    (volaille, b2, 'Provende finition poulet de chair', 'Aliment complet 22 à 45 jours.', 16500, 45, 'sac 50 kg'),
    (volaille, b2, 'Aliment pondeuses', 'Riche en calcium pour une meilleure ponte.', 15000, 35, 'sac 50 kg'),
    (porcs, b2, 'Aliment porc croissance', 'Aliment complet pour porcs de 25 à 60 kg.', 14000, 20, 'sac 50 kg'),
    (veto, b2, 'Anti-stress vitaminé', 'Vitamines A, D3, E et électrolytes pour volailles.', 2000, 100, 'sachet 100 g'),
    (veto, b2, 'Vaccin Newcastle HB1', 'Vaccin contre la maladie de Newcastle, 1000 doses.', 4500, 15, 'flacon'),
    (veto, null, 'Ivermectine 1 %', 'Antiparasitaire injectable bovins, ovins, porcins.', 7500, 18, 'flacon 50 mL'),
  ];
  for (final (i, (c, b, nom, desc, prix, stock, unite)) in produits.indexed) {
    ins('produits', 'id_produit', {
      'id_categorie': c,
      'id_boutique': b,
      'nom': nom,
      'description': desc,
      'prix_produit': prix,
      'quantite_stock': stock,
      'unite': unite,
      'image_produit': null,
      'statut': 'publie',
      // Ordre « nouveautés » du catalogue identique au serveur.
      'date_creation': il(j(60 - i)),
      'date_modification': il(j(60 - i)),
    });
  }
  J produit(int id) => (db['produits'] as List).cast<J>().firstWhere((p) => p['id_produit'] == id);

  // --- Règles de livraison ---
  for (final (ville, frais, seuil) in [
    ('*', 3000, 150000),
    ('Yaoundé', 1500, 100000),
    ('Douala', 1500, 100000),
    ('Bafoussam', 1000, 80000),
  ]) {
    ins('regles_livraison', 'id_regle', {'ville': ville, 'frais': frais, 'seuil_gratuite': seuil});
  }
  int frais(String ville, int sousTotal) {
    final r = (db['regles_livraison'] as List).cast<J>().firstWhere(
      (r) => r['ville'] == ville,
      orElse: () => (db['regles_livraison'] as List).cast<J>().first,
    );
    return sousTotal >= (r['seuil_gratuite'] as int) ? 0 : r['frais'];
  }

  // --- Commandes à tous les stades du suivi ---
  const libelles = {
    'en_attente_paiement': 'Reçue',
    'en_cours': 'Confirmée',
    'en_preparation': 'En préparation',
    'en_livraison': 'En cours de livraison',
    'livree': 'Livrée',
    'cloturee': 'Clôturée',
    'echec_livraison': 'Échec de livraison',
    'annulee': 'Annulée',
  };
  void notifier(int idUser, String type, String titre, String message, Duration quand, {bool lu = true}) => ins(
    'notifications',
    'id_notification',
    {'id_user': idUser, 'type': type, 'titre': titre, 'message': message, 'lu': lu, 'date': il(quand)},
  );

  /// [etapes] : (statut, il y a, auteur, commentaire), du plus ancien au plus récent.
  void commande(
    int client,
    String ville,
    String adresse,
    List<(int, int)> lignes,
    List<(String, Duration, int?, String?)> etapes, {
    int? livreur,
    String? motif,
    String mode = 'MTN_MOMO',
    int? note,
    bool nonLue = false,
  }) {
    final sousTotal = lignes.fold<int>(0, (s, l) => s + (produit(l.$1)['prix_produit'] as int) * l.$2);
    final f = frais(ville, sousTotal);
    final dernier = etapes.last;
    final c = ins('commandes', 'id_commande', {
      'id_user': client,
      'date_commande': il(etapes.first.$2),
      'statut_commande': dernier.$1,
      'sous_total': sousTotal,
      'frais_livraison': f,
      'total_commande': sousTotal + f,
      'adresse_livraison': adresse,
      'ville': ville,
      'telephone_livraison': (db['users'] as List).cast<J>().firstWhere((u) => u['id_user'] == client)['telephone'],
      'id_livreur': livreur,
      'motif_echec': motif,
      'date_livraison': [
        for (final e in etapes)
          if (e.$1 == 'livree') il(e.$2),
      ].firstOrNull,
    });
    final id = c['id_commande'] as int;
    for (final (idp, qte) in lignes) {
      (db['commande_items'] as List).add({
        'id_commande': id,
        'id_produit': idp,
        'nom_produit': produit(idp)['nom'],
        'prix_unitaire': produit(idp)['prix_produit'],
        'quantite': qte,
      });
    }
    for (final (i, (statut, quand, auteur, commentaire)) in etapes.indexed) {
      ins('commande_historique', 'id_historique', {
        'id_commande': id,
        'statut': statut,
        'commentaire': commentaire,
        'id_auteur': auteur,
        'date': il(quand),
      });
      notifier(
        client,
        'commande',
        'Commande #$id : ${libelles[statut]}',
        switch (statut) {
          'en_attente_paiement' => 'Votre commande #$id est bien reçue. Procédez au paiement pour la confirmer.',
          'en_cours' => 'Paiement de ${sousTotal + f} FCFA reçu : votre commande #$id est confirmée.',
          'en_preparation' => 'Votre commande #$id est en préparation.',
          'en_livraison' => 'Votre commande #$id est en route vers vous.',
          'livree' => 'Votre commande #$id a été livrée. Confirmez la réception dans l’application.',
          'cloturee' => 'Commande #$id clôturée. Merci pour votre confiance !',
          'echec_livraison' => 'Livraison de la commande #$id non effectuée : $motif. Nous vous recontactons.',
          _ => 'Votre commande #$id a été annulée.',
        },
        quand,
        lu: !(nonLue && i == etapes.length - 1),
      );
    }
    // Paiement réussi et facture dès que la commande a été confirmée.
    final confirmation = etapes.where((e) => e.$1 == 'en_cours').firstOrNull;
    if (confirmation != null) {
      final p = ins('payements', 'id_payement', {
        'id_commande': id,
        'montant': sousTotal + f,
        'date_paie': il(confirmation.$2 + const Duration(minutes: 1)),
        'statut_paie': 'reussi',
        'mode_paie': mode,
        'telephone': c['telephone_livraison'],
        'reference_transaction': 'TX-DEMO-${id.toString().padLeft(4, '0')}',
        'message': 'Paiement confirmé par l’opérateur',
      });
      ins('factures', 'id_facture', {
        'id_payement': p['id_payement'],
        'numero_facture': 'FAC-${maintenant.year}-${'${p['id_payement']}'.padLeft(6, '0')}',
        'date_facture': il(confirmation.$2),
        'statut_facture': 'payee',
      });
    }
    if (note != null) {
      ins('avis', 'id_avis', {
        'id_user': client,
        'id_produit': null,
        'id_commande': id,
        'note_avis': note,
        'commentaire': 'Livraison rapide, produits conformes.',
        'date_avis': il(etapes.last.$2),
      });
    }
  }

  const paiement = 'Paiement MTN_MOMO réussi';
  const om = 'Paiement ORANGE_MONEY réussi';
  String prise(String prenom) => 'Prise en charge par $prenom Fotso';

  // Historique : commandes clôturées réparties sur le mois (graphique des ventes).
  for (final (k, client, ville, adresse, lignes) in [
    (26, marie, 'Yaoundé', 'Essos, face pharmacie', [(1, 2), (5, 1)]),
    (21, brice, 'Dschang', 'Foto, carrefour', [(9, 2), (13, 3)]),
    (17, estelle, 'Douala', 'Akwa, rue Joss', [(11, 4)]),
    (12, marie, 'Yaoundé', 'Essos, face pharmacie', [(7, 1), (3, 2)]),
    (8, brice, 'Dschang', 'Foto, carrefour', [(10, 3), (14, 1)]),
  ]) {
    commande(
      client,
      ville,
      adresse,
      lignes,
      [
        ('en_attente_paiement', j(k), client, 'Commande enregistrée'),
        ('en_cours', j(k, -0.2), null, k.isEven ? paiement : om),
        ('en_preparation', j(k, -3), admin, 'Mis à jour par l’administrateur'),
        ('en_livraison', j(k - 1), jean, prise('Jean')),
        ('livree', j(k - 1, -4), jean, 'Livraison effectuée'),
        ('cloturee', j(k - 1, -6), client, 'Réception confirmée par le client'),
      ],
      livreur: jean,
      mode: k.isEven ? 'MTN_MOMO' : 'ORANGE_MONEY',
      note: k % 3 == 0 ? 5 : null,
    );
  }
  // Annulée par le client.
  commande(
    marie,
    'Yaoundé',
    'Essos, face pharmacie',
    [(4, 1)],
    [
      ('en_attente_paiement', j(15), marie, 'Commande enregistrée'),
      ('annulee', j(15, -1), marie, 'Annulée par le client'),
    ],
  );
  // Livrée : Brice doit confirmer la réception.
  commande(
    brice,
    'Dschang',
    'Foto, carrefour',
    [(9, 2)],
    [
      ('en_attente_paiement', j(3), brice, 'Commande enregistrée'),
      ('en_cours', j(3, -0.2), null, paiement),
      ('en_preparation', j(3, -2), admin, 'Mis à jour par l’administrateur'),
      ('en_livraison', j(2), jean, prise('Jean')),
      ('livree', j(2, -3), jean, 'Livraison effectuée'),
    ],
    livreur: jean,
  );
  // Livrée : Marie peut confirmer la réception et noter.
  commande(
    marie,
    'Yaoundé',
    'Essos, face pharmacie',
    [(6, 4), (13, 2)],
    [
      ('en_attente_paiement', j(2), marie, 'Commande enregistrée'),
      ('en_cours', j(2, -0.2), null, om),
      ('en_preparation', j(2, -2), admin, 'Mis à jour par l’administrateur'),
      ('en_livraison', j(1, 2), jean, prise('Jean')),
      ('livree', j(1), jean, 'Livraison effectuée'),
    ],
    livreur: jean,
    mode: 'ORANGE_MONEY',
    nonLue: true,
  );
  // Échec de livraison : à réaffecter par l'administrateur.
  const absent = 'Client absent au point de livraison';
  commande(
    brice,
    'Dschang',
    'Foto, carrefour',
    [(12, 2)],
    [
      ('en_attente_paiement', j(1, 6), brice, 'Commande enregistrée'),
      ('en_cours', j(1, 5.8), null, paiement),
      ('en_livraison', j(1, 2), jean, prise('Jean')),
      ('echec_livraison', j(0, 20), jean, absent),
    ],
    livreur: jean,
    motif: absent,
  );
  // En cours de livraison (aujourd'hui) : suivie par Marie, à confirmer par le livreur.
  commande(
    marie,
    'Yaoundé',
    'Essos, face pharmacie',
    [(7, 1), (2, 1)],
    [
      ('en_attente_paiement', j(0, 6), marie, 'Commande enregistrée'),
      ('en_cours', j(0, 5.8), null, paiement),
      ('en_preparation', j(0, 4), admin, 'Mis à jour par l’administrateur'),
      ('en_livraison', j(0, 1), jean, prise('Jean')),
    ],
    livreur: jean,
    nonLue: true,
  );
  // En préparation, livreur affecté par l'administrateur : Jean doit la démarrer.
  commande(
    estelle,
    'Douala',
    'Akwa, rue Joss',
    [(11, 3), (14, 1)],
    [
      ('en_attente_paiement', j(0, 5), estelle, 'Commande enregistrée'),
      ('en_cours', j(0, 4.8), null, om),
      ('en_preparation', j(0, 3), admin, 'Livreur affecté : Jean Fotso'),
    ],
    livreur: jean,
    mode: 'ORANGE_MONEY',
  );
  // Confirmée (payée), à préparer : libre pour un livreur.
  commande(
    brice,
    'Bafoussam',
    'Marché A, entrée nord',
    [(3, 2), (5, 2)],
    [('en_attente_paiement', j(0, 3), brice, 'Commande enregistrée'), ('en_cours', j(0, 2.8), null, paiement)],
  );
  // Reçue, en attente de paiement.
  commande(
    estelle,
    'Douala',
    'Akwa, rue Joss',
    [(8, 1)],
    [('en_attente_paiement', j(0, 1), estelle, 'Commande enregistrée')],
  );
  // Reçue (Marie) : elle peut la payer ou l'annuler.
  commande(
    marie,
    'Yaoundé',
    'Essos, face pharmacie',
    [(13, 5)],
    [('en_attente_paiement', j(0, 0.5), marie, 'Commande enregistrée')],
  );

  // Avis sur des produits achetés.
  for (final (client, idp, note, commentaire, k) in [
    (marie, 1, 5, 'Très efficace sur les mauvaises herbes, je recommande.', 20),
    (brice, 9, 4, 'Bons résultats sur mes poussins.', 18),
    (estelle, 11, 5, 'Mes pondeuses produisent mieux depuis.', 14),
    (marie, 5, 4, 'Efficace contre le mildiou.', 10),
  ]) {
    ins('avis', 'id_avis', {
      'id_user': client,
      'id_produit': idp,
      'id_commande': null,
      'note_avis': note,
      'commentaire': commentaire,
      'date_avis': il(j(k)),
    });
  }

  // Notifications des autres profils.
  notifier(admin, 'commande', 'Nouvelle commande payée', 'Commande #12 à préparer.', j(0, 2.8), lu: false);
  notifier(admin, 'livraison', 'Échec de livraison', 'Commande #9 : $absent', j(0, 20), lu: false);
  notifier(
    jean,
    'livraison',
    'Livraison assignée',
    'La commande #11 (Douala) vous a été assignée.',
    j(0, 3),
    lu: false,
  );
  notifier(
    jean,
    'livraison',
    'Nouvelle livraison disponible',
    'Commande #12 à livrer à Bafoussam.',
    j(0, 2.8),
    lu: false,
  );
  notifier(paul, 'commande', 'Nouvelle vente', 'Vos produits ont été commandés (#12).', j(0, 2.8), lu: false);
  notifier(alice, 'commande', 'Nouvelle vente', 'Vos produits ont été commandés (#11).', j(0, 4.8), lu: false);

  // Messagerie.
  for (final (de, vers, contenu, quand, lu) in [
    (marie, admin, 'Bonjour, le Ridomil convient-il aussi pour le cacao ?', j(1, 3), true),
    (
      admin,
      marie,
      'Bonjour Marie, oui : 50 g pour 15 L d’eau, toutes les 3 semaines en saison des pluies.',
      j(1, 2),
      false,
    ),
    (brice, paul, 'Avez-vous du NPK en sac de 25 kg ?', j(0, 6), false),
    (estelle, alice, 'Livrez-vous à Akwa le samedi ?', j(0, 4), false),
  ]) {
    ins('messagerie', 'id_messagerie', {
      'id_expediteur': de,
      'id_destinataire': vers,
      'sujet': null,
      'contenu': contenu,
      'date_envoie': il(quand),
      'date_lecture': lu ? il(quand - const Duration(minutes: 5)) : null,
    });
  }

  // Journal d'activité.
  for (final (u, action, details, quand) in [
    (admin, 'connexion', null, j(0, 5)),
    (admin, 'commande.statut', '{"id_commande":10,"de":"en_cours","vers":"en_preparation"}', j(0, 4)),
    (admin, 'commande.livreur', '{"id_commande":11,"id_livreur":$jean}', j(0, 3)),
    (jean, 'connexion', null, j(0, 2)),
    (paul, 'connexion.echec', 'Mot de passe incorrect', j(0, 1.5)),
    (paul, 'connexion', null, j(0, 1.4)),
    (marie, 'connexion', null, j(0, 1)),
  ]) {
    ins('journal_activite', 'id_journal', {
      'id_user': u,
      'action': action,
      'details': details,
      'ip': 'mode démo',
      'date': il(quand),
    });
  }
  return db;
}

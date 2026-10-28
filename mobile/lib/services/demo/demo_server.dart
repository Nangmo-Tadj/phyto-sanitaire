import 'dart:async';
import 'dart:convert';

import 'demo_donnees.dart';

typedef J = Map<String, dynamic>;

/// Erreur renvoyée par le serveur de démonstration (même format que l'API : { erreur, details }).
class DemoErreur implements Exception {
  DemoErreur(this.status, this.message, [this.details]);
  final int status;
  final String message;
  final dynamic details;
}

DemoErreur _bad(String m, [dynamic d]) => DemoErreur(400, m, d);
DemoErreur _unauth([String m = 'Authentification requise']) => DemoErreur(401, m);
DemoErreur _forbidden([String m = 'Accès refusé']) => DemoErreur(403, m);
DemoErreur _notFound([String m = 'Ressource introuvable']) => DemoErreur(404, m);
DemoErreur _conflict(String m, [dynamic d]) => DemoErreur(409, m, d);

/// Réponse : code HTTP et corps JSON.
typedef DemoReponse = (int, Object?);

/// Constantes du backend (backend/src/constants.js).
class _S {
  static const attente = 'en_attente_paiement';
  static const enCours = 'en_cours';
  static const preparation = 'en_preparation';
  static const livraison = 'en_livraison';
  static const livree = 'livree';
  static const cloturee = 'cloturee';
  static const echec = 'echec_livraison';
  static const annulee = 'annulee';
  static const payes = [enCours, preparation, livraison, livree, cloturee, echec];
  static const aLivrer = [enCours, preparation];
  static const libelles = {
    attente: 'Reçue',
    enCours: 'Confirmée',
    preparation: 'En préparation',
    livraison: 'En cours de livraison',
    livree: 'Livrée',
    cloturee: 'Clôturée',
    echec: 'Échec de livraison',
    annulee: 'Annulée',
  };
  static const transitions = {
    attente: [enCours, annulee],
    enCours: [preparation, livraison, annulee],
    preparation: [livraison, enCours, annulee],
    livraison: [livree, echec, preparation],
    echec: [preparation, livraison, annulee],
    livree: [cloturee],
    cloturee: <String>[],
    annulee: <String>[],
  };
}

class _P {
  static const produitsGerer = 'produits.gerer';
  static const produitsModerer = 'produits.moderer';
  static const categoriesGerer = 'categories.gerer';
  static const utilisateursGerer = 'utilisateurs.gerer';
  static const rolesGerer = 'roles.gerer';
  static const commandesGerer = 'commandes.gerer';
  static const paiementsVoir = 'paiements.voir';
  static const livraisonsEffectuer = 'livraisons.effectuer';
  static const livraisonRegles = 'livraison.regles';
  static const boutiqueGerer = 'boutique.gerer';
  static const statistiquesVoir = 'statistiques.voir';
  static const journalVoir = 'journal.voir';
}

/// Comptes de démonstration par profil (téléphone), comme backend/src/constants.js.
const profilsDemo = {'client': '690000004', 'vendeur': '690000002', 'livreur': '690000003', 'admin': '690000001'};

String _deux(int n) => n.toString().padLeft(2, '0');

/// Date au format SQLite (UTC « AAAA-MM-JJ HH:MM:SS »), comme le serveur.
String horodatage([DateTime? d]) {
  final u = (d ?? DateTime.now()).toUtc();
  return '${u.year}-${_deux(u.month)}-${_deux(u.day)} ${_deux(u.hour)}:${_deux(u.minute)}:${_deux(u.second)}';
}

DateTime _local(String ts) => DateTime.parse('${ts.replaceFirst(' ', 'T')}Z').toLocal();
String _jourLocal(DateTime d) => '${d.year}-${_deux(d.month)}-${_deux(d.day)}';

/// Serveur simulé : reproduit l'API REST (backend/src) sur des données en mémoire,
/// pour essayer l'application sans connexion. Les tables suivent le schéma SQLite.
class DemoServer {
  DemoServer({J? etat, this.onChange}) : db = etat ?? donneesInitiales() {
    // Paiements restés en attente (application fermée) : on les conclut.
    for (final p in _t('payements').where((p) => p['statut_paie'] == 'en_attente').toList()) {
      _resultatPaiement(p['reference_transaction'], !'${p['telephone']}'.endsWith('0000'));
    }
  }

  /// Tables (listes de lignes) et compteurs d'identifiants.
  final J db;

  /// Appelé après chaque modification (sauvegarde des données de démonstration).
  final void Function()? onChange;

  List<J> _t(String table) => (db[table] as List).cast<J>();

  int _id(String table) {
    final seq = db['seq'] as J;
    final n = ((seq[table] as int?) ?? 0) + 1;
    seq[table] = n;
    return n;
  }

  J _insert(String table, String cle, J ligne) {
    final l = {cle: _id(table), ...ligne};
    _t(table).add(l);
    return l;
  }

  J? _un(String table, bool Function(J) f) => _t(table).where(f).firstOrNull;

  // --- Utilitaires de validation (backend/src/errors.js) -----------------------------
  void _requis(J body, List<String> champs) {
    final manquants = champs.where((c) => body[c] == null || '${body[c]}'.trim().isEmpty).toList();
    if (manquants.isNotEmpty) throw _bad('Champs obligatoires manquants : ${manquants.join(', ')}');
  }

  int _int(dynamic v, String nom, {int? min}) {
    final n = v is int ? v : (v is double && v == v.roundToDouble() ? v.toInt() : int.tryParse('${v ?? ''}'.trim()));
    if (n == null || (min != null && n < min)) {
      throw _bad('$nom doit être un entier${min != null ? ' ≥ $min' : ''}');
    }
    return n;
  }

  bool _like(dynamic valeur, String q) => '${valeur ?? ''}'.toLowerCase().contains(q.toLowerCase());

  // --- Utilisateurs, rôles et permissions -------------------------------------------------
  J? _user(dynamic id) => _un('users', (u) => u['id_user'] == id);

  List<String> _roles(int idUser) {
    final noms = _t('user_roles').where((r) => r['id_user'] == idUser).map((r) => r['role'] as String).toSet();
    return [
      for (final r in _t('roles'))
        if (noms.contains(r['nom'])) r['nom'] as String,
    ];
  }

  List<String> _permissionsRole(String role) =>
      _t('role_permissions').where((rp) => rp['role'] == role).map((rp) => rp['permission'] as String).toList()..sort();

  List<String> _permissions(int idUser) => {for (final r in _roles(idUser)) ..._permissionsRole(r)}.toList();

  J _publicUser(J u) {
    final b = _un('boutiques', (b) => b['id_vendeur'] == u['id_user']);
    return {
      ...Map.of(u)
        ..remove('mdp')
        ..remove('token_version'),
      'totp_actif': false,
      'roles': _roles(u['id_user']),
      'permissions': _permissions(u['id_user']),
      'boutique': b == null ? null : {'id_boutique': b['id_boutique'], 'nom': b['nom']},
    };
  }

  String _token(J u) => 'demo.${u['id_user']}.${u['token_version']}';

  /// Utilisateur courant (middleware authenticate).
  J? _authentifier(String? token, {bool optionnel = false}) {
    if (token == null) {
      if (optionnel) return null;
      throw _unauth();
    }
    final parties = token.split('.');
    final u = parties.length == 3 && parties[0] == 'demo' ? _user(int.tryParse(parties[1])) : null;
    if (u == null || '${u['token_version']}' != parties[2]) throw _unauth('Session expirée ou invalide');
    if (u['actif'] != true) throw _forbidden('Compte désactivé');
    return u;
  }

  bool _peut(J? u, String permission) => u != null && _permissions(u['id_user']).contains(permission);

  void _exiger(J u, List<String> permissions) {
    if (!permissions.any((p) => _peut(u, p))) throw _forbidden();
  }

  bool _estCompteDemo(J u) => profilsDemo.values.contains(u['telephone']);

  // --- Journal, notifications ---------------------------------------------------------------
  void _journaliser(int? idUser, String action, [Object? details]) => _insert('journal_activite', 'id_journal', {
    'id_user': idUser,
    'action': action,
    'details': details == null ? null : (details is String ? details : jsonEncode(details)),
    'ip': 'mode démo',
    'date': horodatage(),
  });

  void _notifier(int idUser, String type, String titre, String message) {
    if (_user(idUser) == null) return;
    _insert('notifications', 'id_notification', {
      'id_user': idUser,
      'type': type,
      'titre': titre,
      'message': message,
      'lu': false,
      'date': horodatage(),
    });
  }

  void _notifierPermission(String permission, String type, String titre, String message) {
    for (final u in _t('users').where((u) => u['actif'] == true && _peut(u, permission)).toList()) {
      _notifier(u['id_user'], type, titre, message);
    }
  }

  void _notifierAdmins(String type, String titre, String message) =>
      _notifierPermission(_P.commandesGerer, type, titre, message);

  // --- Paramètres --------------------------------------------------------------------------------
  bool get _creationBoutique => (db['parametres'] as J)['creation_boutique'] as bool? ?? true;

  // --- Catalogue -------------------------------------------------------------------------------------
  J? _boutique(dynamic id) => id == null ? null : _un('boutiques', (b) => b['id_boutique'] == id);
  J? _categorie(dynamic id) => _un('categories', (c) => c['id_categorie'] == id);

  bool _visible(J p) {
    final b = _boutique(p['id_boutique']);
    return p['statut'] == 'publie' && (b == null || b['active'] == true);
  }

  /// Produit avec sa catégorie, sa boutique et sa note (PRODUIT_SELECT).
  J _produitVue(J p) {
    final c = _categorie(p['id_categorie']);
    final b = _boutique(p['id_boutique']);
    final avis = _t('avis').where((a) => a['id_produit'] == p['id_produit']).toList();
    final moyenne = avis.isEmpty ? 0 : avis.map((a) => a['note_avis'] as int).reduce((a, b) => a + b) / avis.length;
    return {
      ...p,
      'categorie': c?['nom'],
      'type_categorie': c?['type'],
      'boutique': b?['nom'],
      'ville_boutique': b?['ville'],
      'id_vendeur': b?['id_vendeur'],
      'telephone_boutique': b?['telephone'],
      'note_moyenne': (moyenne * 10).round() / 10,
      'nb_avis': avis.length,
    };
  }

  J? _produit(dynamic id) => _un('produits', (p) => p['id_produit'] == id);

  // --- Panier et commandes ------------------------------------------------------------------------------
  int _fraisLivraison(String? ville, int sousTotal) {
    final v = (ville ?? '').trim().toLowerCase();
    final regle =
        _un('regles_livraison', (r) => '${r['ville']}'.toLowerCase() == v) ??
        _un('regles_livraison', (r) => r['ville'] == '*');
    if (regle == null || sousTotal == 0) return 0;
    if (regle['seuil_gratuite'] != null && sousTotal >= regle['seuil_gratuite']) return 0;
    return regle['frais'];
  }

  J _lirePanier(int idUser, [String? ville]) {
    final items = [
      for (final i in _t('panier_items').where((i) => i['id_user'] == idUser))
        if (_produit(i['id_produit']) case final p?)
          {
            'id_produit': p['id_produit'],
            'quantite': i['quantite'],
            'nom': p['nom'],
            'prix_produit': p['prix_produit'],
            'image_produit': p['image_produit'],
            'quantite_stock': p['quantite_stock'],
            'unite': p['unite'],
            'statut': p['statut'],
            'total_ligne': (p['prix_produit'] as int) * (i['quantite'] as int),
            'disponible': _visible(p),
          },
    ]..sort((a, b) => '${a['nom']}'.compareTo('${b['nom']}'));
    final sousTotal = items.fold<int>(0, (s, i) => s + (i['total_ligne'] as int));
    final frais = _fraisLivraison(ville, sousTotal);
    return {
      'id_panier': idUser,
      'items': items,
      'nombre_articles': items.fold<int>(0, (s, i) => s + (i['quantite'] as int)),
      'sous_total': sousTotal,
      'frais_livraison': frais,
      'total': sousTotal + frais,
      'adresse_par_defaut': _user(idUser)?['adresse'],
    };
  }

  J? _commande(dynamic id) => _un('commandes', (c) => c['id_commande'] == id);

  String _libelle(String statut) => _S.libelles[statut] ?? statut;

  /// Changement de statut : historique et notification du client (commerce.suivreStatut).
  void _suivreStatut(int id, String statut, {int? auteur, String? commentaire, String? message}) {
    _insert('commande_historique', 'id_historique', {
      'id_commande': id,
      'statut': statut,
      'commentaire': commentaire,
      'id_auteur': auteur,
      'date': horodatage(),
    });
    final texte =
        message ??
        switch (statut) {
          _S.attente => 'Votre commande #$id est bien reçue. Procédez au paiement pour la confirmer.',
          _S.enCours => 'Votre commande #$id est confirmée. Nous la préparons.',
          _S.preparation => 'Votre commande #$id est en préparation.',
          _S.livraison => 'Votre commande #$id est en route vers vous.',
          _S.livree => 'Votre commande #$id a été livrée. Confirmez la réception dans l’application.',
          _S.cloturee => 'Commande #$id clôturée. Merci pour votre confiance !',
          _S.echec => 'La livraison de votre commande #$id n’a pas pu être effectuée.',
          _S.annulee => 'Votre commande #$id a été annulée.',
          _ => 'Commande #$id : $statut.',
        };
    _notifier(_commande(id)!['id_user'], 'commande', 'Commande #$id : ${_libelle(statut)}', texte);
  }

  J _detailCommande(int id) {
    final c = _commande(id)!;
    final u = _user(c['id_user']);
    final l = _user(c['id_livreur']);
    final avis = _un('avis', (a) => a['id_commande'] == id);
    return {
      ...c,
      'client_nom': u?['nom'],
      'client_prenom': u?['prenom'],
      'client_telephone': u?['telephone'],
      'livreur_nom': l?['nom'],
      'livreur_prenom': l?['prenom'],
      'livreur_telephone': l?['telephone'],
      'items': [
        for (final i in _t('commande_items').where((i) => i['id_commande'] == id))
          {
            ...i,
            'image_produit': _produit(i['id_produit'])?['image_produit'],
            'total_ligne': (i['prix_unitaire'] as int) * (i['quantite'] as int),
          },
      ],
      'paiements': [
        for (final p in _t('payements').where((p) => p['id_commande'] == id).toList().reversed) _paiementVue(p),
      ],
      'avis': avis,
      'libelle_statut': _libelle(c['statut_commande']),
      'historique': [
        for (final h in _t(
          'commande_historique',
        ).where((h) => h['id_commande'] == id).toList()..sort((a, b) => '${a['date']}'.compareTo('${b['date']}')))
          {
            ...h,
            'auteur_prenom': _user(h['id_auteur'])?['prenom'],
            'auteur_nom': _user(h['id_auteur'])?['nom'],
            'libelle': _libelle(h['statut']),
          },
      ],
    };
  }

  J _paiementVue(J p) {
    final f = _un('factures', (f) => f['id_payement'] == p['id_payement']);
    return {...p, 'numero_facture': f?['numero_facture'], 'date_facture': f?['date_facture']};
  }

  bool _vendeurDe(int idCommande, int idUser) => _t('commande_items').any((i) {
    if (i['id_commande'] != idCommande) return false;
    final b = _boutique(_produit(i['id_produit'])?['id_boutique']);
    return b != null && b['id_vendeur'] == idUser;
  });

  bool _peutVoirCommande(J u, J c) {
    final id = u['id_user'];
    if (c['id_user'] == id || c['id_livreur'] == id) return true;
    if (_peut(u, _P.commandesGerer)) return true;
    if (_peut(u, _P.livraisonsEffectuer) && _S.aLivrer.contains(c['statut_commande']) && c['id_livreur'] == null) {
      return true;
    }
    return _vendeurDe(c['id_commande'], id);
  }

  void _restituerStock(int id) {
    for (final i in _t('commande_items').where((i) => i['id_commande'] == id)) {
      final p = _produit(i['id_produit']);
      if (p != null) p['quantite_stock'] = (p['quantite_stock'] as int) + (i['quantite'] as int);
    }
  }

  J _verifierPanier(int idUser, String? ville) {
    final panier = _lirePanier(idUser, ville);
    final items = (panier['items'] as List).cast<J>();
    if (items.isEmpty) throw _bad('Panier vide');
    final problemes = [
      for (final i in items)
        if (i['disponible'] != true || (i['quantite'] as int) > (i['quantite_stock'] as int))
          {
            'id_produit': i['id_produit'],
            'nom': i['nom'],
            'demande': i['quantite'],
            'disponible': i['disponible'] == true ? i['quantite_stock'] : 0,
          },
    ];
    if (problemes.isNotEmpty) throw _conflict('Stock insuffisant', problemes);
    return panier;
  }

  /// Réponse de l'opérateur de paiement simulé (backend/src/services/payment.js).
  void _resultatPaiement(String reference, bool succes) {
    final p = _un('payements', (p) => p['reference_transaction'] == reference);
    if (p == null || p['statut_paie'] != 'en_attente') return;
    final c = _commande(p['id_commande'])!;
    final id = c['id_commande'] as int;
    if (!succes) {
      p['statut_paie'] = 'echoue';
      p['message'] = 'Transaction refusée par l’opérateur (solde insuffisant)';
      _notifier(
        c['id_user'],
        'paiement',
        'Paiement échoué',
        'Le paiement de la commande #$id a échoué. Vous pouvez réessayer.',
      );
      onChange?.call();
      return;
    }
    p['statut_paie'] = 'reussi';
    p['message'] = 'Paiement confirmé par l’opérateur';
    final confirmee = c['statut_commande'] == _S.attente;
    if (confirmee) c['statut_commande'] = _S.enCours;
    _insert('factures', 'id_facture', {
      'id_payement': p['id_payement'],
      'numero_facture': 'FAC-${DateTime.now().year}-${'${p['id_payement']}'.padLeft(6, '0')}',
      'date_facture': horodatage(),
      'statut_facture': 'payee',
    });
    final texte = 'Paiement de ${p['montant']} FCFA reçu : votre commande #$id est confirmée.';
    if (confirmee) {
      _suivreStatut(id, _S.enCours, commentaire: 'Paiement ${p['mode_paie']} réussi', message: texte);
    } else {
      _notifier(c['id_user'], 'paiement', 'Paiement réussi', texte);
    }
    _notifierAdmins('commande', 'Nouvelle commande payée', 'Commande #$id à préparer.');
    _notifierPermission(
      _P.livraisonsEffectuer,
      'livraison',
      'Nouvelle livraison disponible',
      'Commande #$id à livrer à ${c['ville']}.',
    );
    final vendeurs = {
      for (final i in _t('commande_items').where((i) => i['id_commande'] == id))
        if (_boutique(_produit(i['id_produit'])?['id_boutique']) case final b?) b['id_vendeur'] as int,
    };
    for (final v in vendeurs) {
      _notifier(v, 'commande', 'Nouvelle vente', 'Vos produits ont été commandés (#$id).');
    }
    onChange?.call();
  }

  // --- Routage ----------------------------------------------------------------------------------------------
  /// Traite une requête « [methode] /api[chemin] ».
  DemoReponse traiter(String methode, String chemin, Map<String, String> query, J body, String? token) {
    final s = chemin.split('/').where((e) => e.isNotEmpty).toList();
    final r = _router(methode, s, query, body, token);
    if (methode != 'GET') onChange?.call();
    return r;
  }

  DemoReponse _router(String m, List<String> s, Map<String, String> q, J b, String? token) {
    J moi() => _authentifier(token)!;
    switch ((m, s)) {
      case ('GET', ['sante']):
        return (200, {'statut': 'ok'});
      case ('GET', ['parametres']):
        return (200, {'creation_boutique': _creationBoutique, 'comptes_demo': true});

      // --- Authentification ---
      case ('POST', ['auth', 'inscription']):
        return _inscription(b);
      case ('POST', ['auth', 'connexion']):
        return _connexion(b);
      case ('POST', ['auth', 'demo']):
        final tel = profilsDemo[b['profil'] ?? 'client'];
        if (tel == null) throw _bad('Profil de démonstration invalide (${profilsDemo.keys.join(', ')})');
        final u = _un('users', (u) => u['telephone'] == tel);
        if (u == null || u['actif'] != true) throw _notFound('Compte de démonstration indisponible');
        _journaliser(u['id_user'], 'connexion.demo', b['profil'] ?? 'client');
        u['derniere_connexion'] = horodatage();
        return (200, {'message': 'Connexion de démonstration', 'token': _token(u), 'utilisateur': _publicUser(u)});
      case ('POST', ['auth', 'deconnexion']):
        final u = moi();
        if (!_estCompteDemo(u)) u['token_version'] = (u['token_version'] as int) + 1;
        return (200, {'message': 'Déconnexion réussie'});

      // --- Compte ---
      case ('GET', ['compte']):
        return (200, _publicUser(moi()));
      case ('PUT', ['compte']):
        return _modifierCompte(moi(), b);
      case ('PUT', ['compte', 'mot-de-passe']):
        return _changerMotDePasse(moi(), b);
      case ('POST', ['compte', '2fa', _]):
        moi();
        throw _forbidden('La double authentification n’est pas disponible en mode démo');
      case ('DELETE', ['compte']):
        return _supprimerCompte(moi(), b);
      case ('PUT', ['compte', 'newsletter']):
        final u = moi();
        u['newsletter'] = b['abonne'] == true;
        return (200, {'abonne': u['newsletter']});
      case ('POST', ['newsletter']):
        _requis(b, ['email']);
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch('${b['email']}'.trim())) {
          throw _bad('Adresse email invalide');
        }
        return (201, {'message': 'Inscription à la newsletter confirmée'});
      case ('POST', ['uploads']):
        throw _bad('Aucune image reçue (champ « image »)');

      // --- Catalogue ---
      case ('GET', ['categories']):
        return (200, _categories(q));
      case ('POST', ['categories']):
        _exiger(moi(), [_P.categoriesGerer]);
        return _enregistrerCategorie(null, b);
      case ('PUT', ['categories', final id]):
        _exiger(moi(), [_P.categoriesGerer]);
        return _enregistrerCategorie(_int(id, 'id'), b);
      case ('DELETE', ['categories', final id]):
        _exiger(moi(), [_P.categoriesGerer]);
        final idc = _int(id, 'id');
        if (_t('produits').any((p) => p['id_categorie'] == idc)) {
          throw _conflict('Impossible de supprimer une catégorie contenant des produits');
        }
        if (_categorie(idc) == null) throw _notFound('Catégorie introuvable');
        _t('categories').removeWhere((c) => c['id_categorie'] == idc);
        return (204, null);
      case ('GET', ['produits']):
        return (200, _produits(q));
      case ('GET', ['produits', 'gestion']):
        final u = moi();
        _exiger(u, [_P.produitsGerer, _P.produitsModerer]);
        final tous = _peut(u, _P.produitsModerer) && q['tous'] != 'false';
        final rows = _t('produits').map(_produitVue).where((p) => tous || p['id_vendeur'] == u['id_user']).toList()
          ..sort((a, b) => '${b['date_modification']}'.compareTo('${a['date_modification']}'));
        return (200, rows);
      case ('GET', ['produits', final id]):
        final u = _authentifier(token, optionnel: true);
        final p = _produit(_int(id, 'id'));
        if (p == null) throw _notFound('Produit introuvable');
        final vue = _produitVue(p);
        final visible =
            p['statut'] == 'publie' || _peut(u, _P.produitsModerer) || (u != null && vue['id_vendeur'] == u['id_user']);
        if (!visible) throw _notFound('Produit introuvable');
        return (200, vue);
      case ('GET', ['produits', final id, 'avis']):
        final idp = _int(id, 'id');
        final rows = [
          for (final a in _t('avis').where((a) => a['id_produit'] == idp))
            {...a, 'prenom': _user(a['id_user'])?['prenom'], 'nom': '${_initiale(_user(a['id_user'])?['nom'])}.'},
        ]..sort((a, b) => '${b['date_avis']}'.compareTo('${a['date_avis']}'));
        return (200, rows);
      case ('POST', ['produits', final id, 'avis']):
        return _avisProduit(moi(), _int(id, 'id'), b);
      case ('POST', ['produits']):
        return _creerProduit(moi(), b);
      case ('PUT', ['produits', final id]):
        final (u, p) = _produitGerable(moi(), id);
        final d = _validerProduit({...p, ...b});
        final doublon = _t('produits').any(
          (x) =>
              '${x['nom']}'.toLowerCase() == '${d['nom']}'.toLowerCase() &&
              x['id_boutique'] == p['id_boutique'] &&
              x['id_produit'] != p['id_produit'],
        );
        if (doublon) throw _conflict('Produit existant');
        p.addAll({...d, 'date_modification': horodatage()});
        _journaliserSiAdmin(u, 'produit.modifier', {'id_produit': p['id_produit']});
        return (200, _produitVue(p));
      case ('PATCH', ['produits', final id, 'stock']):
        final (_, p) = _produitGerable(moi(), id);
        p['quantite_stock'] = _int(b['quantite_stock'], 'quantite_stock', min: 0);
        p['date_modification'] = horodatage();
        return (200, _produitVue(p));
      case ('PATCH', ['produits', final id, 'statut']):
        final (_, p) = _produitGerable(moi(), id);
        if (!['brouillon', 'publie', 'retire'].contains(b['statut'])) throw _bad('Statut de produit invalide');
        p['statut'] = b['statut'];
        p['date_modification'] = horodatage();
        return (200, _produitVue(p));
      case ('DELETE', ['produits', final id]):
        final (_, p) = _produitGerable(moi(), id, absent: 'Suppression impossible : produit absent');
        if (_t('commande_items').any((i) => i['id_produit'] == p['id_produit'])) {
          p['statut'] = 'retire';
          p['date_modification'] = horodatage();
          return (200, {'message': 'Produit déjà commandé : retiré du catalogue', 'retire': true});
        }
        _t('produits').remove(p);
        _t('panier_items').removeWhere((i) => i['id_produit'] == p['id_produit']);
        return (204, null);

      // --- Boutiques ---
      case ('GET', ['boutiques', 'moi']):
        final bq = _un('boutiques', (x) => x['id_vendeur'] == moi()['id_user']);
        if (bq == null) throw _notFound('Aucune boutique');
        return (200, bq);
      case ('POST', ['boutiques']):
        return _creerBoutique(moi(), b);
      case ('PUT', ['boutiques', 'moi']):
        final u = moi();
        _exiger(u, [_P.boutiqueGerer]);
        final bq = _un('boutiques', (x) => x['id_vendeur'] == u['id_user']);
        if (bq == null) throw _notFound('Aucune boutique');
        final d = {...bq, ...b};
        if ('${d['nom'] ?? ''}'.trim().isEmpty) throw _bad('Le nom est obligatoire');
        bq.addAll({
          'nom': '${d['nom']}'.trim(),
          'description': d['description'],
          'adresse': d['adresse'],
          'ville': d['ville'],
          'telephone': d['telephone'],
        });
        return (200, bq);
      case ('GET', ['boutiques', 'moi', 'ventes']):
        final u = moi();
        _exiger(u, [_P.boutiqueGerer]);
        return (200, _ventes(u['id_user']));
      case ('GET', ['boutiques', final id]):
        final bq = _boutique(_int(id, 'id'));
        if (bq == null || bq['active'] != true) throw _notFound('Boutique introuvable');
        return (200, Map.of(bq)..remove('active'));

      // --- Panier ---
      case ('GET', ['panier']):
        return (200, _lirePanier(moi()['id_user'], q['ville']));
      case ('POST', ['panier', 'items']):
        final u = moi();
        final idp = _int(b['id_produit'], 'id_produit');
        final quantite = _int(b['quantite'] ?? 1, 'quantite', min: 1);
        final p = _produitDisponible(idp);
        final ligne = _un('panier_items', (i) => i['id_user'] == u['id_user'] && i['id_produit'] == idp);
        final total = ((ligne?['quantite'] as int?) ?? 0) + quantite;
        if (total > (p['quantite_stock'] as int)) {
          throw _conflict('Stock insuffisant (disponible : ${p['quantite_stock']})');
        }
        if (ligne == null) {
          _t('panier_items').add({'id_user': u['id_user'], 'id_produit': idp, 'quantite': total});
        } else {
          ligne['quantite'] = total;
        }
        return (201, _lirePanier(u['id_user']));
      case ('PATCH', ['panier', 'items', final id]):
        final u = moi();
        final idp = _int(id, 'id_produit');
        final quantite = _int(b['quantite'], 'quantite', min: 0);
        if (quantite == 0) {
          _t('panier_items').removeWhere((i) => i['id_user'] == u['id_user'] && i['id_produit'] == idp);
        } else {
          final p = _produitDisponible(idp);
          if (quantite > (p['quantite_stock'] as int)) {
            throw _conflict('Stock insuffisant (disponible : ${p['quantite_stock']})');
          }
          final ligne = _un('panier_items', (i) => i['id_user'] == u['id_user'] && i['id_produit'] == idp);
          if (ligne == null) throw _notFound('Produit absent du panier');
          ligne['quantite'] = quantite;
        }
        return (200, _lirePanier(u['id_user']));
      case ('DELETE', ['panier', 'items', final id]):
        final u = moi();
        final idp = _int(id, 'id_produit');
        _t('panier_items').removeWhere((i) => i['id_user'] == u['id_user'] && i['id_produit'] == idp);
        return (200, _lirePanier(u['id_user']));
      case ('DELETE', ['panier']):
        final u = moi();
        _t('panier_items').removeWhere((i) => i['id_user'] == u['id_user']);
        return (200, _lirePanier(u['id_user']));

      // --- Commandes ---
      case ('POST', ['commandes', 'recapitulatif']):
        return (200, _verifierPanier(moi()['id_user'], b['ville']));
      case ('POST', ['commandes']):
        return _passerCommande(moi(), b);
      case ('GET', ['commandes']):
        final u = moi();
        final rows = [
          for (final c in _t('commandes').where((c) => c['id_user'] == u['id_user']))
            {...c, 'nb_articles': _t('commande_items').where((i) => i['id_commande'] == c['id_commande']).length},
        ]..sort(_parDateDesc);
        return (200, rows);
      case ('GET', ['commandes', final id]):
        final u = moi();
        final c = _commande(_int(id, 'id'));
        if (c == null || !_peutVoirCommande(u, c)) throw _notFound('Commande introuvable');
        return (200, _detailCommande(c['id_commande']));
      case ('POST', ['commandes', final id, 'annuler']):
        final u = moi();
        final c = _commande(_int(id, 'id'));
        if (c == null || c['id_user'] != u['id_user']) throw _notFound('Commande introuvable');
        if (c['statut_commande'] != _S.attente) throw _conflict('Seule une commande non payée peut être annulée');
        if (_paiementEnAttente(c['id_commande'])) throw _conflict('Un paiement est en cours de traitement');
        c['statut_commande'] = _S.annulee;
        _restituerStock(c['id_commande']);
        _suivreStatut(c['id_commande'], _S.annulee, auteur: u['id_user'], commentaire: 'Annulée par le client');
        return (200, _detailCommande(c['id_commande']));
      case ('POST', ['commandes', final id, 'reception']):
        final u = moi();
        final c = _commande(_int(id, 'id'));
        if (c == null || c['id_user'] != u['id_user']) throw _notFound('Commande introuvable');
        if (c['statut_commande'] != _S.livree) throw _conflict('Seule une commande livrée peut être réceptionnée');
        c['statut_commande'] = _S.cloturee;
        final idc = c['id_commande'] as int;
        _suivreStatut(idc, _S.cloturee, auteur: u['id_user'], commentaire: 'Réception confirmée par le client');
        _notifierAdmins('commande', 'Réception confirmée', 'Le client a confirmé la réception de la commande #$idc.');
        return (200, _detailCommande(idc));
      case ('POST', ['commandes', final id, 'avis']):
        final u = moi();
        final idc = _int(id, 'id');
        final note = _note(b);
        final c = _commande(idc);
        if (c == null || c['id_user'] != u['id_user']) throw _notFound('Commande introuvable');
        if (![_S.livree, _S.cloturee].contains(c['statut_commande'])) {
          throw _conflict('La commande doit être livrée pour être notée');
        }
        _enregistrerAvis(u['id_user'], 'id_commande', idc, note, b['commentaire']);
        return (201, _detailCommande(idc));

      // --- Paiements ---
      case ('GET', ['paiements', 'modes']):
        moi();
        return (
          200,
          [
            {'code': 'MTN_MOMO', 'libelle': 'MTN Mobile Money'},
            {'code': 'ORANGE_MONEY', 'libelle': 'Orange Money'},
          ],
        );
      case ('POST', ['paiements']):
        return _payer(moi(), b);
      case ('GET', ['paiements', final id]):
        final u = moi();
        final p = _un('payements', (p) => p['id_payement'] == _int(id, 'id'));
        final c = p == null ? null : _commande(p['id_commande']);
        if (p == null || (c!['id_user'] != u['id_user'] && !_peut(u, _P.paiementsVoir))) {
          throw _notFound('Paiement introuvable');
        }
        return (200, {..._paiementVue(p), 'id_user': c['id_user'], 'statut_commande': c['statut_commande']});

      // --- Livraisons ---
      case ('GET', ['livraisons', 'frais']):
        final sousTotal = int.tryParse(q['sous_total'] ?? '') ?? 0;
        return (200, {'ville': q['ville'], 'frais_livraison': _fraisLivraison(q['ville'], sousTotal)});
      case ('GET', ['livraisons']):
        return _livraisons(moi());
      case ('POST', ['livraisons', final id, 'prendre']):
        final u = moi();
        _exiger(u, [_P.livraisonsEffectuer]);
        final c = _commande(_int(id, 'id'));
        if (c == null ||
            !_S.aLivrer.contains(c['statut_commande']) ||
            (c['id_livreur'] != null && c['id_livreur'] != u['id_user'])) {
          throw _conflict('Commande indisponible');
        }
        c['statut_commande'] = _S.livraison;
        c['id_livreur'] = u['id_user'];
        final idc = c['id_commande'] as int;
        _suivreStatut(
          idc,
          _S.livraison,
          auteur: u['id_user'],
          commentaire: 'Prise en charge par ${u['prenom']} ${u['nom']}',
          message: 'Votre commande #$idc est en route avec ${u['prenom']} (${u['telephone']}).',
        );
        return (200, _detailCommande(idc));
      case ('POST', ['livraisons', final id, 'confirmer']):
        final (u, c) = _maLivraison(moi(), id);
        c['statut_commande'] = _S.livree;
        c['date_livraison'] = horodatage();
        _suivreStatut(c['id_commande'], _S.livree, auteur: u['id_user'], commentaire: 'Livraison effectuée');
        return (200, _detailCommande(c['id_commande']));
      case ('POST', ['livraisons', final id, 'echec']):
        final (u, c) = _maLivraison(moi(), id, motifRequis: b);
        final idc = c['id_commande'] as int;
        c['statut_commande'] = _S.echec;
        c['motif_echec'] = b['motif'];
        _suivreStatut(
          idc,
          _S.echec,
          auteur: u['id_user'],
          commentaire: b['motif'],
          message: 'Livraison de la commande #$idc non effectuée : ${b['motif']}. Nous vous recontactons.',
        );
        _notifierAdmins('livraison', 'Échec de livraison', 'Commande #$idc : ${b['motif']}');
        return (200, _detailCommande(idc));

      // --- Messagerie et notifications ---
      case ('GET', ['messages', 'conversations']):
        return (200, _conversations(moi()['id_user']));
      case ('GET', ['messages', 'support']):
        moi();
        final admins = _t('users').where((u) => u['actif'] == true && _peut(u, _P.commandesGerer)).toList()
          ..sort((a, b) => (a['id_user'] as int).compareTo(b['id_user']));
        if (admins.isEmpty) throw _notFound('Support indisponible');
        final a = admins.first;
        return (200, {'id_user': a['id_user'], 'nom': a['nom'], 'prenom': a['prenom'], 'telephone': a['telephone']});
      case ('GET', ['messages', 'non-lus']):
        final id = moi()['id_user'];
        return (
          200,
          {'non_lus': _t('messagerie').where((x) => x['id_destinataire'] == id && x['date_lecture'] == null).length},
        );
      case ('GET', ['messages', final autre]):
        return _filMessages(moi()['id_user'], _int(autre, 'idUser'), int.tryParse(q['apres'] ?? '') ?? 0);
      case ('POST', ['messages']):
        return _envoyerMessage(moi(), b);
      case ('GET', ['notifications']):
        final id = moi()['id_user'];
        final items = _t('notifications').where((n) => n['id_user'] == id).toList().reversed.take(100).toList();
        return (200, {'non_lues': items.where((n) => n['lu'] != true).length, 'items': items});
      case ('POST', ['notifications', 'tout-lu']):
        final id = moi()['id_user'];
        for (final n in _t('notifications').where((n) => n['id_user'] == id)) {
          n['lu'] = true;
        }
        return (200, {'ok': true});
      case ('POST', ['notifications', final id, 'lu']):
        final u = moi();
        _un('notifications', (n) => n['id_notification'] == _int(id, 'id') && n['id_user'] == u['id_user'])?['lu'] =
            true;
        return (200, {'ok': true});

      // --- Administration ---
      case (_, ['admin', ...final reste]):
        return _admin(m, reste, q, b, moi());
    }
    throw DemoErreur(404, 'Route introuvable');
  }

  int _parDateDesc(J a, J b) {
    final d = '${b['date_commande']}'.compareTo('${a['date_commande']}');
    return d != 0 ? d : (b['id_commande'] as int).compareTo(a['id_commande']);
  }

  bool _paiementEnAttente(int idCommande) =>
      _t('payements').any((p) => p['id_commande'] == idCommande && p['statut_paie'] == 'en_attente');

  int _note(J b) {
    final note = _int(b['note_avis'], 'note_avis', min: 1);
    if (note > 5) throw _bad('La note doit être comprise entre 1 et 5');
    return note;
  }

  void _enregistrerAvis(int idUser, String cle, int id, int note, dynamic commentaire) {
    final existant = _un('avis', (a) => a['id_user'] == idUser && a[cle] == id);
    final valeurs = {'note_avis': note, 'commentaire': commentaire, 'date_avis': horodatage()};
    if (existant != null) {
      existant.addAll(valeurs);
    } else {
      _insert('avis', 'id_avis', {
        'id_user': idUser,
        'id_produit': cle == 'id_produit' ? id : null,
        'id_commande': cle == 'id_commande' ? id : null,
        ...valeurs,
      });
    }
  }

  void _journaliserSiAdmin(J u, String action, Object details) {
    if (_peut(u, _P.produitsModerer)) _journaliser(u['id_user'], action, details);
  }

  // --- Authentification et compte ----------------------------------------------------------------
  DemoReponse _inscription(J b) {
    _requis(b, ['nom', 'prenom', 'telephone', 'mot_de_passe']);
    final type = b['type_compte'] ?? 'client';
    if ('${b['mot_de_passe']}'.length < 6) throw _bad('Le mot de passe doit contenir au moins 6 caractères');
    if (!['client', 'vendeur'].contains(type)) throw _bad('Type de compte invalide');
    if (type == 'vendeur' && !_creationBoutique) {
      throw _forbidden('Les inscriptions vendeur sont actuellement fermées. Créez un compte client.');
    }
    final email = '${b['email'] ?? ''}'.trim().toLowerCase();
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      throw _bad('Adresse email invalide');
    }
    final tel = '${b['telephone']}'.trim();
    if (_t('users').any((u) => u['telephone'] == tel || (email.isNotEmpty && u['email'] == email))) {
      throw _conflict('Un compte existe déjà avec ce téléphone ou cet email');
    }
    final u = _nouvelUtilisateur(
      nom: '${b['nom']}'.trim(),
      prenom: '${b['prenom']}'.trim(),
      email: email.isEmpty ? null : email,
      telephone: tel,
      adresse: b['adresse'],
      mdp: '${b['mot_de_passe']}',
      roles: ['client', if (type == 'vendeur') 'vendeur'],
    );
    u['newsletter'] = b['newsletter'] == true;
    return (201, {'token': _token(u), 'utilisateur': _publicUser(u)});
  }

  J _nouvelUtilisateur({
    required String nom,
    required String prenom,
    String? email,
    required String telephone,
    String? adresse,
    required String mdp,
    required List<String> roles,
  }) {
    final u = _insert('users', 'id_user', {
      'nom': nom,
      'prenom': prenom,
      'email': email,
      'telephone': telephone,
      'adresse': adresse,
      'profil': null,
      'mdp': mdp,
      'actif': true,
      'newsletter': false,
      'token_version': 0,
      'derniere_connexion': null,
      'date_creation': horodatage(),
    });
    for (final r in roles) {
      _t('user_roles').add({'id_user': u['id_user'], 'role': r});
    }
    return u;
  }

  DemoReponse _connexion(J b) {
    _requis(b, ['identifiant', 'mot_de_passe']);
    final id = '${b['identifiant']}'.trim();
    final u = _un('users', (u) => u['telephone'] == id || u['email'] == id.toLowerCase());
    if (u == null || u['mdp'] != b['mot_de_passe']) {
      if (u != null) _journaliser(u['id_user'], 'connexion.echec', 'Mot de passe incorrect');
      throw _unauth("Nom d'utilisateur ou mot de passe incorrect");
    }
    if (u['actif'] != true) throw _forbidden('Compte désactivé. Contactez l’administrateur.');
    _journaliser(u['id_user'], 'connexion');
    u['derniere_connexion'] = horodatage();
    return (200, {'message': 'Connexion réussie', 'token': _token(u), 'utilisateur': _publicUser(u)});
  }

  DemoReponse _modifierCompte(J u, J b) {
    final d = {
      for (final c in ['nom', 'prenom', 'email', 'telephone', 'adresse', 'profil']) c: b.containsKey(c) ? b[c] : u[c],
    };
    for (final c in ['nom', 'prenom', 'telephone']) {
      if ('${d[c] ?? ''}'.trim().isEmpty) throw _bad('Nom, prénom et téléphone sont obligatoires');
      d[c] = '${d[c]}'.trim();
    }
    final email = '${d['email'] ?? ''}'.trim().toLowerCase();
    d['email'] = email.isEmpty ? null : email;
    final doublon = _t('users').any(
      (x) =>
          x['id_user'] != u['id_user'] &&
          (x['telephone'] == d['telephone'] || (email.isNotEmpty && x['email'] == email)),
    );
    if (doublon) throw _conflict('Ce téléphone ou cet email est déjà utilisé');
    u.addAll(d);
    return (200, _publicUser(u));
  }

  DemoReponse _changerMotDePasse(J u, J b) {
    _requis(b, ['ancien', 'nouveau']);
    if (b['ancien'] != u['mdp']) throw _bad('Ancien mot de passe incorrect');
    final nouveau = '${b['nouveau']}';
    if (nouveau.length < 6) throw _bad('Le mot de passe doit contenir au moins 6 caractères');
    if (_roles(u['id_user']).contains('admin') &&
        (nouveau.length < 10 ||
            !RegExp('[a-z]').hasMatch(nouveau) ||
            !RegExp('[A-Z]').hasMatch(nouveau) ||
            !RegExp(r'\d').hasMatch(nouveau))) {
      throw _bad(
        'Mot de passe administrateur trop faible : au moins 10 caractères, avec une minuscule, une majuscule et un chiffre',
      );
    }
    u['mdp'] = nouveau;
    u['token_version'] = (u['token_version'] as int) + 1;
    _journaliser(u['id_user'], 'compte.mot_de_passe');
    return (200, {'message': 'Mot de passe modifié', 'token': _token(u)});
  }

  DemoReponse _supprimerCompte(J u, J b) {
    _requis(b, ['mot_de_passe']);
    if (b['mot_de_passe'] != u['mdp']) throw _bad('Mot de passe incorrect');
    if (_estCompteDemo(u)) throw _forbidden('Un compte de démonstration ne peut pas être supprimé');
    final id = u['id_user'] as int;
    if (_roles(id).contains('admin') &&
        !_t('users').any((x) => x['id_user'] != id && x['actif'] == true && _roles(x['id_user']).contains('admin'))) {
      throw _conflict('Vous êtes le dernier administrateur : nommez-en un autre avant de supprimer ce compte');
    }
    _t('panier_items').removeWhere((i) => i['id_user'] == id);
    _t('notifications').removeWhere((n) => n['id_user'] == id);
    _t('messagerie').removeWhere((x) => x['id_expediteur'] == id || x['id_destinataire'] == id);
    _t('user_roles').removeWhere((r) => r['id_user'] == id);
    for (final bq in _t('boutiques').where((x) => x['id_vendeur'] == id)) {
      bq['active'] = false;
    }
    u.addAll({
      'nom': 'supprimé',
      'prenom': 'Compte',
      'email': null,
      'telephone': 'supprime-$id',
      'adresse': null,
      'profil': null,
      'mdp': '',
      'actif': false,
      'newsletter': false,
      'token_version': (u['token_version'] as int) + 1,
    });
    for (final c in _t('commandes').where((c) => c['id_user'] == id)) {
      c['telephone_livraison'] = '-';
      c['adresse_livraison'] = '(supprimée)';
    }
    _journaliser(id, 'compte.supprimer');
    return (204, null);
  }

  // --- Catalogue ----------------------------------------------------------------------------------
  List<J> _categories(Map<String, String> q) {
    final recherche = (q['q'] ?? '').trim();
    final rows = [
      for (final c in _t('categories'))
        if (_like(c['nom'], recherche) && (q['type'] == null || c['type'] == q['type']))
          {
            ...c,
            'nb_produits': _t('produits').where((p) => p['id_categorie'] == c['id_categorie'] && _visible(p)).length,
          },
    ];
    rows.sort((a, b) {
      final t = '${a['type']}'.compareTo('${b['type']}');
      return t != 0 ? t : '${a['nom']}'.compareTo('${b['nom']}');
    });
    return rows;
  }

  DemoReponse _enregistrerCategorie(int? id, J b) {
    _requis(b, ['nom']);
    final type = b['type'] ?? 'phytosanitaire';
    if (!['phytosanitaire', 'elevage'].contains(type)) throw _bad('Type de catégorie invalide');
    final nom = '${b['nom']}'.trim();
    if (id != null && _categorie(id) == null) throw _notFound('Catégorie introuvable');
    if (_t('categories').any((c) => c['nom'] == nom && c['id_categorie'] != id)) {
      throw _conflict('Catégorie existante');
    }
    final valeurs = {'nom': nom, 'description': b['description'], 'type': type};
    if (id == null) return (201, _insert('categories', 'id_categorie', valeurs));
    return (200, _categorie(id)!..addAll(valeurs));
  }

  List<J> _produits(Map<String, String> q) {
    final recherche = q['q']?.trim();
    final categorie = q['categorie'] == null ? null : _int(q['categorie'], 'categorie');
    final boutique = q['boutique'] == null ? null : _int(q['boutique'], 'boutique');
    final min = q['prix_min'] == null ? null : _int(q['prix_min'], 'prix_min', min: 0);
    final max = q['prix_max'] == null ? null : _int(q['prix_max'], 'prix_max', min: 0);
    final rows = _t('produits').where(_visible).map(_produitVue).where((p) {
      if (recherche != null &&
          recherche.isNotEmpty &&
          !_like(p['nom'], recherche) &&
          !_like(p['description'], recherche) &&
          !_like(p['categorie'], recherche)) {
        return false;
      }
      if (categorie != null && p['id_categorie'] != categorie) return false;
      if (q['type'] != null && p['type_categorie'] != q['type']) return false;
      if (boutique != null && p['id_boutique'] != boutique) return false;
      if (min != null && (p['prix_produit'] as int) < min) return false;
      if (max != null && (p['prix_produit'] as int) > max) return false;
      if (q['en_stock'] == 'true' && (p['quantite_stock'] as int) <= 0) return false;
      return true;
    }).toList();
    int Function(J, J) tri = switch (q['tri']) {
      'prix_asc' => (a, b) => (a['prix_produit'] as int).compareTo(b['prix_produit']),
      'prix_desc' => (a, b) => (b['prix_produit'] as int).compareTo(a['prix_produit']),
      'note' => (a, b) {
        final n = (b['note_moyenne'] as num).compareTo(a['note_moyenne']);
        return n != 0 ? n : (b['nb_avis'] as int).compareTo(a['nb_avis']);
      },
      'nom' => (a, b) => '${a['nom']}'.compareTo('${b['nom']}'),
      _ => (a, b) {
        final d = '${b['date_creation']}'.compareTo('${a['date_creation']}');
        return d != 0 ? d : (b['id_produit'] as int).compareTo(a['id_produit']);
      },
    };
    rows.sort(tri);
    final limit = (int.tryParse(q['limit'] ?? '') ?? 50).clamp(1, 100);
    final offset = (int.tryParse(q['offset'] ?? '') ?? 0).clamp(0, rows.length);
    return rows.skip(offset).take(limit).toList();
  }

  DemoReponse _avisProduit(J u, int id, J b) {
    final note = _note(b);
    if (_produit(id) == null) throw _notFound('Produit introuvable');
    final achete = _t('commandes').any(
      (c) =>
          c['id_user'] == u['id_user'] &&
          _S.payes.contains(c['statut_commande']) &&
          _t('commande_items').any((i) => i['id_commande'] == c['id_commande'] && i['id_produit'] == id),
    );
    if (!achete) throw _forbidden('Vous devez avoir acheté ce produit pour donner un avis');
    _enregistrerAvis(u['id_user'], 'id_produit', id, note, b['commentaire']);
    return (201, _un('avis', (a) => a['id_user'] == u['id_user'] && a['id_produit'] == id));
  }

  (J, J) _produitGerable(J u, String id, {String absent = 'Produit introuvable'}) {
    _exiger(u, [_P.produitsGerer, _P.produitsModerer]);
    final p = _produit(_int(id, 'id'));
    if (p == null) throw _notFound(absent);
    if (!_peut(u, _P.produitsModerer) && _boutique(p['id_boutique'])?['id_vendeur'] != u['id_user']) {
      throw _forbidden('Ce produit ne vous appartient pas');
    }
    return (u, p);
  }

  J _validerProduit(J d) {
    _requis(d, ['nom', 'id_categorie', 'prix_produit']);
    final statut = d['statut'] ?? 'publie';
    if (!['brouillon', 'publie', 'retire'].contains(statut)) throw _bad('Statut de produit invalide');
    final idCategorie = _int(d['id_categorie'], 'id_categorie');
    if (_categorie(idCategorie) == null) throw _bad('Catégorie inconnue');
    String? texte(dynamic v) => v == null || '$v'.isEmpty ? null : '$v';
    return {
      'nom': '${d['nom']}'.trim(),
      'description': texte(d['description']),
      'id_categorie': idCategorie,
      'prix_produit': _int(d['prix_produit'], 'prix_produit', min: 0),
      'quantite_stock': _int(d['quantite_stock'] ?? 0, 'quantite_stock', min: 0),
      'unite': texte(d['unite']),
      'image_produit': texte(d['image_produit']),
      'statut': statut,
    };
  }

  DemoReponse _creerProduit(J u, J b) {
    _exiger(u, [_P.produitsGerer, _P.produitsModerer]);
    final boutique = _un('boutiques', (x) => x['id_vendeur'] == u['id_user']);
    if (boutique == null && !_peut(u, _P.produitsModerer)) {
      throw _bad('Créez d’abord votre boutique pour publier des produits');
    }
    final d = _validerProduit(b);
    final idBoutique = boutique?['id_boutique'];
    if (_t(
      'produits',
    ).any((p) => '${p['nom']}'.toLowerCase() == '${d['nom']}'.toLowerCase() && p['id_boutique'] == idBoutique)) {
      throw _conflict('Produit existant');
    }
    final p = _insert('produits', 'id_produit', {
      ...d,
      'id_boutique': idBoutique,
      'date_creation': horodatage(),
      'date_modification': horodatage(),
    });
    return (201, _produitVue(p));
  }

  DemoReponse _creerBoutique(J u, J b) {
    _requis(b, ['nom']);
    if (_t('boutiques').any((x) => x['id_vendeur'] == u['id_user'])) throw _conflict('Vous avez déjà une boutique');
    if (!_creationBoutique && !_peut(u, _P.utilisateursGerer)) {
      throw _forbidden('La création de boutiques est actuellement désactivée par l’administrateur');
    }
    final bq = _insert('boutiques', 'id_boutique', {
      'id_vendeur': u['id_user'],
      'nom': '${b['nom']}'.trim(),
      'description': b['description'],
      'adresse': b['adresse'],
      'ville': b['ville'],
      'telephone': b['telephone'] ?? u['telephone'],
      'active': true,
      'date_creation': horodatage(),
    });
    if (!_roles(u['id_user']).contains('vendeur')) _t('user_roles').add({'id_user': u['id_user'], 'role': 'vendeur'});
    return (201, bq);
  }

  List<J> _ventes(int idVendeur) {
    final rows = <J>[];
    for (final c in _t('commandes')) {
      if ([_S.attente, _S.annulee].contains(c['statut_commande'])) continue;
      for (final i in _t('commande_items').where((i) => i['id_commande'] == c['id_commande'])) {
        if (_boutique(_produit(i['id_produit'])?['id_boutique'])?['id_vendeur'] != idVendeur) continue;
        rows.add({
          'id_commande': c['id_commande'],
          'date_commande': c['date_commande'],
          'statut_commande': c['statut_commande'],
          'ville': c['ville'],
          'id_produit': i['id_produit'],
          'nom_produit': i['nom_produit'],
          'quantite': i['quantite'],
          'prix_unitaire': i['prix_unitaire'],
          'montant': (i['quantite'] as int) * (i['prix_unitaire'] as int),
        });
      }
    }
    return rows..sort((a, b) => '${b['date_commande']}'.compareTo('${a['date_commande']}'));
  }

  // --- Commandes, paiements, livraisons --------------------------------------------------------------
  J _produitDisponible(int id) {
    final p = _produit(id);
    if (p == null || !_visible(p)) throw _notFound('Produit indisponible');
    return p;
  }

  DemoReponse _passerCommande(J u, J b) {
    _requis(b, ['adresse_livraison', 'ville', 'telephone_livraison']);
    final panier = _verifierPanier(u['id_user'], b['ville']);
    final c = _insert('commandes', 'id_commande', {
      'id_user': u['id_user'],
      'date_commande': horodatage(),
      'statut_commande': _S.attente,
      'sous_total': panier['sous_total'],
      'frais_livraison': panier['frais_livraison'],
      'total_commande': panier['total'],
      'adresse_livraison': '${b['adresse_livraison']}'.trim(),
      'ville': '${b['ville']}'.trim(),
      'telephone_livraison': '${b['telephone_livraison']}'.trim(),
      'id_livreur': null,
      'motif_echec': null,
      'date_livraison': null,
    });
    final id = c['id_commande'] as int;
    for (final i in (panier['items'] as List).cast<J>()) {
      _t('commande_items').add({
        'id_commande': id,
        'id_produit': i['id_produit'],
        'nom_produit': i['nom'],
        'prix_unitaire': i['prix_produit'],
        'quantite': i['quantite'],
      });
      final p = _produit(i['id_produit'])!;
      p['quantite_stock'] = (p['quantite_stock'] as int) - (i['quantite'] as int);
    }
    _t('panier_items').removeWhere((i) => i['id_user'] == u['id_user']);
    if (u['adresse'] == null || '${u['adresse']}'.isEmpty) u['adresse'] = c['adresse_livraison'];
    _suivreStatut(id, _S.attente, auteur: u['id_user'], commentaire: 'Commande enregistrée');
    return (201, _detailCommande(id));
  }

  DemoReponse _payer(J u, J b) {
    _requis(b, ['id_commande', 'mode_paie', 'telephone']);
    final idc = _int(b['id_commande'], 'id_commande');
    if (!['MTN_MOMO', 'ORANGE_MONEY'].contains(b['mode_paie'])) throw _bad('Mode de paiement invalide');
    final tel = '${b['telephone']}'.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\+?\d{8,15}$').hasMatch(tel)) throw _bad('Numéro de téléphone invalide');
    final c = _commande(idc);
    if (c == null || c['id_user'] != u['id_user'] || c['statut_commande'] != _S.attente) {
      throw _conflict('Commande introuvable ou déjà payée');
    }
    if (_paiementEnAttente(idc)) throw _conflict('Un paiement est déjà en cours pour cette commande');
    final reference = 'TX-${DateTime.now().millisecondsSinceEpoch}-DEMO';
    final p = _insert('payements', 'id_payement', {
      'id_commande': idc,
      'montant': c['total_commande'],
      'date_paie': horodatage(),
      'statut_paie': 'en_attente',
      'mode_paie': b['mode_paie'],
      'telephone': tel,
      'reference_transaction': reference,
      'message': 'Confirmez le paiement sur votre téléphone',
    });
    // Comme l'opérateur simulé du serveur : refusé pour un numéro finissant par 0000.
    Timer(const Duration(seconds: 3), () => _resultatPaiement(reference, !tel.endsWith('0000')));
    return (202, p);
  }

  DemoReponse _livraisons(J u) {
    _exiger(u, [_P.livraisonsEffectuer]);
    J vue(J c) {
      final client = _user(c['id_user']);
      return {...c, 'client_prenom': client?['prenom'], 'client_nom': client?['nom']};
    }

    final disponibles =
        _t(
            'commandes',
          ).where((c) => _S.aLivrer.contains(c['statut_commande']) && c['id_livreur'] == null).map(vue).toList()
          ..sort((a, b) => '${a['date_commande']}'.compareTo('${b['date_commande']}'));
    int rang(J c) => c['statut_commande'] == _S.livraison ? 0 : (_S.aLivrer.contains(c['statut_commande']) ? 1 : 2);
    final miennes = _t('commandes').where((c) => c['id_livreur'] == u['id_user']).map(vue).toList()
      ..sort((a, b) {
        final r = rang(a).compareTo(rang(b));
        return r != 0 ? r : '${b['date_commande']}'.compareTo('${a['date_commande']}');
      });
    return (200, {'disponibles': disponibles, 'mes_livraisons': miennes});
  }

  (J, J) _maLivraison(J u, String id, {J? motifRequis}) {
    _exiger(u, [_P.livraisonsEffectuer]);
    final idc = _int(id, 'id');
    if (motifRequis != null) _requis(motifRequis, ['motif']);
    final c = _commande(idc);
    if (c == null || c['id_livreur'] != u['id_user'] || c['statut_commande'] != _S.livraison) {
      throw _conflict('Statut incorrect : la commande n’est pas en livraison par vous');
    }
    return (u, c);
  }

  // --- Messagerie ------------------------------------------------------------------------------------------
  List<J> _conversations(int moi) {
    final derniers = <int, J>{};
    for (final x in _t('messagerie')) {
      if (x['id_expediteur'] != moi && x['id_destinataire'] != moi) continue;
      final autre = x['id_expediteur'] == moi ? x['id_destinataire'] : x['id_expediteur'];
      derniers[autre] = x;
    }
    final rows = [
      for (final MapEntry(key: autre, value: dernier) in derniers.entries)
        if (_user(autre) case final u?)
          {
            'id_user': autre,
            'nom': u['nom'],
            'prenom': u['prenom'],
            'telephone': u['telephone'],
            'profil': u['profil'],
            'dernier_message': dernier['contenu'],
            'date_dernier_message': dernier['date_envoie'],
            'non_lus': _t('messagerie')
                .where((x) => x['id_expediteur'] == autre && x['id_destinataire'] == moi && x['date_lecture'] == null)
                .length,
            '_ordre': dernier['id_messagerie'],
          },
    ]..sort((a, b) => (b['_ordre'] as int).compareTo(a['_ordre']));
    return [for (final r in rows) Map.of(r)..remove('_ordre')];
  }

  DemoReponse _filMessages(int moi, int autre, int apres) {
    final u = _user(autre);
    if (u == null) throw _notFound('Utilisateur introuvable');
    for (final x in _t('messagerie')) {
      if (x['id_expediteur'] == autre && x['id_destinataire'] == moi && x['date_lecture'] == null) {
        x['date_lecture'] = horodatage();
      }
    }
    final messages = _t('messagerie')
        .where(
          (x) =>
              ((x['id_expediteur'] == moi && x['id_destinataire'] == autre) ||
                  (x['id_expediteur'] == autre && x['id_destinataire'] == moi)) &&
              (x['id_messagerie'] as int) > apres,
        )
        .toList();
    onChange?.call();
    return (
      200,
      {
        'interlocuteur': {
          'id_user': u['id_user'],
          'nom': u['nom'],
          'prenom': u['prenom'],
          'telephone': u['telephone'],
          'profil': u['profil'],
        },
        'messages': messages,
      },
    );
  }

  DemoReponse _envoyerMessage(J u, J b) {
    _requis(b, ['id_destinataire', 'contenu']);
    final dest = _int(b['id_destinataire'], 'id_destinataire');
    if (dest == u['id_user']) throw _bad('Vous ne pouvez pas vous écrire à vous-même');
    final destinataire = _user(dest);
    if (destinataire == null || destinataire['actif'] != true) throw _notFound('Destinataire introuvable');
    var contenu = '${b['contenu']}'.trim();
    if (contenu.length > 2000) contenu = contenu.substring(0, 2000);
    final x = _envoyer(u['id_user'], dest, contenu, b['sujet']);
    _notifier(dest, 'message', 'Message de ${u['prenom']}', contenu.length > 80 ? contenu.substring(0, 80) : contenu);
    // Les interlocuteurs de démonstration répondent automatiquement.
    if (destinataire['fictif'] == true) {
      Timer(const Duration(seconds: 2), () {
        _envoyer(
          dest,
          u['id_user'],
          'Bonjour ${u['prenom']}, merci pour votre message ! Ceci est une réponse automatique du mode démo.',
          null,
        );
        _notifier(u['id_user'], 'message', 'Message de ${destinataire['prenom']}', 'Merci pour votre message !');
        onChange?.call();
      });
    }
    return (201, x);
  }

  J _envoyer(int de, int vers, String contenu, dynamic sujet) => _insert('messagerie', 'id_messagerie', {
    'id_expediteur': de,
    'id_destinataire': vers,
    'sujet': sujet,
    'contenu': contenu,
    'date_envoie': horodatage(),
    'date_lecture': null,
  });

  // --- Administration -----------------------------------------------------------------------------------------
  DemoReponse _admin(String m, List<String> s, Map<String, String> q, J b, J u) {
    final id = u['id_user'] as int;
    void exiger(List<String> p) => _exiger(u, p);
    switch ((m, s)) {
      case ('GET', ['utilisateurs']):
        exiger([_P.utilisateursGerer]);
        final recherche = (q['q'] ?? '').trim();
        final rows =
            [
                  for (final x in _t('users'))
                    if ([x['nom'], x['prenom'], x['telephone'], x['email']].any((v) => _like(v, recherche)))
                      {
                        for (final c in [
                          'id_user',
                          'nom',
                          'prenom',
                          'email',
                          'telephone',
                          'adresse',
                          'actif',
                          'derniere_connexion',
                          'date_creation',
                        ])
                          c: x[c],
                        'roles': _roles(x['id_user']),
                      },
                ]
                .where((x) => q['role'] == null || q['role']!.isEmpty || (x['roles'] as List).contains(q['role']))
                .toList()
              ..sort((a, b) {
                final d = '${b['date_creation']}'.compareTo('${a['date_creation']}');
                return d != 0 ? d : (b['id_user'] as int).compareTo(a['id_user']);
              });
        return (200, rows);
      case ('GET', ['parametres']):
        exiger([_P.utilisateursGerer]);
        return (200, {'creation_boutique': _creationBoutique});
      case ('PUT', ['parametres']):
        exiger([_P.utilisateursGerer]);
        final inconnus = b.keys.where((k) => k != 'creation_boutique').toList();
        if (inconnus.isNotEmpty) throw _bad('Paramètre inconnu : ${inconnus.join(', ')}');
        for (final MapEntry(:key, :value) in b.entries) {
          if (value is! bool) throw _bad('Valeur invalide pour $key (true ou false attendu)');
          (db['parametres'] as J)[key] = value;
        }
        _journaliser(id, 'parametres.modifier', b);
        return (200, {'creation_boutique': _creationBoutique});
      case ('GET', ['livreurs']):
        exiger([_P.commandesGerer]);
        final rows = [
          for (final x in _t('users'))
            if (x['actif'] == true && _peut(x, _P.livraisonsEffectuer))
              {
                for (final c in ['id_user', 'nom', 'prenom', 'telephone', 'actif']) c: x[c],
              },
        ]..sort((a, b) => '${a['prenom']} ${a['nom']}'.compareTo('${b['prenom']} ${b['nom']}'));
        return (200, rows);
      case ('PATCH', ['utilisateurs', final cible, 'actif']):
        exiger([_P.utilisateursGerer]);
        final idc = _int(cible, 'id');
        if (idc == id) throw _bad('Vous ne pouvez pas désactiver votre propre compte');
        final x = _user(idc);
        if (x == null) throw _notFound('Utilisateur introuvable');
        final actif = b['actif'] == true;
        x['actif'] = actif;
        if (!actif) x['token_version'] = (x['token_version'] as int) + 1;
        _journaliser(id, actif ? 'utilisateur.activer' : 'utilisateur.desactiver', {'id_user': idc});
        return (200, {'id_user': idc, 'actif': actif});
      case ('PUT', ['utilisateurs', final cible, 'roles']):
        exiger([_P.rolesGerer]);
        final idc = _int(cible, 'id');
        final roles = b['roles'];
        if (roles is! List || roles.isEmpty) throw _bad('Au moins un rôle est requis');
        if (_user(idc) == null) throw _notFound('Utilisateur introuvable');
        for (final r in roles) {
          if (!_t('roles').any((x) => x['nom'] == r)) throw _bad('Rôle inconnu : $r');
        }
        if (idc == id && !roles.contains('admin') && _roles(id).contains('admin')) {
          throw _bad('Vous ne pouvez pas retirer votre propre rôle administrateur');
        }
        _t('user_roles').removeWhere((r) => r['id_user'] == idc);
        for (final r in roles.toSet()) {
          _t('user_roles').add({'id_user': idc, 'role': '$r'});
        }
        _journaliser(id, 'utilisateur.roles', {'id_user': idc, 'roles': roles});
        return (200, {'id_user': idc, 'roles': _roles(idc), 'permissions': _permissions(idc)});
      case ('GET', ['permissions']):
        exiger([_P.rolesGerer]);
        return (200, [...(_t('permissions'))]..sort((a, b) => '${a['nom']}'.compareTo('${b['nom']}')));
      case ('GET', ['roles']):
        exiger([_P.rolesGerer, _P.utilisateursGerer]);
        return (200, [for (final r in _t('roles')) _roleVue(r)]);
      case ('POST', ['roles']):
        exiger([_P.rolesGerer]);
        _requis(b, ['nom']);
        final nom = '${b['nom']}'.trim().toLowerCase();
        if (_t('roles').any((r) => r['nom'] == nom)) throw _conflict('Rôle existant');
        final r = _insert('roles', 'id_role', {'nom': nom, 'description': b['description']});
        _journaliser(id, 'role.creer', {'nom': nom});
        return (201, _roleVue(r));
      case ('PUT', ['roles', final idr, 'permissions']):
        exiger([_P.rolesGerer]);
        final r = _un('roles', (r) => r['id_role'] == _int(idr, 'id'));
        if (r == null) throw _notFound('Rôle introuvable');
        if (r['nom'] == 'admin') throw _forbidden('Les permissions du rôle admin ne sont pas modifiables');
        final perms = b['permissions'];
        if (perms is! List) throw _bad('permissions doit être une liste');
        for (final p in perms) {
          if (!_t('permissions').any((x) => x['nom'] == p)) throw _bad('Permission inconnue : $p');
        }
        _t('role_permissions').removeWhere((rp) => rp['role'] == r['nom']);
        for (final p in perms.toSet()) {
          _t('role_permissions').add({'role': r['nom'], 'permission': '$p'});
        }
        _journaliser(id, 'role.permissions', {'role': r['nom'], 'permissions': perms});
        return (200, _roleVue(r));
      case ('GET', ['commandes']):
        exiger([_P.commandesGerer]);
        return (200, _commandesAdmin(q));
      case ('PATCH', ['commandes', final idc, 'statut']):
        exiger([_P.commandesGerer]);
        return _changerStatut(u, _int(idc, 'id'), b);
      case ('PATCH', ['commandes', final idc, 'livreur']):
        exiger([_P.commandesGerer]);
        return _affecterLivreur(u, _int(idc, 'id'), b);
      case ('GET', ['paiements']):
        exiger([_P.paiementsVoir]);
        final rows = [
          for (final p in _t('payements').reversed)
            if (q['statut'] == null || q['statut']!.isEmpty || p['statut_paie'] == q['statut'])
              {
                ..._paiementVue(p),
                'client_nom': _user(_commande(p['id_commande'])?['id_user'])?['nom'],
                'client_prenom': _user(_commande(p['id_commande'])?['id_user'])?['prenom'],
              },
        ];
        return (200, rows.take(200).toList());
      case ('GET', ['boutiques']):
        exiger([_P.utilisateursGerer]);
        final rows = [
          for (final bq in _t('boutiques'))
            {
              ...bq,
              'vendeur_nom': _user(bq['id_vendeur'])?['nom'],
              'vendeur_prenom': _user(bq['id_vendeur'])?['prenom'],
              'nb_produits': _t('produits').where((p) => p['id_boutique'] == bq['id_boutique']).length,
            },
        ]..sort((a, b) => '${b['date_creation']}'.compareTo('${a['date_creation']}'));
        return (200, rows);
      case ('PATCH', ['boutiques', final idb, 'active']):
        exiger([_P.utilisateursGerer]);
        final bq = _boutique(_int(idb, 'id'));
        if (bq == null) throw _notFound('Boutique introuvable');
        bq['active'] = b['active'] == true;
        _journaliser(id, bq['active'] ? 'boutique.activer' : 'boutique.desactiver', {'id_boutique': bq['id_boutique']});
        return (200, {'id_boutique': bq['id_boutique'], 'active': bq['active']});
      case ('GET', ['regles-livraison']):
        exiger([_P.livraisonRegles]);
        final rows = [..._t('regles_livraison')]
          ..sort((a, b) {
            if (a['ville'] == '*') return -1;
            if (b['ville'] == '*') return 1;
            return '${a['ville']}'.compareTo('${b['ville']}');
          });
        return (200, rows);
      case ('POST', ['regles-livraison']):
        exiger([_P.livraisonRegles]);
        _requis(b, ['ville', 'frais']);
        final frais = _int(b['frais'], 'frais', min: 0);
        final s = b['seuil_gratuite'];
        final seuil = s == null || s == '' ? null : _int(s, 'seuil_gratuite', min: 0);
        final ville = '${b['ville']}'.trim();
        final existante = _un('regles_livraison', (r) => '${r['ville']}'.toLowerCase() == ville.toLowerCase());
        final r = existante != null
            ? (existante..addAll({'frais': frais, 'seuil_gratuite': seuil}))
            : _insert('regles_livraison', 'id_regle', {'ville': ville, 'frais': frais, 'seuil_gratuite': seuil});
        _journaliser(id, 'livraison.regle', {'ville': ville, 'frais': frais, 'seuil_gratuite': seuil});
        return (201, r);
      case ('DELETE', ['regles-livraison', final idr]):
        exiger([_P.livraisonRegles]);
        final r = _un('regles_livraison', (r) => r['id_regle'] == _int(idr, 'id'));
        if (r == null) throw _notFound('Règle introuvable');
        if (r['ville'] == '*') throw _bad('La règle par défaut ne peut pas être supprimée');
        _t('regles_livraison').remove(r);
        _journaliser(id, 'livraison.regle.supprimer', {'ville': r['ville']});
        return (204, null);
      case ('GET', ['statistiques']):
        exiger([_P.statistiquesVoir]);
        return (200, _statistiques());
      case ('GET', ['journal']):
        exiger([_P.journalVoir]);
        final limite = _int(q['limite'] ?? 100, 'limite', min: 1).clamp(1, 500);
        final avant = q['avant'] == null ? null : _int(q['avant'], 'avant');
        final idUser = q['id_user'] == null ? null : _int(q['id_user'], 'id_user');
        final rows = [
          for (final j in _t('journal_activite').reversed)
            if ((q['action'] == null || '${j['action']}'.startsWith(q['action']!.trim())) &&
                (idUser == null || j['id_user'] == idUser) &&
                (avant == null || (j['id_journal'] as int) < avant))
              {
                ...j,
                'prenom': _user(j['id_user'])?['prenom'],
                'nom': _user(j['id_user'])?['nom'],
                'telephone': _user(j['id_user'])?['telephone'],
              },
        ];
        return (200, rows.take(limite).toList());
    }
    throw DemoErreur(404, 'Route introuvable');
  }

  J _roleVue(J r) => {...r, 'permissions': _permissionsRole(r['nom'])};

  List<J> _commandesAdmin(Map<String, String> q) {
    final statuts = (q['statut'] ?? '').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final brut = (q['q'] ?? '').trim();
    final recherche = brut.replaceFirst(RegExp('^#'), '');
    final numero = brut.startsWith('#') ? _int(recherche, 'q') : null;
    for (final cle in ['du', 'au']) {
      final v = q[cle];
      if (v != null && (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) || DateTime.tryParse(v) == null)) {
        throw _bad('Date « $cle » invalide (AAAA-MM-JJ)');
      }
    }
    final idLivreur = q['id_livreur'] == null ? null : _int(q['id_livreur'], 'id_livreur');
    final rows = <J>[];
    for (final c in _t('commandes')) {
      final client = _user(c['id_user']);
      if (statuts.isNotEmpty && !statuts.contains(c['statut_commande'])) continue;
      if (numero != null && c['id_commande'] != numero) continue;
      if (numero == null && recherche.isNotEmpty) {
        final ok =
            '${c['id_commande']}' == recherche ||
            _like('${client?['prenom']} ${client?['nom']}', recherche) ||
            _like(client?['telephone'], recherche) ||
            _like(c['telephone_livraison'], recherche);
        if (!ok) continue;
      }
      final jour = '${c['date_commande']}'.substring(0, 10);
      if (q['du'] != null && jour.compareTo(q['du']!) < 0) continue;
      if (q['au'] != null && jour.compareTo(q['au']!) > 0) continue;
      if (q['ville'] != null && '${c['ville']}'.toLowerCase() != q['ville']!.trim().toLowerCase()) continue;
      if (idLivreur != null && c['id_livreur'] != idLivreur) continue;
      final l = _user(c['id_livreur']);
      rows.add({
        ...c,
        'client_nom': client?['nom'],
        'client_prenom': client?['prenom'],
        'livreur_prenom': l?['prenom'],
        'livreur_nom': l?['nom'],
        'libelle_statut': _libelle(c['statut_commande']),
      });
    }
    rows.sort(_parDateDesc);
    return rows.take(200).toList();
  }

  bool _estLivreurActif(dynamic idUser) {
    final x = _user(idUser);
    return x != null && x['actif'] == true && _peut(x, _P.livraisonsEffectuer);
  }

  DemoReponse _changerStatut(J u, int id, J b) {
    final c = _commande(id);
    if (c == null) throw _notFound('Commande introuvable');
    final statut = b['statut'];
    final avant = c['statut_commande'] as String;
    if (!(_S.transitions[avant] ?? []).contains(statut)) throw _conflict('Transition interdite : $avant → $statut');
    if ([_S.annulee, _S.enCours].contains(statut) && avant == _S.attente && _paiementEnAttente(id)) {
      throw _conflict('Un paiement est en cours de traitement');
    }
    var idLivreur = c['id_livreur'];
    if (statut == _S.livraison) {
      idLivreur = b['id_livreur'] != null ? _int(b['id_livreur'], 'id_livreur') : c['id_livreur'];
      if (idLivreur == null) throw _bad('Un livreur doit être assigné');
      if (!_estLivreurActif(idLivreur)) throw _bad('Cet utilisateur n’est pas un livreur actif');
    }
    if ([_S.enCours, _S.preparation].contains(statut) && [_S.livraison, _S.echec].contains(avant)) idLivreur = null;
    final ancienLivreur = c['id_livreur'];
    c['statut_commande'] = statut;
    c['id_livreur'] = idLivreur;
    if (statut == _S.livree) c['date_livraison'] = horodatage();
    if (statut == _S.echec) c['motif_echec'] = b['motif'] ?? 'Signalé par l’administrateur';
    if (statut == _S.annulee) _restituerStock(id);
    _suivreStatut(
      id,
      statut,
      auteur: u['id_user'],
      commentaire: b['commentaire'] ?? (statut == _S.echec ? b['motif'] : null) ?? 'Mis à jour par l’administrateur',
    );
    if (statut == _S.livraison && idLivreur != ancienLivreur) {
      _notifier(idLivreur, 'livraison', 'Livraison assignée', 'La commande #$id vous a été assignée.');
    }
    _journaliser(u['id_user'], 'commande.statut', {'id_commande': id, 'de': avant, 'vers': statut});
    return (200, _detailCommande(id));
  }

  DemoReponse _affecterLivreur(J u, int id, J b) {
    final c = _commande(id);
    if (c == null) throw _notFound('Commande introuvable');
    final avant = c['statut_commande'];
    if (![_S.enCours, _S.preparation, _S.echec].contains(avant)) {
      throw _conflict(
        'Le livreur ne peut être changé que sur une commande confirmée, en préparation ou en échec de livraison',
      );
    }
    final idLivreur = b['id_livreur'] == null ? null : _int(b['id_livreur'], 'id_livreur');
    if (idLivreur != null && !_estLivreurActif(idLivreur)) throw _bad('Cet utilisateur n’est pas un livreur actif');
    final statut = avant == _S.echec ? _S.preparation : avant;
    final ancien = c['id_livreur'];
    c['id_livreur'] = idLivreur;
    c['statut_commande'] = statut;
    if (statut != avant) {
      _suivreStatut(id, statut, auteur: u['id_user'], commentaire: 'Nouvelle tentative de livraison');
    }
    if (idLivreur != null && idLivreur != ancien) {
      _notifier(idLivreur, 'livraison', 'Livraison assignée', 'La commande #$id (${c['ville']}) vous a été assignée.');
    }
    if (ancien != null && ancien != idLivreur) {
      _notifier(ancien, 'livraison', 'Livraison retirée', 'La commande #$id ne vous est plus assignée.');
    }
    final l = _user(idLivreur);
    _insert('commande_historique', 'id_historique', {
      'id_commande': id,
      'statut': statut,
      'commentaire': l != null ? 'Livreur affecté : ${l['prenom']} ${l['nom']}' : 'Livreur retiré',
      'id_auteur': u['id_user'],
      'date': horodatage(),
    });
    _journaliser(u['id_user'], 'commande.livreur', {'id_commande': id, 'id_livreur': idLivreur});
    return (200, _detailCommande(id));
  }

  J _statistiques() {
    final commandes = _t('commandes');
    final payees = commandes.where((c) => _S.payes.contains(c['statut_commande'])).toList();
    final maintenant = DateTime.now();
    final aujourdhui = _jourLocal(maintenant);
    bool duJour(J c) => _jourLocal(_local(c['date_commande'])) == aujourdhui;
    bool duMois(J c) {
      final d = _local(c['date_commande']);
      return d.year == maintenant.year && d.month == maintenant.month;
    }

    int somme(Iterable<J> l) => l.fold(0, (s, c) => s + (c['total_commande'] as int));
    int nb(String statut) => commandes.where((c) => c['statut_commande'] == statut).length;

    final parStatut = <String, int>{};
    for (final c in commandes) {
      parStatut.update(c['statut_commande'], (n) => n + 1, ifAbsent: () => 1);
    }
    final depuis = horodatage(maintenant.subtract(const Duration(days: 30))).substring(0, 10);
    final parJour = <String, J>{};
    for (final c in payees) {
      final jour = '${c['date_commande']}'.substring(0, 10);
      if (jour.compareTo(depuis) < 0) continue;
      final v = parJour.putIfAbsent(jour, () => {'jour': jour, 'commandes': 0, 'montant': 0});
      v['commandes'] = (v['commandes'] as int) + 1;
      v['montant'] = (v['montant'] as int) + (c['total_commande'] as int);
    }
    final top = <int, J>{};
    final idsPayees = {for (final c in payees) c['id_commande']};
    for (final i in _t('commande_items').where((i) => idsPayees.contains(i['id_commande']))) {
      final v = top.putIfAbsent(
        i['id_produit'],
        () => {'id_produit': i['id_produit'], 'nom': i['nom_produit'], 'quantite': 0, 'montant': 0},
      );
      v['quantite'] = (v['quantite'] as int) + (i['quantite'] as int);
      v['montant'] = (v['montant'] as int) + (i['quantite'] as int) * (i['prix_unitaire'] as int);
    }
    final publies = _t('produits').where((p) => p['statut'] == 'publie').toList();
    return {
      'commandes_jour': commandes.where(duJour).length,
      'chiffre_affaires_jour': somme(payees.where(duJour)),
      'chiffre_affaires_mois': somme(payees.where(duMois)),
      'livraisons_en_cours': nb(_S.livraison),
      'a_preparer': nb(_S.enCours) + nb(_S.preparation),
      'en_attente_paiement': nb(_S.attente),
      'echecs_livraison': nb(_S.echec),
      'chiffre_affaires': somme(payees),
      'nb_commandes': commandes.length,
      'nb_clients': _t('users').length,
      'nb_produits': publies.length,
      'panier_moyen': payees.isEmpty ? 0 : (somme(payees) / payees.length).round(),
      'commandes_par_statut': [
        for (final MapEntry(:key, :value) in parStatut.entries) {'statut': key, 'nombre': value},
      ],
      'ventes_par_jour': parJour.values.toList()..sort((a, b) => '${a['jour']}'.compareTo('${b['jour']}')),
      'top_produits': (top.values.toList()..sort((a, b) => (b['quantite'] as int).compareTo(a['quantite'])))
          .take(5)
          .toList(),
      'stock_bas': [
        for (final p
            in publies.where((p) => (p['quantite_stock'] as int) <= 5).toList()
              ..sort((a, b) => (a['quantite_stock'] as int).compareTo(b['quantite_stock'])))
          {'id_produit': p['id_produit'], 'nom': p['nom'], 'quantite_stock': p['quantite_stock']},
      ].take(10).toList(),
    };
  }
}

/// Initiale du nom (avis publics).
String _initiale(dynamic nom) => '${nom ?? ''}'.isEmpty ? '' : '$nom'.substring(0, 1);

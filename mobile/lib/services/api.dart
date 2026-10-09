import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config.dart';
import '../models/models.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  final dynamic details;
  ApiException(this.status, this.message, [this.details]);

  @override
  String toString() => message;
}

/// Client HTTP de l'API REST (backend/src/app.js).
class Api {
  Api({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  String? token;

  /// Appelé quand le serveur répond 401 (session expirée).
  void Function()? onUnauthorized;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final q = query == null
        ? null
        : {
            for (final e in query.entries)
              if (e.value != null && '${e.value}'.isNotEmpty) e.key: '${e.value}',
          };
    return Uri.parse('${AppConfig.apiUrl}$path').replace(queryParameters: q == null || q.isEmpty ? null : q);
  }

  Future<dynamic> _send(String method, String path, {Object? body, Map<String, dynamic>? query}) async {
    final req = http.Request(method, _uri(path, query))..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    return _decode(await _executer(req));
  }

  /// Envoie la requête en traduisant les erreurs réseau en [ApiException].
  Future<http.Response> _executer(http.BaseRequest req, {Duration delai = const Duration(seconds: 20)}) async {
    try {
      return await http.Response.fromStream(await _http.send(req).timeout(delai));
    } on TimeoutException {
      throw ApiException(0, 'Le serveur met trop de temps à répondre.');
    } on SocketException {
      throw ApiException(0, 'Impossible de joindre le serveur. Vérifiez votre connexion internet.');
    } on HttpException {
      throw ApiException(0, 'Erreur réseau.');
    } on http.ClientException {
      // package:http enveloppe les SocketException dans une ClientException.
      throw ApiException(0, 'Impossible de joindre le serveur. Vérifiez votre connexion internet.');
    }
  }

  dynamic _decode(http.Response res) {
    dynamic data;
    try {
      data = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      // Réponse non JSON (proxy, page d'erreur HTML...).
      data = null;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        throw ApiException(res.statusCode, 'Réponse invalide du serveur.');
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    if (res.statusCode == 401 && token != null) onUnauthorized?.call();
    final msg = data is Map && data['erreur'] != null ? '${data['erreur']}' : 'Erreur ${res.statusCode}';
    throw ApiException(res.statusCode, msg, data is Map ? data['details'] : null);
  }

  Future<dynamic> get(String path, [Map<String, dynamic>? query]) => _send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body ?? {});
  Future<dynamic> put(String path, [Object? body]) => _send('PUT', path, body: body ?? {});
  Future<dynamic> patch(String path, [Object? body]) => _send('PATCH', path, body: body ?? {});
  Future<dynamic> delete(String path) => _send('DELETE', path);

  List<T> _list<T>(dynamic data, T Function(Map<String, dynamic>) f) =>
      (data as List).map((e) => f(e as Map<String, dynamic>)).toList();

  // --- Authentification & compte ---------------------------------------------
  Future<(String, User)> connexion(String identifiant, String motDePasse) async {
    final d = await post('/auth/connexion', {'identifiant': identifiant, 'mot_de_passe': motDePasse});
    return (d['token'] as String, User.fromJson(d['utilisateur']));
  }

  Future<(String, User)> inscription(Map<String, dynamic> data) async {
    final d = await post('/auth/inscription', data);
    return (d['token'] as String, User.fromJson(d['utilisateur']));
  }

  /// Connexion sans mot de passe à un compte de démonstration (client, vendeur, livreur, admin).
  Future<(String, User)> connexionDemo(String profil) async {
    final d = await post('/auth/demo', {'profil': profil});
    return (d['token'] as String, User.fromJson(d['utilisateur']));
  }

  Future<void> deconnexion() => post('/auth/deconnexion');
  Future<User> moi() async => User.fromJson(await get('/compte'));
  Future<User> modifierCompte(Map<String, dynamic> data) async => User.fromJson(await put('/compte', data));
  Future<String> changerMotDePasse(String ancien, String nouveau) async =>
      (await put('/compte/mot-de-passe', {'ancien': ancien, 'nouveau': nouveau}))['token'];
  Future<void> newsletterCompte(bool abonne) => put('/compte/newsletter', {'abonne': abonne});
  Future<void> newsletter(String email) => post('/newsletter', {'email': email});

  Future<String> uploadImage(File file) async {
    final req = http.MultipartRequest('POST', _uri('/uploads'))
      ..headers.addAll({if (token != null) 'Authorization': 'Bearer $token'})
      ..files.add(await http.MultipartFile.fromPath('image', file.path, contentType: _mime(file.path)));
    // Délai plus long : l'envoi de l'image (jusqu'à 5 Mo) est compris dans l'attente.
    return _decode(await _executer(req, delai: const Duration(seconds: 90)))['url'];
  }

  static MediaType? _mime(String path) {
    final ext = path.split('.').last.toLowerCase();
    final sub = {'jpg': 'jpeg', 'jpeg': 'jpeg', 'png': 'png', 'webp': 'webp', 'gif': 'gif'}[ext];
    return sub == null ? null : MediaType('image', sub);
  }

  // --- Catalogue ------------------------------------------------------------------
  Future<List<Categorie>> categories({String? q, String? type}) async =>
      _list(await get('/categories', {'q': q, 'type': type}), Categorie.fromJson);
  Future<Categorie> creerCategorie(Map<String, dynamic> d) async => Categorie.fromJson(await post('/categories', d));
  Future<Categorie> modifierCategorie(int id, Map<String, dynamic> d) async =>
      Categorie.fromJson(await put('/categories/$id', d));
  Future<void> supprimerCategorie(int id) => delete('/categories/$id');

  Future<List<Produit>> produits({
    String? q,
    int? categorie,
    String? type,
    int? boutique,
    int? prixMin,
    int? prixMax,
    bool enStock = false,
    String? tri,
  }) async => _list(
    await get('/produits', {
      'q': q,
      'categorie': categorie,
      'type': type,
      'boutique': boutique,
      'prix_min': prixMin,
      'prix_max': prixMax,
      'en_stock': enStock ? 'true' : null,
      'tri': tri,
    }),
    Produit.fromJson,
  );
  Future<Produit> produit(int id) async => Produit.fromJson(await get('/produits/$id'));
  Future<List<Avis>> avisProduit(int id) async => _list(await get('/produits/$id/avis'), Avis.fromJson);
  Future<void> donnerAvisProduit(int id, int note, String? commentaire) =>
      post('/produits/$id/avis', {'note_avis': note, 'commentaire': commentaire});

  // Gestion des produits (vendeur / administrateur).
  Future<List<Produit>> produitsGestion({bool tous = true}) async =>
      _list(await get('/produits/gestion', {'tous': tous ? null : 'false'}), Produit.fromJson);
  Future<Produit> creerProduit(Map<String, dynamic> d) async => Produit.fromJson(await post('/produits', d));
  Future<Produit> modifierProduit(int id, Map<String, dynamic> d) async =>
      Produit.fromJson(await put('/produits/$id', d));
  Future<Produit> majStock(int id, int stock) async =>
      Produit.fromJson(await patch('/produits/$id/stock', {'quantite_stock': stock}));
  Future<Produit> majStatutProduit(int id, String statut) async =>
      Produit.fromJson(await patch('/produits/$id/statut', {'statut': statut}));

  /// Supprime un produit ; renvoie true s'il a seulement été retiré (déjà commandé).
  Future<bool> supprimerProduit(int id) async {
    final d = await delete('/produits/$id');
    return d is Map && d['retire'] == true;
  }

  // Boutique.
  Future<Boutique?> maBoutique() async {
    try {
      return Boutique.fromJson(await get('/boutiques/moi'));
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<Boutique> creerBoutique(Map<String, dynamic> d) async => Boutique.fromJson(await post('/boutiques', d));
  Future<Boutique> modifierBoutique(Map<String, dynamic> d) async => Boutique.fromJson(await put('/boutiques/moi', d));
  Future<List<Vente>> mesVentes() async => _list(await get('/boutiques/moi/ventes'), Vente.fromJson);

  // --- Panier & commandes -----------------------------------------------------------
  Future<Panier> panier({String? ville}) async => Panier.fromJson(await get('/panier', {'ville': ville}));
  Future<Panier> ajouterAuPanier(int idProduit, int quantite) async =>
      Panier.fromJson(await post('/panier/items', {'id_produit': idProduit, 'quantite': quantite}));
  Future<Panier> modifierQuantite(int idProduit, int quantite) async =>
      Panier.fromJson(await patch('/panier/items/$idProduit', {'quantite': quantite}));
  Future<Panier> retirerDuPanier(int idProduit) async => Panier.fromJson(await delete('/panier/items/$idProduit'));
  Future<Panier> viderPanier() async => Panier.fromJson(await delete('/panier'));

  Future<Panier> recapitulatif(String? ville) async =>
      Panier.fromJson(await post('/commandes/recapitulatif', {'ville': ville}));
  Future<Commande> passerCommande({required String adresse, required String ville, required String telephone}) async =>
      Commande.fromJson(
        await post('/commandes', {'adresse_livraison': adresse, 'ville': ville, 'telephone_livraison': telephone}),
      );
  Future<List<Commande>> mesCommandes() async => _list(await get('/commandes'), Commande.fromJson);
  Future<Commande> commande(int id) async => Commande.fromJson(await get('/commandes/$id'));
  Future<Commande> annulerCommande(int id) async => Commande.fromJson(await post('/commandes/$id/annuler'));
  Future<Commande> noterCommande(int id, int note, String? commentaire) async =>
      Commande.fromJson(await post('/commandes/$id/avis', {'note_avis': note, 'commentaire': commentaire}));

  // --- Paiements ------------------------------------------------------------------------
  Future<Paiement> payer(int idCommande, String mode, String telephone) async => Paiement.fromJson(
    await post('/paiements', {'id_commande': idCommande, 'mode_paie': mode, 'telephone': telephone}),
  );
  Future<Paiement> paiement(int id) async => Paiement.fromJson(await get('/paiements/$id'));

  // --- Livraisons -------------------------------------------------------------------------
  Future<int> fraisLivraison(String ville, int sousTotal) async =>
      (await get('/livraisons/frais', {'ville': ville, 'sous_total': sousTotal}))['frais_livraison'];
  Future<Livraisons> livraisons() async => Livraisons.fromJson(await get('/livraisons'));
  Future<Commande> prendreLivraison(int id) async => Commande.fromJson(await post('/livraisons/$id/prendre'));
  Future<Commande> confirmerLivraison(int id) async => Commande.fromJson(await post('/livraisons/$id/confirmer'));
  Future<Commande> signalerEchec(int id, String motif) async =>
      Commande.fromJson(await post('/livraisons/$id/echec', {'motif': motif}));

  // --- Messagerie & notifications -------------------------------------------------------------
  Future<List<Conversation>> conversations() async =>
      _list(await get('/messages/conversations'), Conversation.fromJson);
  Future<int> messagesNonLus() async => (await get('/messages/non-lus'))['non_lus'];
  Future<Map<String, dynamic>> support() async => Map<String, dynamic>.from(await get('/messages/support'));
  Future<(Map<String, dynamic>, List<Message>)> filMessages(int idUser, {int apres = 0}) async {
    final d = await get('/messages/$idUser', {'apres': apres == 0 ? null : apres});
    return (Map<String, dynamic>.from(d['interlocuteur']), _list(d['messages'], Message.fromJson));
  }

  Future<Message> envoyerMessage(int idDestinataire, String contenu) async =>
      Message.fromJson(await post('/messages', {'id_destinataire': idDestinataire, 'contenu': contenu}));

  Future<(int, List<AppNotification>)> notifications() async {
    final d = await get('/notifications');
    return (d['non_lues'] as int, _list(d['items'], AppNotification.fromJson));
  }

  Future<void> notificationLue(int id) => post('/notifications/$id/lu');
  Future<void> toutesNotificationsLues() => post('/notifications/tout-lu');

  // --- Administration -----------------------------------------------------------------------
  Future<List<User>> utilisateurs({String? q, String? role}) async =>
      _list(await get('/admin/utilisateurs', {'q': q, 'role': role}), User.fromJson);
  Future<List<User>> livreurs() async => _list(await get('/admin/livreurs'), User.fromJson);
  Future<void> activerUtilisateur(int id, bool actif) => patch('/admin/utilisateurs/$id/actif', {'actif': actif});
  Future<void> attribuerRoles(int id, List<String> roles) => put('/admin/utilisateurs/$id/roles', {'roles': roles});
  Future<List<Role>> roles() async => _list(await get('/admin/roles'), Role.fromJson);
  Future<Role> creerRole(String nom, String? description) async =>
      Role.fromJson(await post('/admin/roles', {'nom': nom, 'description': description}));
  Future<Role> permissionsRole(int id, List<String> permissions) async =>
      Role.fromJson(await put('/admin/roles/$id/permissions', {'permissions': permissions}));
  Future<List<PermissionInfo>> permissions() async => _list(await get('/admin/permissions'), PermissionInfo.fromJson);

  Future<List<Commande>> toutesCommandes({String? statut}) async =>
      _list(await get('/admin/commandes', {'statut': statut}), Commande.fromJson);
  Future<Commande> changerStatutCommande(int id, String statut, {int? idLivreur, String? motif}) async =>
      Commande.fromJson(
        await patch('/admin/commandes/$id/statut', {'statut': statut, 'id_livreur': ?idLivreur, 'motif': ?motif}),
      );
  Future<List<Paiement>> tousPaiements({String? statut}) async =>
      _list(await get('/admin/paiements', {'statut': statut}), Paiement.fromJson);
  Future<List<Boutique>> boutiques() async => _list(await get('/admin/boutiques'), Boutique.fromJson);
  Future<void> activerBoutique(int id, bool active) => patch('/admin/boutiques/$id/active', {'active': active});
  Future<List<RegleLivraison>> reglesLivraison() async =>
      _list(await get('/admin/regles-livraison'), RegleLivraison.fromJson);
  Future<void> enregistrerRegle(String ville, int frais, int? seuil) =>
      post('/admin/regles-livraison', {'ville': ville, 'frais': frais, 'seuil_gratuite': seuil});
  Future<void> supprimerRegle(int id) => delete('/admin/regles-livraison/$id');
  Future<Map<String, dynamic>> parametres() async => Map<String, dynamic>.from(await get('/parametres'));
  Future<Map<String, dynamic>> modifierParametres(Map<String, dynamic> d) async =>
      Map<String, dynamic>.from(await put('/admin/parametres', d));
  Future<Statistiques> statistiques() async => Statistiques.fromJson(await get('/admin/statistiques'));
}

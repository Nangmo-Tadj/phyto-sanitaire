import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/api.dart';

/// Session utilisateur (s'authentifier / se déconnecter).
class AuthState extends ChangeNotifier {
  AuthState(this.api) {
    api.onUnauthorized = _expire;
  }

  static const _tokenKey = 'auth_token';
  final Api api;
  User? user;
  bool initialise = false;

  bool get connecte => user != null;

  Future<void> restaurer() async {
    final prefs = await SharedPreferences.getInstance();
    api.token = prefs.getString(_tokenKey);
    if (api.token != null) {
      try {
        user = await api.moi();
      } catch (_) {
        api.token = null;
        await prefs.remove(_tokenKey);
      }
    }
    initialise = true;
    notifyListeners();
  }

  Future<void> _ouvrirSession(String token, User u) async {
    api.token = token;
    user = u;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    notifyListeners();
  }

  Future<void> connexion(String identifiant, String motDePasse) async {
    final (token, u) = await api.connexion(identifiant, motDePasse);
    await _ouvrirSession(token, u);
  }

  Future<void> connexionDemo(String profil) async {
    final (token, u) = await api.connexionDemo(profil);
    await _ouvrirSession(token, u);
  }

  Future<void> inscription(Map<String, dynamic> data) async {
    final (token, u) = await api.inscription(data);
    await _ouvrirSession(token, u);
  }

  Future<void> rafraichir() async {
    user = await api.moi();
    notifyListeners();
  }

  void majUtilisateur(User u) {
    user = u;
    notifyListeners();
  }

  Future<void> remplacerToken(String token) async {
    api.token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> deconnexion() async {
    try {
      await api.deconnexion();
    } catch (_) {
      // Déconnexion locale même si le serveur est injoignable.
    }
    await _fermer();
  }

  void _expire() => _fermer();

  Future<void> _fermer() async {
    api.token = null;
    user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    notifyListeners();
  }
}

/// Panier partagé entre les écrans (badge, ajout depuis la fiche produit...).
class CartState extends ChangeNotifier {
  CartState(this.api);

  final Api api;
  Panier panier = Panier();
  bool chargement = false;

  int get nombreArticles => panier.nombreArticles;

  Future<void> charger() async {
    chargement = true;
    notifyListeners();
    try {
      panier = await api.panier();
    } finally {
      chargement = false;
      notifyListeners();
    }
  }

  Future<void> _maj(Future<Panier> Function() action) async {
    panier = await action();
    notifyListeners();
  }

  Future<void> ajouter(int idProduit, [int quantite = 1]) => _maj(() => api.ajouterAuPanier(idProduit, quantite));
  Future<void> modifier(int idProduit, int quantite) => _maj(() => api.modifierQuantite(idProduit, quantite));
  Future<void> retirer(int idProduit) => _maj(() => api.retirerDuPanier(idProduit));
  Future<void> vider() => _maj(api.viderPanier);

  void reinitialiser() {
    panier = Panier();
    notifyListeners();
  }
}

/// Paramètres de la plateforme fixés par l'administrateur.
class ParametresState extends ChangeNotifier {
  ParametresState(this.api);

  final Api api;

  /// Les utilisateurs peuvent ouvrir une boutique (et s'inscrire comme vendeur).
  bool creationBoutique = true;

  void _appliquer(Map<String, dynamic> d) {
    creationBoutique = d['creation_boutique'] as bool? ?? true;
    notifyListeners();
  }

  Future<void> charger() async => _appliquer(await api.parametres());

  Future<void> autoriserCreationBoutique(bool autorise) async =>
      _appliquer(await api.modifierParametres({'creation_boutique': autorise}));
}

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
  static const _demoKey = 'mode_demo';
  final Api api;
  User? user;
  bool initialise = false;

  bool get connecte => user != null;

  /// Session du mode démo (hors ligne, données fictives).
  bool get demo => api.demo;

  Future<void> restaurer() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_demoKey) ?? false) await api.activerDemo();
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

  /// Renvoie false si un code de double authentification est demandé.
  Future<bool> connexion(String identifiant, String motDePasse, {String? code}) async {
    final r = await api.connexion(identifiant, motDePasse, code: code);
    if (r == null) return false;
    await _ouvrirSession(r.$1, r.$2);
    return true;
  }

  /// Ouvre le mode démo hors ligne avec le profil choisi (client, vendeur, livreur, admin).
  Future<void> connexionDemo(String profil) async {
    await api.activerDemo();
    try {
      final (token, u) = await api.connexionDemo(profil);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_demoKey, true);
      await _ouvrirSession(token, u);
    } catch (_) {
      if (user == null) api.quitterDemo();
      rethrow;
    }
  }

  /// Remet les données de démonstration à zéro en gardant le profil connecté.
  Future<void> reinitialiserDemo() async {
    await api.reinitialiserDemo();
    try {
      user = await api.moi();
      notifyListeners();
    } catch (_) {
      await _fermer();
    }
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

  Future<void> supprimerCompte(String motDePasse) async {
    await api.supprimerCompte(motDePasse);
    await _fermer();
  }

  void _expire() => _fermer();

  Future<void> _fermer() async {
    api.token = null;
    user = null;
    api.quitterDemo();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_demoKey);
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

  /// Connexion aux comptes de démonstration ouverte par le serveur (désactivée en production).
  bool comptesDemo = false;

  void _appliquer(Map<String, dynamic> d) {
    creationBoutique = d['creation_boutique'] as bool? ?? true;
    comptesDemo = d['comptes_demo'] as bool? ?? comptesDemo;
    notifyListeners();
  }

  Future<void> charger() async => _appliquer(await api.parametres());

  Future<void> autoriserCreationBoutique(bool autorise) async =>
      _appliquer(await api.modifierParametres({'creation_boutique': autorise}));
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'demo_server.dart';

/// Client HTTP du mode démo : les requêtes de [Api] sont traitées par [DemoServer]
/// dans l'application, sans réseau.
class DemoClient extends http.BaseClient {
  DemoClient(this.serveur);

  final DemoServer serveur;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Petit délai : les écrans affichent leur chargement comme avec le vrai serveur.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    var chemin = request.url.path;
    final i = chemin.indexOf('/api/');
    if (i >= 0) chemin = chemin.substring(i + 4);
    final token = request.headers['Authorization']?.replaceFirst('Bearer ', '');

    int status;
    Object? corps;
    try {
      if (request is http.MultipartRequest && chemin == '/uploads') {
        (status, corps) = (201, {'url': await _enregistrerImage(request)});
      } else {
        final texte = request is http.Request ? request.body : '';
        final body = texte.isEmpty ? <String, dynamic>{} : jsonDecode(texte);
        (status, corps) = serveur.traiter(
          request.method,
          chemin,
          request.url.queryParameters,
          body is Map<String, dynamic> ? body : {},
          token,
        );
      }
    } on DemoErreur catch (e) {
      (status, corps) = (e.status, {'erreur': e.message, 'details': e.details});
    } catch (e, pile) {
      debugPrint('Mode démo : $e\n$pile');
      (status, corps) = (500, {'erreur': 'Erreur interne du serveur'});
    }
    final octets = corps == null ? <int>[] : utf8.encode(jsonEncode(corps));
    return http.StreamedResponse(
      Stream.value(octets),
      status,
      contentLength: octets.length,
      request: request,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  /// Photo de produit : copiée dans les fichiers de l'application (adresse file://).
  Future<String> _enregistrerImage(http.MultipartRequest request) async {
    if (request.files.isEmpty) throw DemoErreur(400, 'Aucune image reçue (champ « image »)');
    final fichier = request.files.first;
    final dossier = Directory('${Directory.systemTemp.path}/demo-images');
    await dossier.create(recursive: true);
    final ext = (fichier.filename ?? 'image.jpg').split('.').last.toLowerCase();
    final cible = File('${dossier.path}/${DateTime.now().millisecondsSinceEpoch}.$ext');
    await cible.writeAsBytes(await fichier.finalize().toBytes());
    return cible.uri.toString();
  }
}

const _cleDonnees = 'demo_donnees';

/// Charge le serveur de démonstration avec les données enregistrées sur le téléphone
/// (ou les données de départ si [reinitialiser] ou si rien n'est enregistré).
Future<DemoServer> chargerServeurDemo({bool reinitialiser = false}) async {
  final prefs = await SharedPreferences.getInstance();
  Map<String, dynamic>? etat;
  if (reinitialiser) {
    await prefs.remove(_cleDonnees);
  } else {
    try {
      final brut = prefs.getString(_cleDonnees);
      if (brut != null) etat = jsonDecode(brut) as Map<String, dynamic>;
    } catch (_) {
      etat = null; // données illisibles : on repart des données de départ
    }
  }
  late final DemoServer serveur;
  Timer? sauvegarde;
  serveur = DemoServer(
    etat: etat,
    onChange: () {
      sauvegarde?.cancel();
      sauvegarde = Timer(const Duration(milliseconds: 400), () {
        prefs.setString(_cleDonnees, jsonEncode(serveur.db)).ignore();
      });
    },
  );
  return serveur;
}

import 'dart:io' show Platform;

/// URL de l'API. Surchargeable au build :
///   flutter run --dart-define=API_URL=http://192.168.1.10:3000
class AppConfig {
  static const _fromEnv = String.fromEnvironment('API_URL');

  static String get baseUrl {
    if (_fromEnv.isNotEmpty) return _fromEnv;
    // L'émulateur Android joint la machine hôte via 10.0.2.2.
    return Platform.isAndroid ? 'http://10.0.2.2:3000' : 'http://localhost:3000';
  }

  static String get apiUrl => '$baseUrl/api';

  /// Résout une URL d'image relative (/uploads/...) renvoyée par l'API.
  static String? imageUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    return path.startsWith('http') ? path : '$baseUrl$path';
  }
}

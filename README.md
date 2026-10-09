# AgroPhyto — vente en ligne de produits phytosanitaires et d'aliments pour éleveurs

Implémentation de la conception décrite dans le dossier « Analyse et conception d'une application mobile de vente en ligne des produits phytosanitaires et produits pour élevages » (cas du Cameroun).

```
backend/   API REST Node.js (Express + SQLite)
mobile/    Application mobile Flutter (Android / iOS)
```

## Démarrage

### 1. API

Il faut Node.js 22.13 ou plus récent (le module intégré `node:sqlite` est utilisé, aucune base à installer).

```bash
cd backend
npm install
npm run seed     # (ré)initialise la base avec des données de démonstration
npm start        # http://localhost:3000/api
npm test         # tests d'intégration des scénarios de la conception
```

Variables d'environnement : `PORT`, `DB_FILE`, `UPLOAD_DIR`, `JWT_SECRET`, `JWT_EXPIRES_IN`, `PAYMENT_CALLBACK_SECRET`, `PAYMENT_MOCK_DELAY_MS`, `DEMO_ACCOUNTS` (`false` pour désactiver la connexion de démonstration).

Comptes de démonstration (mot de passe `password123`) :

| Rôle           | Identifiant                        |
|----------------|------------------------------------|
| Administrateur | `690000001` / admin@agrophyto.cm   |
| Vendeur        | `690000002` / vendeur@agrophyto.cm |
| Livreur        | `690000003` / livreur@agrophyto.cm |
| Client         | `690000004` / client@agrophyto.cm  |

Dans l'application, l'écran de connexion propose aussi « Compte de démonstration » : un appui sur Client, Vendeur, Livreur ou Admin ouvre directement la session correspondante, sans mot de passe (route `POST /api/auth/demo`). Ces comptes étant partagés, s'y déconnecter ne ferme pas la session des autres visiteurs. À désactiver en production avec `DEMO_ACCOUNTS=false`.

L'administrateur peut fermer ou rouvrir la création de boutiques par les utilisateurs (Administration → Paramètres de la plateforme, ou `PUT /api/admin/parametres {"creation_boutique": false}`). Fermée, elle bloque l'ouverture de boutique et l'inscription vendeur, sauf pour les administrateurs ; les boutiques existantes ne sont pas touchées.

### 2. Application mobile

```bash
cd mobile
flutter pub get
flutter run                                           # émulateur Android → 10.0.2.2:3000, simulateur iOS → localhost:3000
flutter run --dart-define=API_URL=http://192.168.1.20:3000   # téléphone réel sur le même réseau
```

### 3. Test de bout en bout (simulateur)

Avec l'API démarrée sur une base fraîche (`npm run seed && npm start`) :

```bash
cd mobile
flutter test integration_test/parcours_test.dart -d <id-du-simulateur>
```

Le test enchaîne le parcours client (recherche, panier, commande, paiement), la livraison par le livreur, puis le tableau de bord administrateur.

> Si un environnement conda est actif, la compilation iOS échoue (variables `CC`, `CFLAGS`, `SDKROOT`…). Lancez `conda deactivate` avant `flutter run` / `flutter test`.

## Correspondance avec la conception

### Acteurs → rôles et permissions

Les acteurs du diagramme de cas d'utilisation deviennent des rôles, chacun doté de permissions (`backend/src/constants.js`). L'administrateur peut créer des rôles et modifier leurs permissions depuis l'application.

| Acteur          | Rôle      | Permissions principales                                    |
|-----------------|-----------|------------------------------------------------------------|
| Client          | `client`  | acheter, payer, suivre ses commandes, donner son avis, écrire |
| Vendeur         | `vendeur` | `boutique.gerer`, `produits.gerer`                         |
| Livreur         | `livreur` | `livraisons.effectuer`                                     |
| Administrateur  | `admin`   | toutes les permissions                                      |
| Système de paiement | —     | acteur externe : `services/payment.js` + webhook `POST /api/paiements/callback` |

### Diagramme de classes → tables

`users`, `roles`, `permissions` (plus les tables de liaison `user_roles` et `role_permissions`), `categories`, `produits`, `paniers` et `panier_items`, `commandes` et `commande_items`, `payements`, `factures`, `avis`, `messagerie`, `notifications` et `notification_logs`. S'y ajoutent `boutiques`, `regles_livraison` et `newsletter`, nécessaires à certains cas d'utilisation (voir `backend/src/db.js`).

### Cas d'utilisation → écrans / API

| Cas d'utilisation | Mobile | API |
|---|---|---|
| S'authentifier, créer / gérer son compte, se déconnecter | `screens/auth`, `screens/compte` | `/api/auth`, `/api/compte` |
| Consulter le catalogue, rechercher des produits, catégories et prix | `screens/catalogue` | `GET /api/produits`, `GET /api/categories` |
| Voir les détails d'un produit, donner son avis | `product_detail_screen.dart` | `/api/produits/:id`, `/api/produits/:id/avis` |
| Gérer le panier (calcul automatique du total) | `panier/cart_screen.dart` | `/api/panier` |
| Passer la commande, gérer l'adresse de livraison | `panier/checkout_screen.dart` | `POST /api/commandes/recapitulatif`, `POST /api/commandes` |
| Payer la commande (MTN MoMo / Orange Money) | `panier/payment_screen.dart` | `POST /api/paiements`, `GET /api/paiements/:id` |
| Consulter l'historique, suivre la commande, noter | `screens/commandes` | `/api/commandes` |
| Écrire des messages, appeler | `screens/messages` (appel via `tel:`) | `/api/messages` |
| Notifications (commande, paiement, livraison) | `notifications_screen.dart` | `/api/notifications` |
| S'inscrire à la newsletter | inscription et compte | `/api/newsletter`, `/api/compte/newsletter` |
| Créer la boutique, gérer les stocks, publier les produits | `screens/vendeur` | `/api/boutiques`, `/api/produits` (POST/PUT/PATCH/DELETE) |
| Consulter les livraisons, prendre en charge, confirmer ou signaler un échec | `screens/livreur` | `/api/livraisons` |
| Gérer les utilisateurs et les rôles | `admin_users_screen.dart`, `admin_roles_screen.dart` | `/api/admin/utilisateurs`, `/api/admin/roles` |
| Gérer les catégories | `admin_categories_screen.dart` | `/api/categories` |
| Consulter toutes les commandes, mettre à jour leur statut | `admin_orders_screen.dart` | `/api/admin/commandes` |
| Voir les paiements | `admin_payments_screen.dart` | `/api/admin/paiements` |
| Configurer les règles de livraison | `admin_delivery_rules_screen.dart` | `/api/admin/regles-livraison` |
| Consulter les statistiques des ventes | `admin_home_screen.dart` | `/api/admin/statistiques` |

### Diagrammes de séquence

Les fichiers `backend/test/api.test.js` vérifient chaque diagramme, y compris ses branches `alt`.

- **Authentification :** message « Nom d'utilisateur ou mot de passe incorrect », mise à jour de `derniere_connexion`.
- **Gestion des produits :** ajout (« Produit existant »), modification (« Produit introuvable ») et suppression (« Suppression impossible »). Un produit déjà commandé est retiré du catalogue au lieu d'être supprimé, pour conserver l'historique.
- **Passer la commande :** « Panier vide », puis vérification du stock (« Stock insuffisant »), création, calcul du montant et statut `en_attente_paiement`. Le stock est réservé à la création de la commande et rendu si elle est annulée.
- **Paiement :** « Commande introuvable ou déjà payée ». Si le paiement est accepté, la commande passe `en_cours` et une facture est émise ; s'il est refusé, le client peut réessayer.
- **Gestion des livraisons :** prise en charge (« Commande indisponible »), passage `en_livraison`, confirmation `livree` (« statut incorrect »), et `echec_livraison` avec un motif.

Cycle de vie d'une commande :

```
en_attente_paiement ──paiement réussi──▶ en_cours ──prise en charge──▶ en_livraison ──▶ livree
        │                                    │                              └──────────▶ echec_livraison ──▶ en_cours (relance)
        └──────────── annulee ◀──────────────┘
```

## Paiement mobile

Par défaut, l'API utilise un opérateur **simulé** (`createMockPaymentProvider`). Il répond au bout de `PAYMENT_MOCK_DELAY_MS` millisecondes et refuse les numéros se terminant par `0000`, ce qui permet de tester le cas « Paiement refusé ».

Pour brancher les vraies API MTN MoMo ou Orange Money, il suffit d'écrire un fournisseur qui respecte le même contrat (`requestPayment` et `setResultHandler`), de le passer à `createApp({ paymentProvider })` et de configurer l'opérateur pour qu'il appelle le webhook `POST /api/paiements/callback` avec l'en-tête `x-callback-secret`.

Les envois SMS et email des notifications sont eux aussi simulés : ils sont journalisés dans `notification_logs`. Les passerelles réelles s'injectent dans `createNotifier`.

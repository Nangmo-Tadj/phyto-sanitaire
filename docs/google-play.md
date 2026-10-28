# Publier « fonction Phyto » sur Google Play

## 0. Décisions à prendre avant la première publication

| Élément | Valeur actuelle | Remarque |
|---|---|---|
| Identifiant de l'application | `cm.fonctionphyto.app` | **Définitif** une fois publié. À changer maintenant si besoin dans `mobile/android/app/build.gradle.kts` (`applicationId`, `namespace`), le dossier `kotlin/cm/fonctionphyto/app` et `ios/Runner.xcodeproj/project.pbxproj`. |
| Nom affiché | fonction Phyto | `AndroidManifest.xml` (`android:label`), `Info.plist`. |
| Version | `1.0.0+1` | `mobile/pubspec.yaml` : augmenter le nombre après `+` à chaque envoi. |

## 1. Pré-requis

1. **API en ligne en HTTPS.** Héberger `backend/` sur un serveur (VPS, Render, Railway…) avec un nom de domaine et un certificat (ex. `https://api.fonctionphyto.cm`) :
   ```bash
   NODE_ENV=production JWT_SECRET=<chaîne aléatoire longue> PAYMENT_CALLBACK_SECRET=<secret> PORT=3000 npm start
   npm run creer-admin -- --telephone 6XXXXXXXX --prenom … --nom … --email …
   ```
   En production les comptes de démonstration sont désactivés et l'API refuse de démarrer sans `JWT_SECRET`. Sauvegarder chaque jour `backend/data/*.db` et `backend/uploads/`.
2. **Compte développeur Google Play Console** (frais uniques de 25 USD) : <https://play.google.com/console/signup>. Préférer un compte **Organisation** (au nom d'IDfonction, numéro D-U-N-S requis) : un compte Personnel récent doit d'abord faire un test fermé avec au moins 12 testeurs pendant 14 jours.
3. **Politique de confidentialité publiée** : `docs/politique-confidentialite.html`, compléter les informations entre crochets puis la publier (par ex. GitHub Pages : Settings → Pages → branche `main`, dossier `/docs` → `https://nangmo-tadj.github.io/phyto-sanitaire/politique-confidentialite.html`).

## 2. Clé de signature

La clé d'envoi a été générée dans `~/fonction-phyto-signature/` (hors du dépôt Git) :

- `upload-keystore.jks` : la clé ;
- `key.properties` : mot de passe et alias (copie de `mobile/android/key.properties`, ignoré par Git).

**À sauvegarder immédiatement en deux endroits sûrs.** Lors de la création de l'application dans la Play Console, garder la « Signature d'application par Google Play » (par défaut) : Google conserve la clé finale et la clé d'envoi peut être réinitialisée en cas de perte.

## 3. Construire le fichier à envoyer (.aab)

```bash
cd mobile
conda deactivate   # si un environnement conda est actif
flutter build appbundle --release --dart-define=API_URL=https://api.fonctionphyto.cm
# → build/app/outputs/bundle/release/app-release.aab
```

Sans `API_URL`, l'application cherche l'API sur l'ordinateur de développement : le fichier serait inutilisable.

## 4. Fiche Play Store

**Nom :** fonction Phyto

**Description courte (80 caractères max) :**
> Produits phytosanitaires et aliments pour animaux livrés près de chez vous.

**Description longue :**
> fonction Phyto est la boutique en ligne des agriculteurs et des éleveurs du Cameroun.
>
> • Catalogue d'herbicides, insecticides, fongicides, engrais, provendes et produits vétérinaires, avec prix et disponibilité.
> • Panier avec calcul automatique des frais de livraison selon votre ville.
> • Paiement par MTN Mobile Money ou Orange Money.
> • Suivi de commande étape par étape : reçue, confirmée, en préparation, en cours de livraison, livrée, clôturée — avec une notification à chaque étape.
> • Reçu et facture consultables dans l'application.
> • Messagerie avec les vendeurs et le service client, avis sur les produits.
> • Espace vendeur pour gérer sa boutique et ses stocks, espace livreur pour les tournées.

**Catégorie :** Shopping (ou Entreprise). **Coordonnées :** e-mail de contact obligatoire, site web facultatif.

**Visuels à fournir :**
- icône 512 × 512 px (PNG) — à partir de `mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png` redimensionné ;
- image de présentation 1024 × 500 px ;
- au moins 2 captures d'écran de téléphone (catalogue, fiche produit, panier, suivi de commande).

## 5. Questionnaires de la Play Console

**Sécurité des données** (Contenu de l'application → Sécurité des données) :

| Données | Collectées | Partagées | Finalité |
|---|---|---|---|
| Nom, téléphone, e-mail, adresse | Oui | Avec le vendeur et le livreur de la commande | Gestion du compte, livraison |
| Historique d'achats | Oui | Non | Fonctionnement de l'application |
| Informations de paiement (n° Mobile Money) | Oui | Avec MTN / Orange pour le paiement | Paiement |
| Messages | Oui | Non | Communication client / vendeur |
| Photos (produits, envoyées par les vendeurs) | Oui | Publiées dans le catalogue | Fonctionnement de l'application |

- Données chiffrées en transit : **Oui** (à condition que l'API soit en HTTPS).
- Les utilisateurs peuvent demander la suppression : **Oui** — dans l'application (Compte → Supprimer mon compte) et via la page web de la politique de confidentialité (section « Supprimer votre compte »).

**Classification du contenu :** questionnaire IARC, catégorie « Achats/Commerce » ; pas de violence ni de contenu généré non modéré (les avis sont liés à des achats). **Public cible :** 18 ans et plus. **Annonces :** non.

**Accès à l'application pour la vérification :** fournir à Google un compte client de test (téléphone + mot de passe) créé sur le serveur de production.

## 6. Tests puis production

1. Tests → **Test interne** : envoyer le `.aab`, ajouter les e-mails des testeurs, installer via le lien d'inscription.
2. Vérifier le parcours : inscription, commande, paiement, suivi « Reçue » → « Livrée » avec notifications, connexion administrateur.
3. Test fermé si le compte l'exige (12 testeurs / 14 jours pour un compte personnel récent).
4. Production → Créer une version → envoyer → examen Google (quelques heures à quelques jours).
5. Le lien de téléchargement sera : `https://play.google.com/store/apps/details?id=cm.fonctionphyto.app`.

## 7. Mises à jour

Augmenter `version:` dans `mobile/pubspec.yaml` (ex. `1.0.1+2`), reconstruire le `.aab` avec la même clé et l'envoyer dans une nouvelle version.

# Héberger l'API sur Railway

L'API (dossier `backend/`) se déploie depuis le dépôt GitHub. La base SQLite et les images
sont stockées sur un **volume** Railway, conservé entre les déploiements.

## 1. Créer le service

1. Sur https://railway.com, connectez-vous avec GitHub.
2. **New Project** → **Deploy from GitHub repo** → choisissez `phyto-sanitaire`.
3. Ouvrez le service créé → **Settings** :
   - **Root Directory** : `backend`. Railway lit alors `backend/railway.json` (démarrage
     `npm start`, contrôle de santé `/api/sante`) et `backend/.nvmrc` (Node 22).
   - **Networking** → **Generate Domain** (port `8080` si Railway le demande). Vous obtenez une
     adresse du type `https://fonction-phyto-production.up.railway.app`.

## 2. Ajouter le volume (obligatoire)

Sans volume, **toutes les données sont perdues à chaque déploiement**.

Clic droit dans le projet (ou **Create**) → **Volume** → rattachez-le au service, point de
montage : `/data`.

## 3. Variables d'environnement

Service → **Variables** → **Raw Editor**, puis collez en remplaçant les valeurs :

```
NODE_ENV=production
JWT_SECRET=<chaîne aléatoire de 64 caractères>
DB_FILE=/data/agrophyto.db
UPLOAD_DIR=/data/uploads
TRUST_PROXY=1
ADMIN_TELEPHONE=<téléphone du propriétaire>
ADMIN_PRENOM=<prénom>
ADMIN_NOM=<nom>
ADMIN_EMAIL=<email>
ADMIN_MOT_DE_PASSE=<10 caractères min., majuscule, minuscule et chiffre>
```

- `JWT_SECRET` : générez-la avec `openssl rand -hex 32`. Sans elle, l'API refuse de démarrer.
- Les variables `ADMIN_*` créent le compte administrateur au premier démarrage, uniquement
  s'il n'existe encore aucun administrateur. Une fois connecté dans l'application,
  **supprimez `ADMIN_MOT_DE_PASSE`** des variables et activez la double authentification.
- Les comptes de démonstration du serveur sont désactivés en production. Le mode démo de
  l'application, lui, fonctionne hors ligne et reste disponible.

Railway redéploie automatiquement après l'enregistrement des variables.

## 4. Vérifier

Ouvrez `https://<votre-domaine>/api/sante` : la réponse doit être `{"statut":"ok"}`.
Les journaux sont dans l'onglet **Deployments** → **View logs**.

## 5. Compiler l'application avec cette adresse

```
cd mobile
flutter build apk --release --dart-define=API_URL=https://<votre-domaine>
flutter build appbundle --release --dart-define=API_URL=https://<votre-domaine>
```

## Premiers pas sur une base vide

La base de production démarre vide (pas de produits d'exemple). Connecté en administrateur :
créez les **catégories** et les **règles de livraison** (Administration), puis les boutiques
et produits (ou ouvrez la création de boutiques aux vendeurs).

## Mises à jour et sauvegardes

- Chaque `git push` sur `main` redéploie l'API ; le volume est conservé.
- Sauvegarde : Railway propose des **Backups** du volume (onglet du volume). Faites-en une
  avant chaque mise à jour importante.

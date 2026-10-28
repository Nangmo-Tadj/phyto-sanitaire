# Remise des accès au propriétaire — fonction Phyto

Liste à remplir et à remettre au propriétaire (document confidentiel, ne pas versionner une fois rempli).

## 1. Compte administrateur système de l'application

- [ ] Créé sur le serveur de production :
  ```bash
  cd backend && NODE_ENV=production npm run creer-admin -- --telephone 6XXXXXXXX --prenom … --nom … --email …
  ```
  Le mot de passe (10 caractères minimum, majuscule, minuscule, chiffre) est saisi par le propriétaire lui-même.
- [ ] Double authentification activée par le propriétaire : Compte → Double authentification (Google Authenticator, Microsoft Authenticator…). La clé affichée est conservée en lieu sûr.
- [ ] Vérifié : accès à Administration → tableau de bord, commandes, utilisateurs, rôles, catégories, produits, paiements, règles de livraison, paramètres, statistiques, journal d'activité.
- [ ] Comptes administrateurs du prestataire désactivés (Administration → Utilisateurs) après la remise.

## 2. Hébergement et base de données

| Élément | Information |
|---|---|
| Hébergeur / serveur | [nom, adresse IP, accès console] |
| Nom de domaine et registraire | [ex. fonctionphyto.cm] |
| Accès SSH / panneau | [identifiant — mot de passe remis séparément] |
| Base de données | fichier SQLite `backend/data/agrophyto.db` (variable `DB_FILE`) |
| Images | dossier `backend/uploads/` (variable `UPLOAD_DIR`) |
| Secrets | `JWT_SECRET`, `PAYMENT_CALLBACK_SECRET` (dans les variables d'environnement du serveur) |
| Sauvegardes | [fréquence, emplacement, test de restauration effectué le …] |

- [ ] Mot de passe du serveur changé par le propriétaire.
- [ ] Double authentification activée chez l'hébergeur et le registraire.

## 3. Code source

- Dépôt : <https://github.com/Nangmo-Tadj/phyto-sanitaire>
- [ ] Propriétaire ajouté comme propriétaire du dépôt (ou dépôt transféré : Settings → Transfer ownership).
- [ ] Double authentification GitHub activée.
- [ ] Décider si le dépôt reste public ou passe en privé.

## 4. Google Play Console

- [ ] Compte développeur au nom du propriétaire (ou propriétaire ajouté avec le rôle « Administrateur » : Utilisateurs et autorisations).
- [ ] Clé d'envoi remise : `upload-keystore.jks` + `key.properties` (dossier `~/fonction-phyto-signature/`), sur support chiffré, en deux copies.
- [ ] Signature d'application par Google Play activée.

## 5. Services externes

| Service | Accès |
|---|---|
| MTN Mobile Money (API) | [compte marchand, clés] |
| Orange Money (API) | [compte marchand, clés] |
| Passerelle SMS | [fournisseur, clés] |
| E-mail d'envoi | [fournisseur, clés] |

Remis le : ____ / ____ / ________      Par : ______________      Reçu par : ______________

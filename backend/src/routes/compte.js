const crypto = require('node:crypto');
const express = require('express');
const bcrypt = require('bcryptjs');
const { authenticate, signToken } = require('../middleware/auth');
const { badRequest, conflict, forbidden, requireFields } = require('../errors');
const { publicUser } = require('./auth');
const { transaction } = require('../db');
const { DEMO_ACCOUNTS, ROLES } = require('../constants');
const { journaliser } = require('../services/journal');
const { genererSecret, verifierCode, lienOtpauth } = require('../services/totp');
const { verifierMotDePasseFort } = require('../services/securite');

// Gestion de son compte (profil, mot de passe, newsletter, double authentification).
function compteRoutes({ db, config }) {
  const router = express.Router();
  router.use(authenticate(db));

  router.get('/', (req, res) => res.json(publicUser(db, req.user)));

  router.put('/', (req, res) => {
    const champs = ['nom', 'prenom', 'email', 'telephone', 'adresse', 'profil'];
    const data = Object.fromEntries(champs.map((c) => [c, req.body[c] !== undefined ? req.body[c] : req.user[c]]));
    if (!String(data.nom || '').trim() || !String(data.prenom || '').trim() || !String(data.telephone || '').trim()) {
      throw badRequest('Nom, prénom et téléphone sont obligatoires');
    }
    data.email = data.email ? String(data.email).trim().toLowerCase() : null;
    // Normaliser avant le contrôle de doublon (sinon violation UNIQUE -> erreur 500).
    data.nom = String(data.nom).trim();
    data.prenom = String(data.prenom).trim();
    data.telephone = String(data.telephone).trim();
    const doublon = db
      .prepare('SELECT 1 FROM users WHERE id_user <> ? AND (telephone = ? OR (email IS NOT NULL AND email = ?))')
      .get(req.user.id_user, data.telephone, data.email);
    if (doublon) throw conflict('Ce téléphone ou cet email est déjà utilisé');

    db.prepare(
      'UPDATE users SET nom = ?, prenom = ?, email = ?, telephone = ?, adresse = ?, profil = ? WHERE id_user = ?',
    ).run(data.nom, data.prenom, data.email, data.telephone, data.adresse, data.profil, req.user.id_user);
    res.json(publicUser(db, db.prepare('SELECT * FROM users WHERE id_user = ?').get(req.user.id_user)));
  });

  router.put('/mot-de-passe', (req, res) => {
    requireFields(req.body, ['ancien', 'nouveau']);
    if (!bcrypt.compareSync(req.body.ancien, req.user.mdp)) throw badRequest('Ancien mot de passe incorrect');
    if (String(req.body.nouveau).length < 6) throw badRequest('Le mot de passe doit contenir au moins 6 caractères');
    if (req.user.roles.includes(ROLES.ADMIN)) verifierMotDePasseFort(req.body.nouveau);
    db.prepare('UPDATE users SET mdp = ?, token_version = token_version + 1 WHERE id_user = ?').run(
      bcrypt.hashSync(req.body.nouveau, 10),
      req.user.id_user,
    );
    const user = db.prepare('SELECT * FROM users WHERE id_user = ?').get(req.user.id_user);
    journaliser(db, req, 'compte.mot_de_passe');
    res.json({ message: 'Mot de passe modifié', token: signToken(user) });
  });

  // --- Double authentification (application Google Authenticator, Microsoft Authenticator…) ---
  const verifierMotDePasse = (req) => {
    requireFields(req.body, ['mot_de_passe']);
    if (!bcrypt.compareSync(String(req.body.mot_de_passe), req.user.mdp)) throw badRequest('Mot de passe incorrect');
  };

  // Étape 1 : génère la clé à saisir (ou scanner) dans l'application d'authentification.
  router.post('/2fa/initier', (req, res) => {
    verifierMotDePasse(req);
    if (config.demoAccounts && Object.values(DEMO_ACCOUNTS).includes(req.user.telephone)) {
      throw forbidden('Indisponible sur un compte de démonstration partagé');
    }
    if (req.user.totp_actif) throw conflict('La double authentification est déjà activée');
    const secret = genererSecret();
    db.prepare('UPDATE users SET totp_secret = ? WHERE id_user = ?').run(secret, req.user.id_user);
    res.json({ secret, otpauth: lienOtpauth(secret, req.user.email || req.user.telephone) });
  });

  // Étape 2 : le premier code saisi prouve que l'application est bien configurée.
  router.post('/2fa/activer', (req, res) => {
    requireFields(req.body, ['code']);
    if (req.user.totp_actif) throw conflict('La double authentification est déjà activée');
    if (!req.user.totp_secret) throw badRequest('Générez d’abord une clé');
    if (!verifierCode(req.user.totp_secret, req.body.code)) throw badRequest('Code incorrect. Vérifiez l’heure de votre téléphone.');
    db.prepare('UPDATE users SET totp_actif = 1 WHERE id_user = ?').run(req.user.id_user);
    journaliser(db, req, 'compte.2fa.activer');
    res.json(publicUser(db, db.prepare('SELECT * FROM users WHERE id_user = ?').get(req.user.id_user)));
  });

  router.post('/2fa/desactiver', (req, res) => {
    verifierMotDePasse(req);
    if (!req.user.totp_actif) throw conflict('La double authentification n’est pas activée');
    if (!verifierCode(req.user.totp_secret, req.body.code)) throw badRequest('Code de vérification incorrect');
    db.prepare('UPDATE users SET totp_actif = 0, totp_secret = NULL WHERE id_user = ?').run(req.user.id_user);
    journaliser(db, req, 'compte.2fa.desactiver');
    res.json(publicUser(db, db.prepare('SELECT * FROM users WHERE id_user = ?').get(req.user.id_user)));
  });

  // Suppression du compte (exigée par Google Play). Les commandes sont conservées pour la
  // comptabilité mais rendues anonymes ; les données personnelles sont effacées.
  router.delete('/', (req, res) => {
    verifierMotDePasse(req);
    if (config.demoAccounts && Object.values(DEMO_ACCOUNTS).includes(req.user.telephone)) {
      throw forbidden('Un compte de démonstration ne peut pas être supprimé');
    }
    if (req.user.roles.includes(ROLES.ADMIN)) {
      const autres = db
        .prepare(
          `SELECT COUNT(*) AS n FROM users u JOIN user_roles ur ON ur.id_user = u.id_user JOIN roles r ON r.id_role = ur.id_role
           WHERE r.nom = ? AND u.actif = 1 AND u.id_user <> ?`,
        )
        .get(ROLES.ADMIN, req.user.id_user).n;
      if (!autres) throw conflict('Vous êtes le dernier administrateur : nommez-en un autre avant de supprimer ce compte');
    }
    const id = req.user.id_user;
    transaction(db, () => {
      if (req.user.email) db.prepare('DELETE FROM newsletter WHERE email = ?').run(req.user.email);
      db.prepare('DELETE FROM paniers WHERE id_user = ?').run(id);
      db.prepare('DELETE FROM notifications WHERE id_user = ?').run(id);
      db.prepare('DELETE FROM messagerie WHERE id_expediteur = ? OR id_destinataire = ?').run(id, id);
      db.prepare('DELETE FROM user_roles WHERE id_user = ?').run(id);
      db.prepare('UPDATE boutiques SET active = 0 WHERE id_vendeur = ?').run(id);
      db.prepare(
        `UPDATE users SET nom = 'supprimé', prenom = 'Compte', email = NULL, telephone = ?, adresse = NULL, profil = NULL,
           mdp = ?, actif = 0, newsletter = 0, totp_secret = NULL, totp_actif = 0, token_version = token_version + 1
         WHERE id_user = ?`,
      ).run(`supprime-${id}`, bcrypt.hashSync(crypto.randomBytes(24).toString('hex'), 10), id);
      db.prepare('UPDATE commandes SET telephone_livraison = ?, adresse_livraison = ? WHERE id_user = ?').run('-', '(supprimée)', id);
    });
    journaliser(db, req, 'compte.supprimer');
    res.status(204).end();
  });

  router.put('/newsletter', (req, res) => {
    const abonne = Boolean(req.body.abonne);
    db.prepare('UPDATE users SET newsletter = ? WHERE id_user = ?').run(abonne ? 1 : 0, req.user.id_user);
    if (req.user.email) {
      if (abonne) db.prepare('INSERT OR IGNORE INTO newsletter (email) VALUES (?)').run(req.user.email);
      else db.prepare('DELETE FROM newsletter WHERE email = ?').run(req.user.email);
    }
    res.json({ abonne });
  });

  return router;
}

// S'inscrire à la newsletter (sans compte).
function newsletterRoutes({ db }) {
  const router = express.Router();
  router.post('/', (req, res) => {
    requireFields(req.body, ['email']);
    const email = String(req.body.email).trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw badRequest('Adresse email invalide');
    db.prepare('INSERT OR IGNORE INTO newsletter (email) VALUES (?)').run(email);
    res.status(201).json({ message: 'Inscription à la newsletter confirmée' });
  });
  return router;
}

module.exports = { compteRoutes, newsletterRoutes };

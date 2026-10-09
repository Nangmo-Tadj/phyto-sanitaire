const express = require('express');
const bcrypt = require('bcryptjs');
const { signToken, authenticate, loadRolesAndPermissions } = require('../middleware/auth');
const { badRequest, unauthorized, forbidden, notFound, conflict, requireFields } = require('../errors');
const { transaction } = require('../db');
const { ROLES, DEMO_ACCOUNTS } = require('../constants');
const { lireParametres } = require('../services/parametres');

function publicUser(db, user) {
  const { mdp, token_version, ...rest } = user;
  const boutique = db.prepare('SELECT id_boutique, nom FROM boutiques WHERE id_vendeur = ?').get(user.id_user);
  return {
    ...rest,
    actif: Boolean(rest.actif),
    newsletter: Boolean(rest.newsletter),
    ...loadRolesAndPermissions(db, user.id_user),
    boutique: boutique || null,
  };
}

function authRoutes({ db, config }) {
  const router = express.Router();

  // Créer un compte (client ou vendeur ; livreur/admin sont attribués par l'administrateur).
  router.post('/inscription', (req, res) => {
    requireFields(req.body, ['nom', 'prenom', 'telephone', 'mot_de_passe']);
    const { nom, prenom, email, telephone, adresse, mot_de_passe, type_compte = ROLES.CLIENT } = req.body;
    if (String(mot_de_passe).length < 6) throw badRequest('Le mot de passe doit contenir au moins 6 caractères');
    if (![ROLES.CLIENT, ROLES.VENDEUR].includes(type_compte)) throw badRequest('Type de compte invalide');
    if (type_compte === ROLES.VENDEUR && !lireParametres(db).creation_boutique) {
      throw forbidden('Les inscriptions vendeur sont actuellement fermées. Créez un compte client.');
    }
    if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw badRequest('Adresse email invalide');

    const existe = db
      .prepare('SELECT 1 FROM users WHERE telephone = ? OR (email IS NOT NULL AND email = ?)')
      .get(telephone.trim(), email?.trim().toLowerCase() ?? null);
    if (existe) throw conflict('Un compte existe déjà avec ce téléphone ou cet email');

    const user = transaction(db, () => {
      const { lastInsertRowid } = db
        .prepare('INSERT INTO users (nom, prenom, email, telephone, adresse, mdp) VALUES (?, ?, ?, ?, ?, ?)')
        .run(
          nom.trim(),
          prenom.trim(),
          email ? email.trim().toLowerCase() : null,
          telephone.trim(),
          adresse || null,
          bcrypt.hashSync(mot_de_passe, 10),
        );
      const id = Number(lastInsertRowid);
      const addRole = db.prepare('INSERT INTO user_roles (id_user, id_role) SELECT ?, id_role FROM roles WHERE nom = ?');
      addRole.run(id, ROLES.CLIENT);
      if (type_compte === ROLES.VENDEUR) addRole.run(id, ROLES.VENDEUR);
      return db.prepare('SELECT * FROM users WHERE id_user = ?').get(id);
    });

    res.status(201).json({ token: signToken(user), utilisateur: publicUser(db, user) });
  });

  // Diagramme de séquence « Authentification utilisateur ».
  router.post('/connexion', (req, res) => {
    requireFields(req.body, ['identifiant', 'mot_de_passe']);
    const identifiant = String(req.body.identifiant).trim();
    const user = db
      .prepare('SELECT * FROM users WHERE telephone = ? OR email = ?')
      .get(identifiant, identifiant.toLowerCase());
    if (!user || !bcrypt.compareSync(req.body.mot_de_passe, user.mdp)) {
      throw unauthorized("Nom d'utilisateur ou mot de passe incorrect");
    }
    if (!user.actif) throw forbidden('Compte désactivé. Contactez l’administrateur.');
    db.prepare("UPDATE users SET derniere_connexion = datetime('now') WHERE id_user = ?").run(user.id_user);
    const fresh = db.prepare('SELECT * FROM users WHERE id_user = ?').get(user.id_user);
    res.json({ message: 'Connexion réussie', token: signToken(fresh), utilisateur: publicUser(db, fresh) });
  });

  // Découvrir l'application avec un compte de démonstration, sans mot de passe.
  router.post('/demo', (req, res) => {
    if (!config.demoAccounts) throw forbidden('Les comptes de démonstration sont désactivés');
    const profil = String(req.body.profil || ROLES.CLIENT);
    const telephone = Object.hasOwn(DEMO_ACCOUNTS, profil) ? DEMO_ACCOUNTS[profil] : null;
    if (!telephone) throw badRequest(`Profil de démonstration invalide (${Object.keys(DEMO_ACCOUNTS).join(', ')})`);
    const user = db.prepare('SELECT * FROM users WHERE telephone = ?').get(telephone);
    if (!user || !user.actif) throw notFound('Compte de démonstration indisponible');
    db.prepare("UPDATE users SET derniere_connexion = datetime('now') WHERE id_user = ?").run(user.id_user);
    const fresh = db.prepare('SELECT * FROM users WHERE id_user = ?').get(user.id_user);
    res.json({ message: 'Connexion de démonstration', token: signToken(fresh), utilisateur: publicUser(db, fresh) });
  });

  // Se déconnecter : invalide les jetons existants.
  router.post('/deconnexion', authenticate(db), (req, res) => {
    // Comptes de démonstration partagés : on ne déconnecte pas les autres visiteurs.
    const demo = config.demoAccounts && Object.values(DEMO_ACCOUNTS).includes(req.user.telephone);
    if (!demo) db.prepare('UPDATE users SET token_version = token_version + 1 WHERE id_user = ?').run(req.user.id_user);
    res.json({ message: 'Déconnexion réussie' });
  });

  return router;
}

module.exports = { authRoutes, publicUser };

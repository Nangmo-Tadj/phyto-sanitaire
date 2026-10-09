const express = require('express');
const bcrypt = require('bcryptjs');
const { authenticate, signToken } = require('../middleware/auth');
const { badRequest, conflict, requireFields } = require('../errors');
const { publicUser } = require('./auth');

// Gestion de son compte (profil, mot de passe, newsletter).
function compteRoutes({ db }) {
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
    db.prepare('UPDATE users SET mdp = ?, token_version = token_version + 1 WHERE id_user = ?').run(
      bcrypt.hashSync(req.body.nouveau, 10),
      req.user.id_user,
    );
    const user = db.prepare('SELECT * FROM users WHERE id_user = ?').get(req.user.id_user);
    res.json({ message: 'Mot de passe modifié', token: signToken(user) });
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

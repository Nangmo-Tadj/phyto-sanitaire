const bcrypt = require('bcryptjs');
const { transaction } = require('../db');
const { ROLES } = require('../constants');
const { verifierMotDePasseFort } = require('./securite');
const { journaliser } = require('./journal');

/**
 * Crée (ou promeut) le compte administrateur système. Un compte existant (même téléphone
 * ou email) reçoit le nouveau mot de passe, ce qui ferme ses sessions ouvertes.
 */
function creerAdmin(db, { telephone, prenom, nom, email, motDePasse, source = 'script' }) {
  verifierMotDePasseFort(motDePasse);
  telephone = String(telephone).trim();
  email = email ? String(email).trim().toLowerCase() : null;
  const existant = db.prepare('SELECT * FROM users WHERE telephone = ? OR (email IS NOT NULL AND email = ?)').get(telephone, email);
  return transaction(db, () => {
    let id = existant?.id_user;
    const hash = bcrypt.hashSync(motDePasse, 10);
    if (existant) {
      db.prepare('UPDATE users SET mdp = ?, actif = 1, token_version = token_version + 1 WHERE id_user = ?').run(hash, id);
    } else {
      if (!prenom || !nom) throw new Error('Prénom et nom sont obligatoires pour un nouveau compte');
      id = Number(
        db.prepare('INSERT INTO users (nom, prenom, email, telephone, mdp) VALUES (?, ?, ?, ?, ?)')
          .run(String(nom).trim(), String(prenom).trim(), email, telephone, hash).lastInsertRowid,
      );
    }
    const addRole = db.prepare('INSERT OR IGNORE INTO user_roles (id_user, id_role) SELECT ?, id_role FROM roles WHERE nom = ?');
    addRole.run(id, ROLES.CLIENT);
    addRole.run(id, ROLES.ADMIN);
    journaliser(db, null, existant ? 'admin.promouvoir' : 'admin.creer', `Compte administrateur système (${source})`, id);
    return { id, cree: !existant };
  });
}

/** Nombre d'administrateurs actifs. */
const nombreAdmins = (db) =>
  db
    .prepare(
      `SELECT COUNT(*) AS n FROM users u JOIN user_roles ur ON ur.id_user = u.id_user
       JOIN roles r ON r.id_role = ur.id_role WHERE r.nom = ? AND u.actif = 1`,
    )
    .get(ROLES.ADMIN).n;

module.exports = { creerAdmin, nombreAdmins };

// Crée (ou promeut) le compte administrateur système du propriétaire.
// Usage : npm run creer-admin -- --telephone 6XXXXXXXX --prenom Jean --nom Dupont [--email jean@exemple.cm]
// Le mot de passe est demandé sans affichage (ou lu dans ADMIN_MOT_DE_PASSE).
const { parseArgs } = require('node:util');
const readline = require('node:readline');
const bcrypt = require('bcryptjs');
const config = require('./config');
const { open, transaction } = require('./db');
const { ensureDefaults } = require('./bootstrap');
const { ROLES } = require('./constants');
const { verifierMotDePasseFort } = require('./services/securite');
const { journaliser } = require('./services/journal');

function demanderMotDePasse(question) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    rl._writeToOutput = (s) => {
      if (s.includes(question)) rl.output.write(s);
    };
    rl.question(question, (reponse) => {
      rl.close();
      process.stdout.write('\n');
      resolve(reponse);
    });
  });
}

async function main() {
  const { values } = parseArgs({
    options: { telephone: { type: 'string' }, prenom: { type: 'string' }, nom: { type: 'string' }, email: { type: 'string' } },
  });
  if (!values.telephone) {
    console.error('Usage : npm run creer-admin -- --telephone 6XXXXXXXX --prenom Prénom --nom Nom [--email adresse]');
    process.exit(1);
  }
  const telephone = values.telephone.trim();
  const email = values.email ? values.email.trim().toLowerCase() : null;

  let mdp = process.env.ADMIN_MOT_DE_PASSE;
  if (!mdp) {
    mdp = await demanderMotDePasse('Mot de passe administrateur : ');
    if ((await demanderMotDePasse('Confirmez le mot de passe : ')) !== mdp) throw new Error('Les mots de passe ne correspondent pas');
  }
  try {
    verifierMotDePasseFort(mdp);
  } catch (err) {
    throw new Error(err.message);
  }

  const db = open(config.dbFile);
  ensureDefaults(db);
  const existant = db.prepare('SELECT * FROM users WHERE telephone = ? OR (email IS NOT NULL AND email = ?)').get(telephone, email);
  const idUser = transaction(db, () => {
    let id = existant?.id_user;
    const hash = bcrypt.hashSync(mdp, 10);
    if (existant) {
      // Le changement de mot de passe déconnecte les sessions ouvertes.
      db.prepare('UPDATE users SET mdp = ?, actif = 1, token_version = token_version + 1 WHERE id_user = ?').run(hash, id);
    } else {
      if (!values.prenom || !values.nom) throw new Error('--prenom et --nom sont obligatoires pour un nouveau compte');
      id = Number(
        db.prepare('INSERT INTO users (nom, prenom, email, telephone, mdp) VALUES (?, ?, ?, ?, ?)')
          .run(values.nom.trim(), values.prenom.trim(), email, telephone, hash).lastInsertRowid,
      );
    }
    const addRole = db.prepare('INSERT OR IGNORE INTO user_roles (id_user, id_role) SELECT ?, id_role FROM roles WHERE nom = ?');
    addRole.run(id, ROLES.CLIENT);
    addRole.run(id, ROLES.ADMIN);
    journaliser(db, null, existant ? 'admin.promouvoir' : 'admin.creer', 'Compte administrateur système (script)', id);
    return id;
  });
  db.close();
  console.log(`Administrateur système ${existant ? 'mis à jour' : 'créé'} (id ${idUser}, téléphone ${telephone}).`);
  console.log('Connectez-vous dans l’application puis activez la double authentification : Compte > Sécurité.');
}

main().catch((err) => {
  console.error(`Erreur : ${err.message}`);
  process.exit(1);
});

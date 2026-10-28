// Crée (ou promeut) le compte administrateur système du propriétaire.
// Usage : npm run creer-admin -- --telephone 6XXXXXXXX --prenom Jean --nom Dupont [--email jean@exemple.cm]
// Le mot de passe est demandé sans affichage (ou lu dans ADMIN_MOT_DE_PASSE).
const { parseArgs } = require('node:util');
const readline = require('node:readline');
const config = require('./config');
const { open } = require('./db');
const { ensureDefaults } = require('./bootstrap');
const { creerAdmin } = require('./services/admin');

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

  let mdp = process.env.ADMIN_MOT_DE_PASSE;
  if (!mdp) {
    mdp = await demanderMotDePasse('Mot de passe administrateur : ');
    if ((await demanderMotDePasse('Confirmez le mot de passe : ')) !== mdp) throw new Error('Les mots de passe ne correspondent pas');
  }
  const db = open(config.dbFile);
  ensureDefaults(db);
  let resultat;
  try {
    resultat = creerAdmin(db, { telephone: values.telephone, prenom: values.prenom, nom: values.nom, email: values.email, motDePasse: mdp });
  } finally {
    db.close();
  }
  const { id: idUser, cree } = resultat;
  const telephone = values.telephone.trim();
  console.log(`Administrateur système ${cree ? 'créé' : 'mis à jour'} (id ${idUser}, téléphone ${telephone}).`);
  console.log('Connectez-vous dans l’application puis activez la double authentification : Compte > Sécurité.');
}

main().catch((err) => {
  console.error(`Erreur : ${err.message}`);
  process.exit(1);
});

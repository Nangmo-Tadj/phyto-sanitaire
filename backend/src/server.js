const { createApp } = require('./app');
const config = require('./config');
const { creerAdmin, nombreAdmins } = require('./services/admin');

if (config.production && config.jwtSecret === 'changez-moi-en-production') {
  console.error('JWT_SECRET doit être défini en production (chaîne aléatoire longue).');
  process.exit(1);
}

const app = createApp();

// Premier démarrage d'un hébergement (Railway…) : administrateur créé à partir des variables
// ADMIN_TELEPHONE, ADMIN_PRENOM, ADMIN_NOM, ADMIN_EMAIL et ADMIN_MOT_DE_PASSE, s'il n'y en a aucun.
if (process.env.ADMIN_TELEPHONE && process.env.ADMIN_MOT_DE_PASSE && !nombreAdmins(app.locals.ctx.db)) {
  try {
    const { id } = creerAdmin(app.locals.ctx.db, {
      telephone: process.env.ADMIN_TELEPHONE,
      prenom: process.env.ADMIN_PRENOM,
      nom: process.env.ADMIN_NOM,
      email: process.env.ADMIN_EMAIL,
      motDePasse: process.env.ADMIN_MOT_DE_PASSE,
      source: 'variables d’environnement',
    });
    console.log(`Administrateur système créé (id ${id}). Retirez ADMIN_MOT_DE_PASSE des variables.`);
  } catch (err) {
    console.error(`Administrateur non créé : ${err.message}`);
  }
}
const server = app.listen(config.port, '0.0.0.0', () => {
  console.log(`API fonction Phyto démarrée sur http://localhost:${config.port}/api`);
});

function shutdown() {
  server.close(() => {
    app.locals.ctx.paymentProvider.close?.();
    app.locals.ctx.db.close();
    process.exit(0);
  });
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

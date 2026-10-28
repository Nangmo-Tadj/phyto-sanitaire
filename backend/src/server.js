const { createApp } = require('./app');
const config = require('./config');

if (config.production && config.jwtSecret === 'changez-moi-en-production') {
  console.error('JWT_SECRET doit être défini en production (chaîne aléatoire longue).');
  process.exit(1);
}

const app = createApp();
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

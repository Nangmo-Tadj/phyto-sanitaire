const { createApp } = require('./app');
const config = require('./config');

const app = createApp();
const server = app.listen(config.port, '0.0.0.0', () => {
  console.log(`API AgroPhyto démarrée sur http://localhost:${config.port}/api`);
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

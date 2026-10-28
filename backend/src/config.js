const path = require('node:path');

module.exports = {
  port: Number(process.env.PORT || 3000),
  dbFile: process.env.DB_FILE || path.join(__dirname, '..', 'data', 'agrophyto.db'),
  uploadDir: process.env.UPLOAD_DIR || path.join(__dirname, '..', 'uploads'),
  jwtSecret: process.env.JWT_SECRET || 'changez-moi-en-production',
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '7d',
  // Secret partagé avec l'opérateur de paiement pour authentifier ses callbacks.
  paymentCallbackSecret: process.env.PAYMENT_CALLBACK_SECRET || 'callback-secret-dev',
  // Délai de réponse simulé de l'opérateur (MTN MoMo / Orange Money).
  paymentMockDelayMs: Number(process.env.PAYMENT_MOCK_DELAY_MS ?? 4000),
  production: process.env.NODE_ENV === 'production',
  // Nombre de proxys de confiance devant l'API (« loopback » : proxy local seulement).
  trustProxy: /^\d+$/.test(process.env.TRUST_PROXY || '') ? Number(process.env.TRUST_PROXY) : process.env.TRUST_PROXY || 'loopback',
  // Connexion sans mot de passe aux comptes de démonstration : désactivée par défaut en production
  // (elle donnerait l'accès administrateur à tous). DEMO_ACCOUNTS=true|false pour forcer.
  demoAccounts: process.env.DEMO_ACCOUNTS ? process.env.DEMO_ACCOUNTS === 'true' : process.env.NODE_ENV !== 'production',
};

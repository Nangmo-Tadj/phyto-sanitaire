const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const express = require('express');
const cors = require('cors');
const multer = require('multer');

const defaultConfig = require('./config');
const { open } = require('./db');
const { ensureDefaults } = require('./bootstrap');
const { HttpError, badRequest } = require('./errors');
const { authenticate } = require('./middleware/auth');
const { createNotifier } = require('./services/notifications');
const { createCommerce } = require('./services/commerce');
const { createMockPaymentProvider } = require('./services/payment');
const { authRoutes } = require('./routes/auth');
const { compteRoutes, newsletterRoutes } = require('./routes/compte');
const { categoriesRoutes, produitsRoutes, boutiquesRoutes } = require('./routes/catalogue');
const { panierRoutes, commandesRoutes, paiementsRoutes, livraisonsRoutes } = require('./routes/commandes');
const { messagesRoutes, notificationsRoutes } = require('./routes/communication');
const { adminRoutes } = require('./routes/admin');
const { lireParametres } = require('./services/parametres');

function createApp(options = {}) {
  const config = { ...defaultConfig, ...options.config };
  const db = options.db || open(config.dbFile);
  ensureDefaults(db);

  const notifier = options.notifier || createNotifier(db);
  const commerce = createCommerce(db, notifier);
  const paymentProvider = options.paymentProvider || createMockPaymentProvider({ delayMs: config.paymentMockDelayMs });
  paymentProvider.setResultHandler?.((ref, ok, msg) => {
    try {
      commerce.appliquerResultatPaiement(ref, ok, msg);
    } catch (err) {
      console.error('Erreur au traitement du résultat de paiement', err);
    }
  });

  const ctx = { db, config, notifier, commerce, paymentProvider };
  const app = express();
  app.use(cors());
  app.use(express.json({ limit: '1mb' }));

  // Images des produits / photos de profil.
  fs.mkdirSync(config.uploadDir, { recursive: true });
  app.use('/uploads', express.static(config.uploadDir, { maxAge: '7d' }));
  const upload = multer({
    storage: multer.diskStorage({
      destination: config.uploadDir,
      filename: (_req, file, cb) => cb(null, `${Date.now()}-${crypto.randomBytes(6).toString('hex')}${path.extname(file.originalname).toLowerCase()}`),
    }),
    limits: { fileSize: 5 * 1024 * 1024 },
    fileFilter: (_req, file, cb) =>
      /^image\/(jpeg|png|webp|gif)$/.test(file.mimetype) ? cb(null, true) : cb(badRequest('Format d’image non supporté')),
  });
  app.post('/api/uploads', authenticate(db), upload.single('image'), (req, res) => {
    if (!req.file) throw badRequest('Aucune image reçue (champ « image »)');
    res.status(201).json({ url: `/uploads/${req.file.filename}` });
  });

  app.get('/api/sante', (_req, res) => res.json({ statut: 'ok' }));
  // Paramètres publics de la plateforme (l'application adapte ses écrans, ex. ouverture de boutique).
  app.get('/api/parametres', (_req, res) => res.json(lireParametres(db)));
  app.use('/api/auth', authRoutes(ctx));
  app.use('/api/compte', compteRoutes(ctx));
  app.use('/api/newsletter', newsletterRoutes(ctx));
  app.use('/api/categories', categoriesRoutes(ctx));
  app.use('/api/produits', produitsRoutes(ctx));
  app.use('/api/boutiques', boutiquesRoutes(ctx));
  app.use('/api/panier', panierRoutes(ctx));
  app.use('/api/commandes', commandesRoutes(ctx));
  app.use('/api/paiements', paiementsRoutes(ctx));
  app.use('/api/livraisons', livraisonsRoutes(ctx));
  app.use('/api/messages', messagesRoutes(ctx));
  app.use('/api/notifications', notificationsRoutes(ctx));
  app.use('/api/admin', adminRoutes(ctx));

  app.use((_req, _res, next) => next(new HttpError(404, 'Route introuvable')));
  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    if (err instanceof multer.MulterError) err = badRequest(err.message);
    if (err.type === 'entity.parse.failed') err = badRequest('JSON invalide');
    const status = err.status || 500;
    if (status >= 500) console.error(err);
    res.status(status).json({ erreur: status >= 500 ? 'Erreur interne du serveur' : err.message, details: err.details });
  });

  app.locals.ctx = ctx;
  return app;
}

module.exports = { createApp };

const express = require('express');
const { authenticate } = require('../middleware/auth');
const { badRequest, notFound, requireFields, toInt } = require('../errors');
const { PERMISSIONS } = require('../constants');

// --- Messagerie (écrire des messages / discuter avec le client) -------------
function messagesRoutes({ db, notifier }) {
  const router = express.Router();
  router.use(authenticate(db));

  // Liste des conversations avec le dernier message et le nombre de non-lus.
  router.get('/conversations', (req, res) => {
    const me = req.user.id_user;
    const rows = db
      .prepare(
        `WITH msgs AS (
           SELECT m.*, CASE WHEN m.id_expediteur = ? THEN m.id_destinataire ELSE m.id_expediteur END AS interlocuteur
           FROM messagerie m WHERE m.id_expediteur = ? OR m.id_destinataire = ?
         )
         SELECT u.id_user, u.nom, u.prenom, u.telephone, u.profil,
                last.contenu AS dernier_message, last.date_envoie AS date_dernier_message,
                (SELECT COUNT(*) FROM msgs x WHERE x.interlocuteur = u.id_user AND x.id_destinataire = ? AND x.date_lecture IS NULL) AS non_lus
         FROM (SELECT interlocuteur, MAX(id_messagerie) AS last_id FROM msgs GROUP BY interlocuteur) g
         JOIN users u ON u.id_user = g.interlocuteur
         JOIN messagerie last ON last.id_messagerie = g.last_id
         ORDER BY last.id_messagerie DESC`,
      )
      .all(me, me, me, me);
    res.json(rows);
  });

  // Interlocuteur « support » : un administrateur actif.
  router.get('/support', (_req, res) => {
    const admin = db
      .prepare(
        `SELECT DISTINCT u.id_user, u.nom, u.prenom, u.telephone FROM users u
         JOIN user_roles ur ON ur.id_user = u.id_user JOIN role_permissions rp ON rp.id_role = ur.id_role
         JOIN permissions p ON p.id_permission = rp.id_permission
         WHERE p.nom = ? AND u.actif = 1 ORDER BY u.id_user LIMIT 1`,
      )
      .get(PERMISSIONS.COMMANDES_GERER);
    if (!admin) throw notFound('Support indisponible');
    res.json(admin);
  });

  router.get('/non-lus', (req, res) => {
    const { n } = db
      .prepare('SELECT COUNT(*) AS n FROM messagerie WHERE id_destinataire = ? AND date_lecture IS NULL')
      .get(req.user.id_user);
    res.json({ non_lus: n });
  });

  // Fil de discussion ; marque les messages reçus comme lus.
  router.get('/:idUser', (req, res) => {
    const autre = toInt(req.params.idUser, 'idUser');
    const me = req.user.id_user;
    const interlocuteur = db.prepare('SELECT id_user, nom, prenom, telephone, profil FROM users WHERE id_user = ?').get(autre);
    if (!interlocuteur) throw notFound('Utilisateur introuvable');
    const apres = Number(req.query.apres) || 0;
    db.prepare("UPDATE messagerie SET date_lecture = datetime('now') WHERE id_expediteur = ? AND id_destinataire = ? AND date_lecture IS NULL").run(autre, me);
    const messages = db
      .prepare(
        `SELECT * FROM messagerie
         WHERE ((id_expediteur = ? AND id_destinataire = ?) OR (id_expediteur = ? AND id_destinataire = ?)) AND id_messagerie > ?
         ORDER BY id_messagerie`,
      )
      .all(me, autre, autre, me, apres);
    res.json({ interlocuteur, messages });
  });

  router.post('/', (req, res) => {
    requireFields(req.body, ['id_destinataire', 'contenu']);
    const dest = toInt(req.body.id_destinataire, 'id_destinataire');
    if (dest === req.user.id_user) throw badRequest('Vous ne pouvez pas vous écrire à vous-même');
    if (!db.prepare('SELECT 1 FROM users WHERE id_user = ? AND actif = 1').get(dest)) throw notFound('Destinataire introuvable');
    const contenu = String(req.body.contenu).trim().slice(0, 2000);
    const { lastInsertRowid } = db
      .prepare('INSERT INTO messagerie (id_expediteur, id_destinataire, sujet, contenu) VALUES (?, ?, ?, ?)')
      .run(req.user.id_user, dest, req.body.sujet || null, contenu);
    notifier.notify(dest, 'message', `Message de ${req.user.prenom}`, contenu.slice(0, 80));
    res.status(201).json(db.prepare('SELECT * FROM messagerie WHERE id_messagerie = ?').get(lastInsertRowid));
  });

  return router;
}

// --- Notifications ------------------------------------------------------------
function notificationsRoutes({ db }) {
  const router = express.Router();
  router.use(authenticate(db));

  router.get('/', (req, res) => {
    const items = db
      .prepare('SELECT * FROM notifications WHERE id_user = ? ORDER BY id_notification DESC LIMIT 100')
      .all(req.user.id_user)
      .map((n) => ({ ...n, lu: Boolean(n.lu) }));
    res.json({ non_lues: items.filter((n) => !n.lu).length, items });
  });

  router.post('/tout-lu', (req, res) => {
    db.prepare('UPDATE notifications SET lu = 1 WHERE id_user = ?').run(req.user.id_user);
    res.json({ ok: true });
  });

  router.post('/:id/lu', (req, res) => {
    db.prepare('UPDATE notifications SET lu = 1 WHERE id_notification = ? AND id_user = ?').run(toInt(req.params.id, 'id'), req.user.id_user);
    res.json({ ok: true });
  });

  return router;
}

module.exports = { messagesRoutes, notificationsRoutes };

const { PERMISSIONS } = require('../constants');

/**
 * Cas « Envoi des notifications » : sur un évènement, le système génère le
 * message, sélectionne les canaux, l'envoie et enregistre le log d'envoi.
 *
 * Les canaux SMS/Email sont des passerelles injectables ; par défaut elles
 * journalisent l'envoi (à remplacer par un vrai fournisseur en production).
 */
function createNotifier(db, { gateways } = {}) {
  const channels = gateways || {
    sms: async (to, text) => ({ ok: Boolean(to), info: `SMS -> ${to}: ${text}` }),
    email: async (to, text) => ({ ok: Boolean(to), info: `EMAIL -> ${to}: ${text}` }),
  };

  const insertNotif = db.prepare('INSERT INTO notifications (id_user, type, titre, message) VALUES (?, ?, ?, ?)');
  const insertLog = db.prepare(
    'INSERT INTO notification_logs (id_notification, canal, destinataire, statut) VALUES (?, ?, ?, ?)',
  );

  function notify(idUser, type, titre, message) {
    const user = db.prepare('SELECT telephone, email FROM users WHERE id_user = ?').get(idUser);
    if (!user) return;
    const { lastInsertRowid } = insertNotif.run(idUser, type, titre, message);
    const id = Number(lastInsertRowid);
    insertLog.run(id, 'in_app', String(idUser), 'envoye');

    const text = `${titre} - ${message}`;
    const sends = [['sms', user.telephone]];
    if (user.email) sends.push(['email', user.email]);
    for (const [canal, to] of sends) {
      Promise.resolve()
        .then(() => channels[canal](to, text))
        .then((r) => insertLog.run(id, canal, to, r.ok ? 'envoye' : 'echec'))
        .catch(() => {
          try {
            insertLog.run(id, canal, to, 'echec');
          } catch {
            /* base fermée (arrêt) */
          }
        });
    }
    return id;
  }

  function notifyPermission(permission, type, titre, message) {
    const ids = db
      .prepare(
        `SELECT DISTINCT u.id_user FROM users u
         JOIN user_roles ur ON ur.id_user = u.id_user
         JOIN role_permissions rp ON rp.id_role = ur.id_role
         JOIN permissions p ON p.id_permission = rp.id_permission
         WHERE p.nom = ? AND u.actif = 1`,
      )
      .all(permission);
    ids.forEach(({ id_user }) => notify(id_user, type, titre, message));
  }

  const notifyAdmins = (type, titre, message) => notifyPermission(PERMISSIONS.COMMANDES_GERER, type, titre, message);

  return { notify, notifyPermission, notifyAdmins };
}

module.exports = { createNotifier };

/** Journal d'activité : qui a fait quoi, quand et depuis quelle adresse. */
function journaliser(db, req, action, details, idUser = req?.user?.id_user) {
  db.prepare('INSERT INTO journal_activite (id_user, action, details, ip) VALUES (?, ?, ?, ?)').run(
    idUser ?? null,
    action,
    details === undefined || details === null ? null : typeof details === 'string' ? details : JSON.stringify(details),
    req?.ip ?? null,
  );
}

module.exports = { journaliser };

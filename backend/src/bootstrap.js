const { DEFAULT_ROLES, PERMISSION_DESCRIPTIONS } = require('./constants');

/** Garantit la présence des rôles, permissions et règle de livraison par défaut. */
function ensureDefaults(db) {
  const insPerm = db.prepare('INSERT OR IGNORE INTO permissions (nom, description) VALUES (?, ?)');
  Object.entries(PERMISSION_DESCRIPTIONS).forEach(([nom, desc]) => insPerm.run(nom, desc));

  const insRole = db.prepare('INSERT OR IGNORE INTO roles (nom, description) VALUES (?, ?)');
  const link = db.prepare(
    `INSERT OR IGNORE INTO role_permissions (id_role, id_permission)
     SELECT r.id_role, p.id_permission FROM roles r, permissions p WHERE r.nom = ? AND p.nom = ?`,
  );
  for (const [nom, { description, permissions }] of Object.entries(DEFAULT_ROLES)) {
    const { changes } = insRole.run(nom, description);
    // Les permissions par défaut ne sont posées qu'à la création du rôle,
    // pour respecter les modifications faites ensuite par l'administrateur.
    if (changes) permissions.forEach((p) => link.run(nom, p));
  }
  // Le rôle admin conserve toujours toutes les permissions.
  Object.keys(PERMISSION_DESCRIPTIONS).forEach((p) => link.run('admin', p));

  db.prepare("INSERT OR IGNORE INTO regles_livraison (ville, frais, seuil_gratuite) VALUES ('*', 2000, 100000)").run();
}

module.exports = { ensureDefaults };

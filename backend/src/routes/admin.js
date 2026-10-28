const express = require('express');
const { authenticate, requirePermission, loadRolesAndPermissions } = require('../middleware/auth');
const { badRequest, forbidden, notFound, conflict, requireFields, toInt } = require('../errors');
const { transaction } = require('../db');
const { PERMISSIONS, STATUT, STATUT_LIBELLES, STATUTS_PAYES } = require('../constants');
const { journaliser } = require('../services/journal');
const { detailCommande } = require('./commandes');
const { DEFAUTS_PARAMETRES, lireParametres, ecrireParametre } = require('../services/parametres');

const perm = requirePermission;

function adminRoutes({ db, commerce, notifier }) {
  const router = express.Router();
  router.use(authenticate(db));

  // --- Utilisateurs -------------------------------------------------------------
  router.get('/utilisateurs', perm(PERMISSIONS.UTILISATEURS_GERER), (req, res) => {
    const q = `%${(req.query.q || '').trim()}%`;
    const rows = db
      .prepare(
        `SELECT id_user, nom, prenom, email, telephone, adresse, actif, derniere_connexion, date_creation FROM users
         WHERE nom LIKE ? OR prenom LIKE ? OR telephone LIKE ? OR COALESCE(email, '') LIKE ?
         ORDER BY date_creation DESC, id_user DESC`,
      )
      .all(q, q, q, q)
      .map((u) => ({ ...u, actif: Boolean(u.actif), roles: loadRolesAndPermissions(db, u.id_user).roles }))
      .filter((u) => !req.query.role || u.roles.includes(req.query.role));
    res.json(rows);
  });

  // --- Paramètres de la plateforme -------------------------------------------------
  router.get('/parametres', perm(PERMISSIONS.UTILISATEURS_GERER), (_req, res) => res.json(lireParametres(db)));

  router.put('/parametres', perm(PERMISSIONS.UTILISATEURS_GERER), (req, res) => {
    const inconnus = Object.keys(req.body).filter((cle) => !Object.hasOwn(DEFAUTS_PARAMETRES, cle));
    if (inconnus.length) throw badRequest(`Paramètre inconnu : ${inconnus.join(', ')}`);
    for (const [cle, valeur] of Object.entries(req.body)) {
      if (typeof valeur !== 'boolean') throw badRequest(`Valeur invalide pour ${cle} (true ou false attendu)`);
    }
    transaction(db, () => Object.entries(req.body).forEach(([cle, valeur]) => ecrireParametre(db, cle, valeur)));
    journaliser(db, req, 'parametres.modifier', req.body);
    res.json(lireParametres(db));
  });

  // Livreurs actifs, pour l'assignation d'une commande.
  router.get('/livreurs', perm(PERMISSIONS.COMMANDES_GERER), (_req, res) => {
    const rows = db
      .prepare(
        `SELECT DISTINCT u.id_user, u.nom, u.prenom, u.telephone, u.actif FROM users u
         JOIN user_roles ur ON ur.id_user = u.id_user JOIN role_permissions rp ON rp.id_role = ur.id_role
         JOIN permissions p ON p.id_permission = rp.id_permission
         WHERE p.nom = ? AND u.actif = 1 ORDER BY u.prenom, u.nom`,
      )
      .all(PERMISSIONS.LIVRAISONS_EFFECTUER)
      .map((u) => ({ ...u, actif: Boolean(u.actif) }));
    res.json(rows);
  });

  // Activer ou désactiver un compte.
  router.patch('/utilisateurs/:id/actif', perm(PERMISSIONS.UTILISATEURS_GERER), (req, res) => {
    const id = toInt(req.params.id, 'id');
    if (id === req.user.id_user) throw badRequest('Vous ne pouvez pas désactiver votre propre compte');
    const actif = Boolean(req.body.actif);
    const { changes } = db
      .prepare('UPDATE users SET actif = ?, token_version = token_version + ? WHERE id_user = ?')
      .run(actif ? 1 : 0, actif ? 0 : 1, id);
    if (!changes) throw notFound('Utilisateur introuvable');
    journaliser(db, req, actif ? 'utilisateur.activer' : 'utilisateur.desactiver', { id_user: id });
    res.json({ id_user: id, actif });
  });

  // Attribution granulaire des rôles.
  router.put('/utilisateurs/:id/roles', perm(PERMISSIONS.ROLES_GERER), (req, res) => {
    const id = toInt(req.params.id, 'id');
    const roles = req.body.roles;
    if (!Array.isArray(roles) || !roles.length) throw badRequest('Au moins un rôle est requis');
    if (!db.prepare('SELECT 1 FROM users WHERE id_user = ?').get(id)) throw notFound('Utilisateur introuvable');
    const ids = roles.map((nom) => {
      const r = db.prepare('SELECT id_role FROM roles WHERE nom = ?').get(nom);
      if (!r) throw badRequest(`Rôle inconnu : ${nom}`);
      return r.id_role;
    });
    if (id === req.user.id_user && !roles.includes('admin') && req.user.roles.includes('admin')) {
      throw badRequest('Vous ne pouvez pas retirer votre propre rôle administrateur');
    }
    transaction(db, () => {
      db.prepare('DELETE FROM user_roles WHERE id_user = ?').run(id);
      ids.forEach((r) => db.prepare('INSERT INTO user_roles (id_user, id_role) VALUES (?, ?)').run(id, r));
    });
    journaliser(db, req, 'utilisateur.roles', { id_user: id, roles });
    res.json({ id_user: id, ...loadRolesAndPermissions(db, id) });
  });

  // --- Rôles & permissions ----------------------------------------------------------
  router.get('/permissions', perm(PERMISSIONS.ROLES_GERER), (_req, res) => {
    res.json(db.prepare('SELECT * FROM permissions ORDER BY nom').all());
  });

  const roleAvecPermissions = (r) => ({
    ...r,
    permissions: db
      .prepare('SELECT p.nom FROM permissions p JOIN role_permissions rp ON rp.id_permission = p.id_permission WHERE rp.id_role = ? ORDER BY p.nom')
      .all(r.id_role)
      .map((p) => p.nom),
  });

  router.get('/roles', perm(PERMISSIONS.ROLES_GERER, PERMISSIONS.UTILISATEURS_GERER), (_req, res) => {
    res.json(db.prepare('SELECT * FROM roles ORDER BY id_role').all().map(roleAvecPermissions));
  });

  router.post('/roles', perm(PERMISSIONS.ROLES_GERER), (req, res) => {
    requireFields(req.body, ['nom']);
    const nom = String(req.body.nom).trim().toLowerCase();
    if (db.prepare('SELECT 1 FROM roles WHERE nom = ?').get(nom)) throw conflict('Rôle existant');
    const { lastInsertRowid } = db.prepare('INSERT INTO roles (nom, description) VALUES (?, ?)').run(nom, req.body.description || null);
    journaliser(db, req, 'role.creer', { nom });
    res.status(201).json(roleAvecPermissions(db.prepare('SELECT * FROM roles WHERE id_role = ?').get(lastInsertRowid)));
  });

  router.put('/roles/:id/permissions', perm(PERMISSIONS.ROLES_GERER), (req, res) => {
    const role = db.prepare('SELECT * FROM roles WHERE id_role = ?').get(toInt(req.params.id, 'id'));
    if (!role) throw notFound('Rôle introuvable');
    if (role.nom === 'admin') throw forbidden('Les permissions du rôle admin ne sont pas modifiables');
    const perms = req.body.permissions;
    if (!Array.isArray(perms)) throw badRequest('permissions doit être une liste');
    transaction(db, () => {
      db.prepare('DELETE FROM role_permissions WHERE id_role = ?').run(role.id_role);
      for (const nom of perms) {
        const p = db.prepare('SELECT id_permission FROM permissions WHERE nom = ?').get(nom);
        if (!p) throw badRequest(`Permission inconnue : ${nom}`);
        db.prepare('INSERT INTO role_permissions (id_role, id_permission) VALUES (?, ?)').run(role.id_role, p.id_permission);
      }
    });
    journaliser(db, req, 'role.permissions', { role: role.nom, permissions: perms });
    res.json(roleAvecPermissions(role));
  });

  // --- Commandes ----------------------------------------------------------------------
  // Filtres : statut (un ou plusieurs, séparés par des virgules), q (n°, client, téléphone),
  // du / au (dates AAAA-MM-JJ), ville, id_livreur.
  router.get('/commandes', perm(PERMISSIONS.COMMANDES_GERER), (req, res) => {
    const params = [];
    let where = '1 = 1';
    const statuts = String(req.query.statut || '').split(',').map((v) => v.trim()).filter(Boolean);
    if (statuts.length) {
      where += ` AND c.statut_commande IN (${statuts.map(() => '?').join(', ')})`;
      params.push(...statuts);
    }
    const brut = String(req.query.q || '').trim();
    const q = brut.replace(/^#/, '');
    if (brut.startsWith('#')) {
      // « #12 » : recherche par numéro de commande uniquement.
      where += ' AND c.id_commande = ?';
      params.push(toInt(q, 'q'));
    } else if (q) {
      where += " AND (CAST(c.id_commande AS TEXT) = ? OR (u.prenom || ' ' || u.nom) LIKE ? OR u.telephone LIKE ? OR c.telephone_livraison LIKE ?)";
      params.push(q, `%${q}%`, `%${q}%`, `%${q}%`);
    }
    for (const [cle, op] of [['du', '>='], ['au', '<=']]) {
      if (!req.query[cle]) continue;
      if (!/^\d{4}-\d{2}-\d{2}$/.test(req.query[cle]) || Number.isNaN(Date.parse(req.query[cle]))) throw badRequest(`Date « ${cle} » invalide (AAAA-MM-JJ)`);
      where += ` AND date(c.date_commande) ${op} ?`;
      params.push(req.query[cle]);
    }
    if (req.query.ville) {
      where += ' AND c.ville = ? COLLATE NOCASE';
      params.push(String(req.query.ville).trim());
    }
    if (req.query.id_livreur) {
      where += ' AND c.id_livreur = ?';
      params.push(toInt(req.query.id_livreur, 'id_livreur'));
    }
    const rows = db
      .prepare(
        `SELECT c.*, u.nom AS client_nom, u.prenom AS client_prenom, l.prenom AS livreur_prenom, l.nom AS livreur_nom
         FROM commandes c JOIN users u ON u.id_user = c.id_user LEFT JOIN users l ON l.id_user = c.id_livreur
         WHERE ${where} ORDER BY c.date_commande DESC, c.id_commande DESC LIMIT 200`,
      )
      .all(...params)
      .map((c) => ({ ...c, libelle_statut: STATUT_LIBELLES[c.statut_commande] || c.statut_commande }));
    res.json(rows);
  });

  // Transitions autorisées pour la mise à jour manuelle du statut.
  // Reçue -> Confirmée : validation manuelle (ex. paiement à la livraison).
  const TRANSITIONS = {
    [STATUT.EN_ATTENTE_PAIEMENT]: [STATUT.EN_COURS, STATUT.ANNULEE],
    [STATUT.EN_COURS]: [STATUT.EN_PREPARATION, STATUT.EN_LIVRAISON, STATUT.ANNULEE],
    [STATUT.EN_PREPARATION]: [STATUT.EN_LIVRAISON, STATUT.EN_COURS, STATUT.ANNULEE],
    [STATUT.EN_LIVRAISON]: [STATUT.LIVREE, STATUT.ECHEC_LIVRAISON, STATUT.EN_PREPARATION],
    [STATUT.ECHEC_LIVRAISON]: [STATUT.EN_PREPARATION, STATUT.EN_LIVRAISON, STATUT.ANNULEE],
    [STATUT.LIVREE]: [STATUT.CLOTUREE],
    [STATUT.CLOTUREE]: [],
    [STATUT.ANNULEE]: [],
  };
  const estLivreurActif = (idUser) =>
    loadRolesAndPermissions(db, idUser).permissions.includes(PERMISSIONS.LIVRAISONS_EFFECTUER) &&
    Boolean(db.prepare('SELECT 1 FROM users WHERE id_user = ? AND actif = 1').get(idUser));

  router.patch('/commandes/:id/statut', perm(PERMISSIONS.COMMANDES_GERER), (req, res) => {
    const id = toInt(req.params.id, 'id');
    const commande = db.prepare('SELECT * FROM commandes WHERE id_commande = ?').get(id);
    if (!commande) throw notFound('Commande introuvable');
    const { statut } = req.body;
    if (!(TRANSITIONS[commande.statut_commande] || []).includes(statut)) {
      throw conflict(`Transition interdite : ${commande.statut_commande} → ${statut}`);
    }
    // Un paiement en attente pourrait encore aboutir (débit sur une commande annulée, ou double validation).
    if ([STATUT.ANNULEE, STATUT.EN_COURS].includes(statut) && commande.statut_commande === STATUT.EN_ATTENTE_PAIEMENT && db.prepare("SELECT 1 FROM payements WHERE id_commande = ? AND statut_paie = 'en_attente'").get(id)) {
      throw conflict('Un paiement est en cours de traitement');
    }
    let idLivreur = commande.id_livreur;
    if (statut === STATUT.EN_LIVRAISON) {
      idLivreur = req.body.id_livreur ? toInt(req.body.id_livreur, 'id_livreur') : commande.id_livreur;
      if (!idLivreur) throw badRequest('Un livreur doit être assigné');
      if (!estLivreurActif(idLivreur)) throw badRequest('Cet utilisateur n’est pas un livreur actif');
    }
    // Retour en préparation après une tournée : la commande est libérée pour une nouvelle affectation.
    const retourDeTournee = [STATUT.EN_LIVRAISON, STATUT.ECHEC_LIVRAISON].includes(commande.statut_commande);
    if ([STATUT.EN_COURS, STATUT.EN_PREPARATION].includes(statut) && retourDeTournee) idLivreur = null;

    transaction(db, () => {
      db.prepare(
        `UPDATE commandes SET statut_commande = ?, id_livreur = ?,
           date_livraison = CASE WHEN ? = 'livree' THEN datetime('now') ELSE date_livraison END,
           motif_echec = CASE WHEN ? = 'echec_livraison' THEN ? ELSE motif_echec END
         WHERE id_commande = ?`,
      ).run(statut, idLivreur, statut, statut, req.body.motif || 'Signalé par l’administrateur', id);
      if (statut === STATUT.ANNULEE) commerce.restituerStock(id);
    });

    commerce.suivreStatut(id, statut, {
      auteur: req.user.id_user,
      commentaire: req.body.commentaire || (statut === STATUT.ECHEC_LIVRAISON ? req.body.motif : null) || 'Mis à jour par l’administrateur',
    });
    if (statut === STATUT.EN_LIVRAISON && idLivreur !== commande.id_livreur) {
      notifier.notify(idLivreur, 'livraison', 'Livraison assignée', `La commande #${id} vous a été assignée.`);
    }
    journaliser(db, req, 'commande.statut', { id_commande: id, de: commande.statut_commande, vers: statut });
    res.json(detailCommande(db, id));
  });

  // Affecter (ou retirer) un livreur sans démarrer la livraison : il la démarre depuis son application.
  router.patch('/commandes/:id/livreur', perm(PERMISSIONS.COMMANDES_GERER), (req, res) => {
    const id = toInt(req.params.id, 'id');
    const commande = db.prepare('SELECT * FROM commandes WHERE id_commande = ?').get(id);
    if (!commande) throw notFound('Commande introuvable');
    const modifiables = [STATUT.EN_COURS, STATUT.EN_PREPARATION, STATUT.ECHEC_LIVRAISON];
    if (!modifiables.includes(commande.statut_commande)) {
      throw conflict('Le livreur ne peut être changé que sur une commande confirmée, en préparation ou en échec de livraison');
    }
    const idLivreur = req.body.id_livreur === null || req.body.id_livreur === undefined ? null : toInt(req.body.id_livreur, 'id_livreur');
    if (idLivreur && !estLivreurActif(idLivreur)) throw badRequest('Cet utilisateur n’est pas un livreur actif');
    // Échec de livraison : la commande repart en préparation pour la nouvelle tournée.
    const statut = commande.statut_commande === STATUT.ECHEC_LIVRAISON ? STATUT.EN_PREPARATION : commande.statut_commande;
    db.prepare('UPDATE commandes SET id_livreur = ?, statut_commande = ? WHERE id_commande = ?').run(idLivreur, statut, id);
    const livreur = idLivreur && db.prepare('SELECT prenom, nom FROM users WHERE id_user = ?').get(idLivreur);
    if (statut !== commande.statut_commande) {
      commerce.suivreStatut(id, statut, { auteur: req.user.id_user, commentaire: 'Nouvelle tentative de livraison' });
    }
    if (idLivreur && idLivreur !== commande.id_livreur) {
      notifier.notify(idLivreur, 'livraison', 'Livraison assignée', `La commande #${id} (${commande.ville}) vous a été assignée.`);
    }
    if (commande.id_livreur && commande.id_livreur !== idLivreur) {
      notifier.notify(commande.id_livreur, 'livraison', 'Livraison retirée', `La commande #${id} ne vous est plus assignée.`);
    }
    db.prepare('INSERT INTO commande_historique (id_commande, statut, commentaire, id_auteur) VALUES (?, ?, ?, ?)').run(
      id,
      statut,
      livreur ? `Livreur affecté : ${livreur.prenom} ${livreur.nom}` : 'Livreur retiré',
      req.user.id_user,
    );
    journaliser(db, req, 'commande.livreur', { id_commande: id, id_livreur: idLivreur });
    res.json(detailCommande(db, id));
  });

  // --- Paiements -----------------------------------------------------------------------
  router.get('/paiements', perm(PERMISSIONS.PAIEMENTS_VOIR), (req, res) => {
    const params = [];
    let where = '1 = 1';
    if (req.query.statut) {
      where += ' AND py.statut_paie = ?';
      params.push(req.query.statut);
    }
    const rows = db
      .prepare(
        `SELECT py.*, f.numero_facture, u.nom AS client_nom, u.prenom AS client_prenom
         FROM payements py JOIN commandes c ON c.id_commande = py.id_commande JOIN users u ON u.id_user = c.id_user
         LEFT JOIN factures f ON f.id_payement = py.id_payement
         WHERE ${where} ORDER BY py.id_payement DESC LIMIT 200`,
      )
      .all(...params);
    res.json(rows);
  });

  // --- Boutiques ----------------------------------------------------------------------
  router.get('/boutiques', perm(PERMISSIONS.UTILISATEURS_GERER), (_req, res) => {
    const rows = db
      .prepare(
        `SELECT b.*, u.nom AS vendeur_nom, u.prenom AS vendeur_prenom,
                (SELECT COUNT(*) FROM produits p WHERE p.id_boutique = b.id_boutique) AS nb_produits
         FROM boutiques b JOIN users u ON u.id_user = b.id_vendeur ORDER BY b.date_creation DESC`,
      )
      .all()
      .map((b) => ({ ...b, active: Boolean(b.active) }));
    res.json(rows);
  });

  router.patch('/boutiques/:id/active', perm(PERMISSIONS.UTILISATEURS_GERER), (req, res) => {
    const id = toInt(req.params.id, 'id');
    const { changes } = db.prepare('UPDATE boutiques SET active = ? WHERE id_boutique = ?').run(req.body.active ? 1 : 0, id);
    if (!changes) throw notFound('Boutique introuvable');
    journaliser(db, req, req.body.active ? 'boutique.activer' : 'boutique.desactiver', { id_boutique: id });
    res.json({ id_boutique: id, active: Boolean(req.body.active) });
  });

  // --- Règles de livraison ------------------------------------------------------------------
  router.get('/regles-livraison', perm(PERMISSIONS.LIVRAISON_REGLES), (_req, res) => {
    res.json(db.prepare("SELECT * FROM regles_livraison ORDER BY ville = '*' DESC, ville").all());
  });

  router.post('/regles-livraison', perm(PERMISSIONS.LIVRAISON_REGLES), (req, res) => {
    requireFields(req.body, ['ville', 'frais']);
    const frais = toInt(req.body.frais, 'frais', { min: 0 });
    const seuil = req.body.seuil_gratuite === null || req.body.seuil_gratuite === undefined || req.body.seuil_gratuite === ''
      ? null
      : toInt(req.body.seuil_gratuite, 'seuil_gratuite', { min: 0 });
    db.prepare(
      `INSERT INTO regles_livraison (ville, frais, seuil_gratuite) VALUES (?, ?, ?)
       ON CONFLICT (ville) DO UPDATE SET frais = excluded.frais, seuil_gratuite = excluded.seuil_gratuite`,
    ).run(String(req.body.ville).trim(), frais, seuil);
    journaliser(db, req, 'livraison.regle', { ville: String(req.body.ville).trim(), frais, seuil_gratuite: seuil });
    res.status(201).json(db.prepare('SELECT * FROM regles_livraison WHERE ville = ?').get(String(req.body.ville).trim()));
  });

  router.delete('/regles-livraison/:id', perm(PERMISSIONS.LIVRAISON_REGLES), (req, res) => {
    const regle = db.prepare('SELECT * FROM regles_livraison WHERE id_regle = ?').get(toInt(req.params.id, 'id'));
    if (!regle) throw notFound('Règle introuvable');
    if (regle.ville === '*') throw badRequest('La règle par défaut ne peut pas être supprimée');
    db.prepare('DELETE FROM regles_livraison WHERE id_regle = ?').run(regle.id_regle);
    journaliser(db, req, 'livraison.regle.supprimer', { ville: regle.ville });
    res.status(204).end();
  });

  // --- Statistiques des ventes -----------------------------------------------------------------
  router.get('/statistiques', perm(PERMISSIONS.STATISTIQUES_VOIR), (_req, res) => {
    const payees = `c.statut_commande IN (${STATUTS_PAYES.map((st) => `'${st}'`).join(', ')})`;
    const one = (sql, ...p) => db.prepare(sql).get(...p);
    const aujourdhui = "date(c.date_commande, 'localtime') = date('now', 'localtime')";
    res.json({
      // Tableau de bord du jour.
      commandes_jour: one(`SELECT COUNT(*) AS v FROM commandes c WHERE ${aujourdhui}`).v,
      chiffre_affaires_jour: one(`SELECT COALESCE(SUM(total_commande), 0) AS v FROM commandes c WHERE ${payees} AND ${aujourdhui}`).v,
      chiffre_affaires_mois: one(
        `SELECT COALESCE(SUM(total_commande), 0) AS v FROM commandes c
         WHERE ${payees} AND strftime('%Y-%m', c.date_commande, 'localtime') = strftime('%Y-%m', 'now', 'localtime')`,
      ).v,
      livraisons_en_cours: one('SELECT COUNT(*) AS v FROM commandes WHERE statut_commande = ?', STATUT.EN_LIVRAISON).v,
      a_preparer: one('SELECT COUNT(*) AS v FROM commandes WHERE statut_commande IN (?, ?)', STATUT.EN_COURS, STATUT.EN_PREPARATION).v,
      en_attente_paiement: one('SELECT COUNT(*) AS v FROM commandes WHERE statut_commande = ?', STATUT.EN_ATTENTE_PAIEMENT).v,
      echecs_livraison: one('SELECT COUNT(*) AS v FROM commandes WHERE statut_commande = ?', STATUT.ECHEC_LIVRAISON).v,
      chiffre_affaires: one(`SELECT COALESCE(SUM(total_commande), 0) AS v FROM commandes c WHERE ${payees}`).v,
      nb_commandes: one('SELECT COUNT(*) AS v FROM commandes').v,
      nb_clients: one('SELECT COUNT(*) AS v FROM users').v,
      nb_produits: one("SELECT COUNT(*) AS v FROM produits WHERE statut = 'publie'").v,
      panier_moyen: one(`SELECT COALESCE(ROUND(AVG(total_commande)), 0) AS v FROM commandes c WHERE ${payees}`).v,
      commandes_par_statut: db.prepare('SELECT statut_commande AS statut, COUNT(*) AS nombre FROM commandes GROUP BY statut_commande').all(),
      ventes_par_jour: db
        .prepare(
          `SELECT date(c.date_commande) AS jour, COUNT(*) AS commandes, SUM(c.total_commande) AS montant
           FROM commandes c WHERE ${payees} AND c.date_commande >= date('now', '-30 days')
           GROUP BY jour ORDER BY jour`,
        )
        .all(),
      top_produits: db
        .prepare(
          `SELECT ci.id_produit, ci.nom_produit AS nom, SUM(ci.quantite) AS quantite, SUM(ci.quantite * ci.prix_unitaire) AS montant
           FROM commande_items ci JOIN commandes c ON c.id_commande = ci.id_commande
           WHERE ${payees} GROUP BY ci.id_produit ORDER BY quantite DESC LIMIT 5`,
        )
        .all(),
      stock_bas: db
        .prepare("SELECT id_produit, nom, quantite_stock FROM produits WHERE statut = 'publie' AND quantite_stock <= 5 ORDER BY quantite_stock LIMIT 10")
        .all(),
    });
  });

  // --- Journal d'activité ---------------------------------------------------------------------
  router.get('/journal', perm(PERMISSIONS.JOURNAL_VOIR), (req, res) => {
    const params = [];
    let where = '1 = 1';
    if (req.query.action) {
      where += ' AND j.action LIKE ?';
      params.push(`${String(req.query.action).trim()}%`);
    }
    if (req.query.id_user) {
      where += ' AND j.id_user = ?';
      params.push(toInt(req.query.id_user, 'id_user'));
    }
    const limite = Math.min(toInt(req.query.limite ?? 100, 'limite', { min: 1 }), 500);
    const avant = req.query.avant ? toInt(req.query.avant, 'avant') : null;
    if (avant) {
      where += ' AND j.id_journal < ?';
      params.push(avant);
    }
    const rows = db
      .prepare(
        `SELECT j.*, u.prenom, u.nom, u.telephone FROM journal_activite j LEFT JOIN users u ON u.id_user = j.id_user
         WHERE ${where} ORDER BY j.id_journal DESC LIMIT ?`,
      )
      .all(...params, limite);
    res.json(rows);
  });

  return router;
}

module.exports = { adminRoutes };

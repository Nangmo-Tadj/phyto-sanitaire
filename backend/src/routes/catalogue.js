const express = require('express');
const { authenticate, requirePermission, hasPermission } = require('../middleware/auth');
const { badRequest, forbidden, notFound, conflict, requireFields, toInt } = require('../errors');
const { PERMISSIONS, STATUT } = require('../constants');
const { lireParametres } = require('../services/parametres');

const PRODUIT_SELECT = `
  SELECT p.*, c.nom AS categorie, c.type AS type_categorie,
         b.nom AS boutique, b.ville AS ville_boutique, b.id_vendeur, b.telephone AS telephone_boutique,
         COALESCE(ROUND(a.moyenne, 1), 0) AS note_moyenne, COALESCE(a.nb, 0) AS nb_avis
  FROM produits p
  JOIN categories c ON c.id_categorie = p.id_categorie
  LEFT JOIN boutiques b ON b.id_boutique = p.id_boutique
  LEFT JOIN (SELECT id_produit, AVG(note_avis) AS moyenne, COUNT(*) AS nb FROM avis
             WHERE id_produit IS NOT NULL GROUP BY id_produit) a ON a.id_produit = p.id_produit`;

const VISIBLE = "p.statut = 'publie' AND (b.id_boutique IS NULL OR b.active = 1)";

// --- Catégories -----------------------------------------------------------
function categoriesRoutes({ db }) {
  const router = express.Router();

  // Recherche des catégories des produits.
  router.get('/', (req, res) => {
    const q = `%${(req.query.q || '').trim()}%`;
    const params = [q];
    let where = 'c.nom LIKE ?';
    if (req.query.type) {
      where += ' AND c.type = ?';
      params.push(req.query.type);
    }
    const rows = db
      .prepare(
        `SELECT c.*, (SELECT COUNT(*) FROM produits p LEFT JOIN boutiques b ON b.id_boutique = p.id_boutique
                      WHERE p.id_categorie = c.id_categorie AND ${VISIBLE}) AS nb_produits
         FROM categories c WHERE ${where} ORDER BY c.type, c.nom`,
      )
      .all(...params);
    res.json(rows);
  });

  const gerer = [authenticate(db), requirePermission(PERMISSIONS.CATEGORIES_GERER)];

  function valider(body) {
    requireFields(body, ['nom']);
    const type = body.type || 'phytosanitaire';
    if (!['phytosanitaire', 'elevage'].includes(type)) throw badRequest('Type de catégorie invalide');
    return [String(body.nom).trim(), body.description || null, type];
  }

  router.post('/', ...gerer, (req, res) => {
    const [nom, description, type] = valider(req.body);
    if (db.prepare('SELECT 1 FROM categories WHERE nom = ?').get(nom)) throw conflict('Catégorie existante');
    const { lastInsertRowid } = db
      .prepare('INSERT INTO categories (nom, description, type) VALUES (?, ?, ?)')
      .run(nom, description, type);
    res.status(201).json(db.prepare('SELECT * FROM categories WHERE id_categorie = ?').get(lastInsertRowid));
  });

  router.put('/:id', ...gerer, (req, res) => {
    const [nom, description, type] = valider(req.body);
    const id = toInt(req.params.id, 'id');
    if (!db.prepare('SELECT 1 FROM categories WHERE id_categorie = ?').get(id)) throw notFound('Catégorie introuvable');
    if (db.prepare('SELECT 1 FROM categories WHERE nom = ? AND id_categorie <> ?').get(nom, id)) {
      throw conflict('Catégorie existante');
    }
    db.prepare('UPDATE categories SET nom = ?, description = ?, type = ? WHERE id_categorie = ?').run(nom, description, type, id);
    res.json(db.prepare('SELECT * FROM categories WHERE id_categorie = ?').get(id));
  });

  router.delete('/:id', ...gerer, (req, res) => {
    const id = toInt(req.params.id, 'id');
    if (db.prepare('SELECT 1 FROM produits WHERE id_categorie = ?').get(id)) {
      throw conflict('Impossible de supprimer une catégorie contenant des produits');
    }
    const { changes } = db.prepare('DELETE FROM categories WHERE id_categorie = ?').run(id);
    if (!changes) throw notFound('Catégorie introuvable');
    res.status(204).end();
  });

  return router;
}

// --- Produits ---------------------------------------------------------------
function produitsRoutes({ db }) {
  const router = express.Router();

  // Rechercher / consulter le catalogue (produits, catégories, prix).
  router.get('/', (req, res) => {
    const where = [VISIBLE];
    const params = [];
    if (req.query.q) {
      where.push('(p.nom LIKE ? OR p.description LIKE ? OR c.nom LIKE ?)');
      const q = `%${req.query.q.trim()}%`;
      params.push(q, q, q);
    }
    if (req.query.categorie) {
      where.push('p.id_categorie = ?');
      params.push(toInt(req.query.categorie, 'categorie'));
    }
    if (req.query.type) {
      where.push('c.type = ?');
      params.push(req.query.type);
    }
    if (req.query.boutique) {
      where.push('p.id_boutique = ?');
      params.push(toInt(req.query.boutique, 'boutique'));
    }
    if (req.query.prix_min) {
      where.push('p.prix_produit >= ?');
      params.push(toInt(req.query.prix_min, 'prix_min', { min: 0 }));
    }
    if (req.query.prix_max) {
      where.push('p.prix_produit <= ?');
      params.push(toInt(req.query.prix_max, 'prix_max', { min: 0 }));
    }
    if (req.query.en_stock === 'true') where.push('p.quantite_stock > 0');

    const tri = {
      prix_asc: 'p.prix_produit ASC',
      prix_desc: 'p.prix_produit DESC',
      note: 'note_moyenne DESC, nb_avis DESC',
      nom: 'p.nom ASC',
    }[req.query.tri] || 'p.date_creation DESC, p.id_produit DESC';

    const limit = Math.min(Number(req.query.limit) || 50, 100);
    const offset = Math.max(Number(req.query.offset) || 0, 0);
    const rows = db
      .prepare(`${PRODUIT_SELECT} WHERE ${where.join(' AND ')} ORDER BY ${tri} LIMIT ? OFFSET ?`)
      .all(...params, limit, offset);
    res.json(rows);
  });

  // Gestion : produits du vendeur connecté (ou tous pour un modérateur), tous statuts.
  router.get('/gestion', authenticate(db), requirePermission(PERMISSIONS.PRODUITS_GERER, PERMISSIONS.PRODUITS_MODERER), (req, res) => {
    const tous = hasPermission(req.user, PERMISSIONS.PRODUITS_MODERER) && req.query.tous !== 'false';
    const rows = tous
      ? db.prepare(`${PRODUIT_SELECT} ORDER BY p.date_modification DESC`).all()
      : db.prepare(`${PRODUIT_SELECT} WHERE b.id_vendeur = ? ORDER BY p.date_modification DESC`).all(req.user.id_user);
    res.json(rows);
  });

  router.get('/:id', authenticate(db, { optional: true }), (req, res) => {
    const produit = db.prepare(`${PRODUIT_SELECT} WHERE p.id_produit = ?`).get(toInt(req.params.id, 'id'));
    if (!produit) throw notFound('Produit introuvable');
    const visible =
      produit.statut === 'publie' ||
      hasPermission(req.user, PERMISSIONS.PRODUITS_MODERER) ||
      (req.user && produit.id_vendeur === req.user.id_user);
    if (!visible) throw notFound('Produit introuvable');
    res.json(produit);
  });

  // --- Avis sur un produit ---
  router.get('/:id/avis', (req, res) => {
    const rows = db
      .prepare(
        `SELECT a.id_avis, a.note_avis, a.commentaire, a.date_avis, u.id_user, u.prenom, SUBSTR(u.nom, 1, 1) || '.' AS nom
         FROM avis a JOIN users u ON u.id_user = a.id_user
         WHERE a.id_produit = ? ORDER BY a.date_avis DESC`,
      )
      .all(toInt(req.params.id, 'id'));
    res.json(rows);
  });

  router.post('/:id/avis', authenticate(db), (req, res) => {
    const id = toInt(req.params.id, 'id');
    const note = toInt(req.body.note_avis, 'note_avis', { min: 1 });
    if (note > 5) throw badRequest('La note doit être comprise entre 1 et 5');
    if (!db.prepare('SELECT 1 FROM produits WHERE id_produit = ?').get(id)) throw notFound('Produit introuvable');
    const achete = db
      .prepare(
        `SELECT 1 FROM commandes c JOIN commande_items ci ON ci.id_commande = c.id_commande
         WHERE c.id_user = ? AND ci.id_produit = ? AND c.statut_commande IN (?, ?, ?)`,
      )
      .get(req.user.id_user, id, STATUT.EN_COURS, STATUT.EN_LIVRAISON, STATUT.LIVREE);
    if (!achete) throw forbidden('Vous devez avoir acheté ce produit pour donner un avis');
    db.prepare(
      `INSERT INTO avis (id_user, id_produit, note_avis, commentaire) VALUES (?, ?, ?, ?)
       ON CONFLICT (id_user, id_produit) WHERE id_produit IS NOT NULL
       DO UPDATE SET note_avis = excluded.note_avis, commentaire = excluded.commentaire, date_avis = datetime('now')`,
    ).run(req.user.id_user, id, note, req.body.commentaire || null);
    res.status(201).json(db.prepare('SELECT * FROM avis WHERE id_user = ? AND id_produit = ?').get(req.user.id_user, id));
  });

  // --- Gestion des produits (diagramme de séquence « Gestion des produits ») ---
  const gerer = [authenticate(db), requirePermission(PERMISSIONS.PRODUITS_GERER, PERMISSIONS.PRODUITS_MODERER)];

  /** Retourne le produit si l'utilisateur peut le gérer. */
  function produitGerable(req) {
    const produit = db
      .prepare('SELECT p.*, b.id_vendeur FROM produits p LEFT JOIN boutiques b ON b.id_boutique = p.id_boutique WHERE p.id_produit = ?')
      .get(toInt(req.params.id, 'id'));
    if (!produit) return null;
    if (!hasPermission(req.user, PERMISSIONS.PRODUITS_MODERER) && produit.id_vendeur !== req.user.id_user) {
      throw forbidden('Ce produit ne vous appartient pas');
    }
    return produit;
  }

  function validerProduit(body, existant = {}) {
    const d = { ...existant, ...body };
    requireFields(d, ['nom', 'id_categorie', 'prix_produit']);
    const statut = d.statut || 'publie';
    if (!['brouillon', 'publie', 'retire'].includes(statut)) throw badRequest('Statut de produit invalide');
    const idCategorie = toInt(d.id_categorie, 'id_categorie');
    if (!db.prepare('SELECT 1 FROM categories WHERE id_categorie = ?').get(idCategorie)) throw badRequest('Catégorie inconnue');
    return {
      nom: String(d.nom).trim(),
      description: d.description || null,
      id_categorie: idCategorie,
      prix_produit: toInt(d.prix_produit, 'prix_produit', { min: 0 }),
      quantite_stock: toInt(d.quantite_stock ?? 0, 'quantite_stock', { min: 0 }),
      unite: d.unite || null,
      image_produit: d.image_produit || null,
      statut,
    };
  }

  router.post('/', ...gerer, (req, res) => {
    let idBoutique = null;
    const boutique = db.prepare('SELECT id_boutique FROM boutiques WHERE id_vendeur = ?').get(req.user.id_user);
    if (boutique) idBoutique = boutique.id_boutique;
    else if (!hasPermission(req.user, PERMISSIONS.PRODUITS_MODERER)) {
      throw badRequest('Créez d’abord votre boutique pour publier des produits');
    }
    const p = validerProduit(req.body);

    const existe = db
      .prepare('SELECT 1 FROM produits WHERE nom = ? COLLATE NOCASE AND id_boutique IS ?')
      .get(p.nom, idBoutique);
    if (existe) throw conflict('Produit existant');

    const { lastInsertRowid } = db
      .prepare(
        `INSERT INTO produits (id_categorie, id_boutique, nom, description, prix_produit, quantite_stock, unite, image_produit, statut)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(p.id_categorie, idBoutique, p.nom, p.description, p.prix_produit, p.quantite_stock, p.unite, p.image_produit, p.statut);
    res.status(201).json(db.prepare(`${PRODUIT_SELECT} WHERE p.id_produit = ?`).get(lastInsertRowid));
  });

  router.put('/:id', ...gerer, (req, res) => {
    const existant = produitGerable(req);
    if (!existant) throw notFound('Produit introuvable');
    const p = validerProduit(req.body, existant);
    const doublon = db
      .prepare('SELECT 1 FROM produits WHERE nom = ? COLLATE NOCASE AND id_boutique IS ? AND id_produit <> ?')
      .get(p.nom, existant.id_boutique, existant.id_produit);
    if (doublon) throw conflict('Produit existant');
    db.prepare(
      `UPDATE produits SET id_categorie = ?, nom = ?, description = ?, prix_produit = ?, quantite_stock = ?, unite = ?,
         image_produit = ?, statut = ?, date_modification = datetime('now') WHERE id_produit = ?`,
    ).run(p.id_categorie, p.nom, p.description, p.prix_produit, p.quantite_stock, p.unite, p.image_produit, p.statut, existant.id_produit);
    res.json(db.prepare(`${PRODUIT_SELECT} WHERE p.id_produit = ?`).get(existant.id_produit));
  });

  // Suivi du stock en temps réel.
  router.patch('/:id/stock', ...gerer, (req, res) => {
    const existant = produitGerable(req);
    if (!existant) throw notFound('Produit introuvable');
    const stock = toInt(req.body.quantite_stock, 'quantite_stock', { min: 0 });
    db.prepare("UPDATE produits SET quantite_stock = ?, date_modification = datetime('now') WHERE id_produit = ?").run(stock, existant.id_produit);
    res.json(db.prepare(`${PRODUIT_SELECT} WHERE p.id_produit = ?`).get(existant.id_produit));
  });

  // Mise en statut des produits & aliments et publication.
  router.patch('/:id/statut', ...gerer, (req, res) => {
    const existant = produitGerable(req);
    if (!existant) throw notFound('Produit introuvable');
    if (!['brouillon', 'publie', 'retire'].includes(req.body.statut)) throw badRequest('Statut de produit invalide');
    db.prepare("UPDATE produits SET statut = ?, date_modification = datetime('now') WHERE id_produit = ?").run(req.body.statut, existant.id_produit);
    res.json(db.prepare(`${PRODUIT_SELECT} WHERE p.id_produit = ?`).get(existant.id_produit));
  });

  router.delete('/:id', ...gerer, (req, res) => {
    const existant = produitGerable(req);
    if (!existant) throw notFound('Suppression impossible : produit absent');
    // Un produit déjà commandé est conservé pour l'historique : on le retire du catalogue.
    const commande = db.prepare('SELECT 1 FROM commande_items WHERE id_produit = ?').get(existant.id_produit);
    if (commande) {
      db.prepare("UPDATE produits SET statut = 'retire', date_modification = datetime('now') WHERE id_produit = ?").run(existant.id_produit);
      return res.json({ message: 'Produit déjà commandé : retiré du catalogue', retire: true });
    }
    db.prepare('DELETE FROM produits WHERE id_produit = ?').run(existant.id_produit);
    res.status(204).end();
  });

  return router;
}

// --- Boutiques ---------------------------------------------------------------
function boutiquesRoutes({ db }) {
  const router = express.Router();
  const vendeur = [authenticate(db)];

  router.get('/moi', ...vendeur, (req, res) => {
    const b = db.prepare('SELECT * FROM boutiques WHERE id_vendeur = ?').get(req.user.id_user);
    if (!b) throw notFound('Aucune boutique');
    res.json(b);
  });

  // Créer la boutique : attribue le rôle vendeur si nécessaire.
  router.post('/', ...vendeur, (req, res) => {
    requireFields(req.body, ['nom']);
    if (db.prepare('SELECT 1 FROM boutiques WHERE id_vendeur = ?').get(req.user.id_user)) {
      throw conflict('Vous avez déjà une boutique');
    }
    if (!lireParametres(db).creation_boutique && !hasPermission(req.user, PERMISSIONS.UTILISATEURS_GERER)) {
      throw forbidden('La création de boutiques est actuellement désactivée par l’administrateur');
    }
    const { nom, description, adresse, ville, telephone } = req.body;
    const { lastInsertRowid } = db
      .prepare('INSERT INTO boutiques (id_vendeur, nom, description, adresse, ville, telephone) VALUES (?, ?, ?, ?, ?, ?)')
      .run(req.user.id_user, nom.trim(), description || null, adresse || null, ville || null, telephone || req.user.telephone);
    db.prepare("INSERT OR IGNORE INTO user_roles (id_user, id_role) SELECT ?, id_role FROM roles WHERE nom = 'vendeur'").run(req.user.id_user);
    res.status(201).json(db.prepare('SELECT * FROM boutiques WHERE id_boutique = ?').get(lastInsertRowid));
  });

  router.put('/moi', ...vendeur, requirePermission(PERMISSIONS.BOUTIQUE_GERER), (req, res) => {
    const b = db.prepare('SELECT * FROM boutiques WHERE id_vendeur = ?').get(req.user.id_user);
    if (!b) throw notFound('Aucune boutique');
    const d = { ...b, ...req.body };
    if (!String(d.nom || '').trim()) throw badRequest('Le nom est obligatoire');
    db.prepare('UPDATE boutiques SET nom = ?, description = ?, adresse = ?, ville = ?, telephone = ? WHERE id_boutique = ?').run(
      d.nom.trim(), d.description, d.adresse, d.ville, d.telephone, b.id_boutique,
    );
    res.json(db.prepare('SELECT * FROM boutiques WHERE id_boutique = ?').get(b.id_boutique));
  });

  // Ventes de la boutique (commandes contenant ses produits).
  router.get('/moi/ventes', ...vendeur, requirePermission(PERMISSIONS.BOUTIQUE_GERER), (req, res) => {
    const rows = db
      .prepare(
        `SELECT c.id_commande, c.date_commande, c.statut_commande, c.ville,
                ci.id_produit, ci.nom_produit, ci.quantite, ci.prix_unitaire, (ci.quantite * ci.prix_unitaire) AS montant
         FROM commande_items ci
         JOIN commandes c ON c.id_commande = ci.id_commande
         JOIN produits p ON p.id_produit = ci.id_produit
         JOIN boutiques b ON b.id_boutique = p.id_boutique
         WHERE b.id_vendeur = ? AND c.statut_commande NOT IN (?, ?)
         ORDER BY c.date_commande DESC`,
      )
      .all(req.user.id_user, STATUT.EN_ATTENTE_PAIEMENT, STATUT.ANNULEE);
    res.json(rows);
  });

  router.get('/:id', (req, res) => {
    const b = db
      .prepare('SELECT id_boutique, id_vendeur, nom, description, adresse, ville, telephone, date_creation FROM boutiques WHERE id_boutique = ? AND active = 1')
      .get(toInt(req.params.id, 'id'));
    if (!b) throw notFound('Boutique introuvable');
    res.json(b);
  });

  return router;
}

module.exports = { categoriesRoutes, produitsRoutes, boutiquesRoutes, PRODUIT_SELECT };

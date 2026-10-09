const express = require('express');
const { authenticate, requirePermission, hasPermission } = require('../middleware/auth');
const { badRequest, forbidden, notFound, conflict, requireFields, toInt } = require('../errors');
const { transaction } = require('../db');
const { PERMISSIONS, STATUT, MODES_PAIEMENT } = require('../constants');
const { newReference } = require('../services/payment');

// --- Panier (cas « Gestion du panier ») --------------------------------------
function panierRoutes({ db, commerce }) {
  const router = express.Router();
  router.use(authenticate(db));

  const touch = (idPanier) =>
    db.prepare("UPDATE paniers SET date_modification = datetime('now') WHERE id_panier = ?").run(idPanier);

  function produitDisponible(idProduit) {
    const p = db
      .prepare(
        `SELECT p.* FROM produits p LEFT JOIN boutiques b ON b.id_boutique = p.id_boutique
         WHERE p.id_produit = ? AND p.statut = 'publie' AND (b.id_boutique IS NULL OR b.active = 1)`,
      )
      .get(idProduit);
    if (!p) throw notFound('Produit indisponible');
    return p;
  }

  router.get('/', (req, res) => res.json(commerce.lirePanier(req.user.id_user, req.query.ville)));

  router.post('/items', (req, res) => {
    const idProduit = toInt(req.body.id_produit, 'id_produit');
    const quantite = toInt(req.body.quantite ?? 1, 'quantite', { min: 1 });
    const produit = produitDisponible(idProduit);
    const idPanier = commerce.panierId(req.user.id_user);
    const actuel = db.prepare('SELECT quantite FROM panier_items WHERE id_panier = ? AND id_produit = ?').get(idPanier, idProduit);
    const total = (actuel?.quantite || 0) + quantite;
    if (total > produit.quantite_stock) {
      throw conflict(`Stock insuffisant (disponible : ${produit.quantite_stock})`);
    }
    db.prepare(
      `INSERT INTO panier_items (id_panier, id_produit, quantite) VALUES (?, ?, ?)
       ON CONFLICT (id_panier, id_produit) DO UPDATE SET quantite = excluded.quantite`,
    ).run(idPanier, idProduit, total);
    touch(idPanier);
    res.status(201).json(commerce.lirePanier(req.user.id_user));
  });

  router.patch('/items/:idProduit', (req, res) => {
    const idProduit = toInt(req.params.idProduit, 'id_produit');
    const quantite = toInt(req.body.quantite, 'quantite', { min: 0 });
    const idPanier = commerce.panierId(req.user.id_user);
    if (quantite === 0) {
      db.prepare('DELETE FROM panier_items WHERE id_panier = ? AND id_produit = ?').run(idPanier, idProduit);
    } else {
      const produit = produitDisponible(idProduit);
      if (quantite > produit.quantite_stock) throw conflict(`Stock insuffisant (disponible : ${produit.quantite_stock})`);
      const { changes } = db
        .prepare('UPDATE panier_items SET quantite = ? WHERE id_panier = ? AND id_produit = ?')
        .run(quantite, idPanier, idProduit);
      if (!changes) throw notFound('Produit absent du panier');
    }
    touch(idPanier);
    res.json(commerce.lirePanier(req.user.id_user));
  });

  router.delete('/items/:idProduit', (req, res) => {
    const idPanier = commerce.panierId(req.user.id_user);
    db.prepare('DELETE FROM panier_items WHERE id_panier = ? AND id_produit = ?').run(idPanier, toInt(req.params.idProduit, 'id_produit'));
    touch(idPanier);
    res.json(commerce.lirePanier(req.user.id_user));
  });

  router.delete('/', (req, res) => {
    const idPanier = commerce.panierId(req.user.id_user);
    db.prepare('DELETE FROM panier_items WHERE id_panier = ?').run(idPanier);
    touch(idPanier);
    res.json(commerce.lirePanier(req.user.id_user));
  });

  return router;
}

// --- Commandes (diagramme de séquence « Passer la commande ») ----------------
function detailCommande(db, idCommande) {
  const commande = db
    .prepare(
      `SELECT c.*, u.nom AS client_nom, u.prenom AS client_prenom, u.telephone AS client_telephone,
              l.nom AS livreur_nom, l.prenom AS livreur_prenom, l.telephone AS livreur_telephone
       FROM commandes c
       JOIN users u ON u.id_user = c.id_user
       LEFT JOIN users l ON l.id_user = c.id_livreur
       WHERE c.id_commande = ?`,
    )
    .get(idCommande);
  if (!commande) return null;
  commande.items = db
    .prepare(
      `SELECT ci.*, p.image_produit, (ci.prix_unitaire * ci.quantite) AS total_ligne
       FROM commande_items ci LEFT JOIN produits p ON p.id_produit = ci.id_produit WHERE ci.id_commande = ?`,
    )
    .all(idCommande);
  commande.paiements = db
    .prepare(
      `SELECT py.*, f.numero_facture, f.date_facture FROM payements py
       LEFT JOIN factures f ON f.id_payement = py.id_payement
       WHERE py.id_commande = ? ORDER BY py.id_payement DESC`,
    )
    .all(idCommande);
  commande.avis = db.prepare('SELECT * FROM avis WHERE id_commande = ?').get(idCommande) || null;
  return commande;
}

function peutVoirCommande(db, user, commande) {
  if (commande.id_user === user.id_user || commande.id_livreur === user.id_user) return true;
  if (hasPermission(user, PERMISSIONS.COMMANDES_GERER)) return true;
  if (hasPermission(user, PERMISSIONS.LIVRAISONS_EFFECTUER) && commande.statut_commande === STATUT.EN_COURS && !commande.id_livreur) {
    return true;
  }
  return Boolean(
    db
      .prepare(
        `SELECT 1 FROM commande_items ci JOIN produits p ON p.id_produit = ci.id_produit
         JOIN boutiques b ON b.id_boutique = p.id_boutique WHERE ci.id_commande = ? AND b.id_vendeur = ?`,
      )
      .get(commande.id_commande, user.id_user),
  );
}

function commandesRoutes({ db, commerce, notifier }) {
  const router = express.Router();
  router.use(authenticate(db));

  function verifierPanier(idUser, ville) {
    const panier = commerce.lirePanier(idUser, ville);
    if (!panier.items.length) throw badRequest('Panier vide');
    const problemes = panier.items
      .filter((i) => !i.disponible || i.quantite > i.quantite_stock)
      .map((i) => ({ id_produit: i.id_produit, nom: i.nom, demande: i.quantite, disponible: i.disponible ? i.quantite_stock : 0 }));
    if (problemes.length) throw conflict('Stock insuffisant', problemes);
    return panier;
  }

  // Récapitulatif : calcul automatique du total et des frais de livraison.
  router.post('/recapitulatif', (req, res) => {
    const panier = verifierPanier(req.user.id_user, req.body.ville);
    res.json(panier);
  });

  // Placer la commande -> statut « en attente de paiement ».
  router.post('/', (req, res) => {
    requireFields(req.body, ['adresse_livraison', 'ville', 'telephone_livraison']);
    const { adresse_livraison, ville, telephone_livraison } = req.body;

    const idCommande = transaction(db, () => {
      const panier = verifierPanier(req.user.id_user, ville);
      const { lastInsertRowid } = db
        .prepare(
          `INSERT INTO commandes (id_user, statut_commande, sous_total, frais_livraison, total_commande,
                                  adresse_livraison, ville, telephone_livraison)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        )
        .run(
          req.user.id_user, STATUT.EN_ATTENTE_PAIEMENT, panier.sous_total, panier.frais_livraison, panier.total,
          adresse_livraison.trim(), ville.trim(), telephone_livraison.trim(),
        );
      const id = Number(lastInsertRowid);
      const insItem = db.prepare(
        'INSERT INTO commande_items (id_commande, id_produit, nom_produit, prix_unitaire, quantite) VALUES (?, ?, ?, ?, ?)',
      );
      const decStock = db.prepare(
        'UPDATE produits SET quantite_stock = quantite_stock - ? WHERE id_produit = ? AND quantite_stock >= ?',
      );
      for (const i of panier.items) {
        insItem.run(id, i.id_produit, i.nom, i.prix_produit, i.quantite);
        if (!decStock.run(i.quantite, i.id_produit, i.quantite).changes) throw conflict('Stock insuffisant');
      }
      db.prepare('DELETE FROM panier_items WHERE id_panier = ?').run(panier.id_panier);
      if (!req.user.adresse) db.prepare('UPDATE users SET adresse = ? WHERE id_user = ?').run(adresse_livraison.trim(), req.user.id_user);
      return id;
    });

    notifier.notify(req.user.id_user, 'commande', 'Commande enregistrée', `Commande #${idCommande} en attente de paiement.`);
    res.status(201).json(detailCommande(db, idCommande));
  });

  // Historique des commandes du client.
  router.get('/', (req, res) => {
    const rows = db
      .prepare(
        `SELECT c.*, (SELECT COUNT(*) FROM commande_items ci WHERE ci.id_commande = c.id_commande) AS nb_articles
         FROM commandes c WHERE c.id_user = ? ORDER BY c.date_commande DESC, c.id_commande DESC`,
      )
      .all(req.user.id_user);
    res.json(rows);
  });

  router.get('/:id', (req, res) => {
    const commande = detailCommande(db, toInt(req.params.id, 'id'));
    if (!commande || !peutVoirCommande(db, req.user, commande)) throw notFound('Commande introuvable');
    res.json(commande);
  });

  router.post('/:id/annuler', (req, res) => {
    const id = toInt(req.params.id, 'id');
    const commande = db.prepare('SELECT * FROM commandes WHERE id_commande = ? AND id_user = ?').get(id, req.user.id_user);
    if (!commande) throw notFound('Commande introuvable');
    if (commande.statut_commande !== STATUT.EN_ATTENTE_PAIEMENT) throw conflict('Seule une commande non payée peut être annulée');
    if (db.prepare("SELECT 1 FROM payements WHERE id_commande = ? AND statut_paie = 'en_attente'").get(id)) {
      throw conflict('Un paiement est en cours de traitement');
    }
    transaction(db, () => {
      db.prepare('UPDATE commandes SET statut_commande = ? WHERE id_commande = ?').run(STATUT.ANNULEE, id);
      commerce.restituerStock(id);
    });
    res.json(detailCommande(db, id));
  });

  // Donner son avis sur une commande livrée.
  router.post('/:id/avis', (req, res) => {
    const id = toInt(req.params.id, 'id');
    const note = toInt(req.body.note_avis, 'note_avis', { min: 1 });
    if (note > 5) throw badRequest('La note doit être comprise entre 1 et 5');
    const commande = db.prepare('SELECT * FROM commandes WHERE id_commande = ? AND id_user = ?').get(id, req.user.id_user);
    if (!commande) throw notFound('Commande introuvable');
    if (commande.statut_commande !== STATUT.LIVREE) throw conflict('La commande doit être livrée pour être notée');
    db.prepare(
      `INSERT INTO avis (id_user, id_commande, note_avis, commentaire) VALUES (?, ?, ?, ?)
       ON CONFLICT (id_user, id_commande) WHERE id_commande IS NOT NULL
       DO UPDATE SET note_avis = excluded.note_avis, commentaire = excluded.commentaire, date_avis = datetime('now')`,
    ).run(req.user.id_user, id, note, req.body.commentaire || null);
    res.status(201).json(detailCommande(db, id));
  });

  return router;
}

// --- Paiements (diagramme de séquence « Paiement ») ---------------------------
function paiementsRoutes({ db, paymentProvider, commerce, config }) {
  const router = express.Router();

  // Callback de l'opérateur (webhook authentifié par secret partagé).
  router.post('/callback', (req, res) => {
    if (req.get('x-callback-secret') !== config.paymentCallbackSecret) throw forbidden('Signature invalide');
    requireFields(req.body, ['reference_transaction']);
    const result = commerce.appliquerResultatPaiement(
      req.body.reference_transaction,
      req.body.statut === 'SUCCESSFUL',
      req.body.message,
    );
    res.json({ traite: Boolean(result) });
  });

  router.use(authenticate(db));

  router.get('/modes', (_req, res) =>
    res.json([
      { code: 'MTN_MOMO', libelle: 'MTN Mobile Money' },
      { code: 'ORANGE_MONEY', libelle: 'Orange Money' },
    ]),
  );

  router.post('/', async (req, res) => {
    requireFields(req.body, ['id_commande', 'mode_paie', 'telephone']);
    const idCommande = toInt(req.body.id_commande, 'id_commande');
    const { mode_paie, telephone } = req.body;
    if (!MODES_PAIEMENT.includes(mode_paie)) throw badRequest('Mode de paiement invalide');
    if (!/^\+?\d{8,15}$/.test(String(telephone).replace(/\s/g, ''))) throw badRequest('Numéro de téléphone invalide');

    // Vérifier statut commande.
    const commande = db.prepare('SELECT * FROM commandes WHERE id_commande = ? AND id_user = ?').get(idCommande, req.user.id_user);
    if (!commande || commande.statut_commande !== STATUT.EN_ATTENTE_PAIEMENT) {
      throw conflict('Commande introuvable ou déjà payée');
    }
    if (db.prepare("SELECT 1 FROM payements WHERE id_commande = ? AND statut_paie = 'en_attente'").get(idCommande)) {
      throw conflict('Un paiement est déjà en cours pour cette commande');
    }

    const reference = newReference();
    const { lastInsertRowid } = db
      .prepare(
        `INSERT INTO payements (id_commande, montant, statut_paie, mode_paie, telephone, reference_transaction, message)
         VALUES (?, ?, 'en_attente', ?, ?, ?, 'Confirmez le paiement sur votre téléphone')`,
      )
      .run(idCommande, commande.total_commande, mode_paie, String(telephone).replace(/\s/g, ''), reference);

    try {
      await paymentProvider.requestPayment({ reference, montant: commande.total_commande, telephone, mode: mode_paie });
    } catch (err) {
      commerce.appliquerResultatPaiement(reference, false, `Opérateur indisponible : ${err.message}`);
    }
    res.status(202).json(db.prepare('SELECT * FROM payements WHERE id_payement = ?').get(lastInsertRowid));
  });

  router.get('/:id', (req, res) => {
    const p = db
      .prepare(
        `SELECT py.*, f.numero_facture, f.date_facture, c.id_user, c.statut_commande FROM payements py
         JOIN commandes c ON c.id_commande = py.id_commande
         LEFT JOIN factures f ON f.id_payement = py.id_payement WHERE py.id_payement = ?`,
      )
      .get(toInt(req.params.id, 'id'));
    if (!p || (p.id_user !== req.user.id_user && !hasPermission(req.user, PERMISSIONS.PAIEMENTS_VOIR))) {
      throw notFound('Paiement introuvable');
    }
    res.json(p);
  });

  return router;
}

// --- Livraisons (diagramme de séquence « Gestion des livraisons ») -----------
function livraisonsRoutes({ db, notifier, commerce }) {
  const router = express.Router();

  // Estimation publique des frais de livraison.
  router.get('/frais', (req, res) => {
    const sousTotal = Number(req.query.sous_total) || 0;
    res.json({ ville: req.query.ville || null, frais_livraison: commerce.fraisLivraison(req.query.ville, sousTotal) });
  });

  router.use(authenticate(db), requirePermission(PERMISSIONS.LIVRAISONS_EFFECTUER));

  // consulterLivraisons() -> commandes à livrer + celles prises en charge.
  router.get('/', (req, res) => {
    const disponibles = db
      .prepare(
        `SELECT c.*, u.prenom AS client_prenom, u.nom AS client_nom FROM commandes c JOIN users u ON u.id_user = c.id_user
         WHERE c.statut_commande = ? AND c.id_livreur IS NULL ORDER BY c.date_commande`,
      )
      .all(STATUT.EN_COURS);
    const mesLivraisons = db
      .prepare(
        `SELECT c.*, u.prenom AS client_prenom, u.nom AS client_nom FROM commandes c JOIN users u ON u.id_user = c.id_user
         WHERE c.id_livreur = ? ORDER BY CASE c.statut_commande WHEN ? THEN 0 ELSE 1 END, c.date_commande DESC`,
      )
      .all(req.user.id_user, STATUT.EN_LIVRAISON);
    res.json({ disponibles, mes_livraisons: mesLivraisons });
  });

  const commandeDe = (id) => db.prepare('SELECT * FROM commandes WHERE id_commande = ?').get(id);

  router.post('/:id/prendre', (req, res) => {
    const id = toInt(req.params.id, 'id');
    const { changes } = db
      .prepare('UPDATE commandes SET statut_commande = ?, id_livreur = ? WHERE id_commande = ? AND statut_commande = ? AND id_livreur IS NULL')
      .run(STATUT.EN_LIVRAISON, req.user.id_user, id, STATUT.EN_COURS);
    if (!changes) throw conflict('Commande indisponible');
    const c = commandeDe(id);
    notifier.notify(c.id_user, 'livraison', 'Commande en livraison', `Votre commande #${id} est en route avec ${req.user.prenom}.`);
    res.json(detailCommande(db, id));
  });

  router.post('/:id/confirmer', (req, res) => {
    const id = toInt(req.params.id, 'id');
    const { changes } = db
      .prepare("UPDATE commandes SET statut_commande = ?, date_livraison = datetime('now') WHERE id_commande = ? AND id_livreur = ? AND statut_commande = ?")
      .run(STATUT.LIVREE, id, req.user.id_user, STATUT.EN_LIVRAISON);
    if (!changes) throw conflict('Statut incorrect : la commande n’est pas en livraison par vous');
    const c = commandeDe(id);
    notifier.notify(c.id_user, 'livraison', 'Commande livrée', `Votre commande #${id} a été livrée. Donnez votre avis !`);
    res.json(detailCommande(db, id));
  });

  router.post('/:id/echec', (req, res) => {
    const id = toInt(req.params.id, 'id');
    requireFields(req.body, ['motif']);
    const { changes } = db
      .prepare('UPDATE commandes SET statut_commande = ?, motif_echec = ? WHERE id_commande = ? AND id_livreur = ? AND statut_commande = ?')
      .run(STATUT.ECHEC_LIVRAISON, req.body.motif, id, req.user.id_user, STATUT.EN_LIVRAISON);
    if (!changes) throw conflict('Statut incorrect : la commande n’est pas en livraison par vous');
    const c = commandeDe(id);
    notifier.notify(c.id_user, 'livraison', 'Échec de livraison', `Livraison #${id} non effectuée : ${req.body.motif}`);
    notifier.notifyAdmins('livraison', 'Échec de livraison', `Commande #${id} : ${req.body.motif}`);
    res.json(detailCommande(db, id));
  });

  return router;
}

module.exports = { panierRoutes, commandesRoutes, paiementsRoutes, livraisonsRoutes, detailCommande };

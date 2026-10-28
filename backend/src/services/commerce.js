const { transaction } = require('../db');
const { STATUT, STATUT_LIBELLES, PERMISSIONS } = require('../constants');

// Message envoyé au client (application + SMS) à chaque changement de statut.
const MESSAGES_STATUT = {
  [STATUT.EN_ATTENTE_PAIEMENT]: (id) => `Votre commande #${id} est bien reçue. Procédez au paiement pour la confirmer.`,
  [STATUT.EN_COURS]: (id) => `Votre commande #${id} est confirmée. Nous la préparons.`,
  [STATUT.EN_PREPARATION]: (id) => `Votre commande #${id} est en préparation.`,
  [STATUT.EN_LIVRAISON]: (id) => `Votre commande #${id} est en route vers vous.`,
  [STATUT.LIVREE]: (id) => `Votre commande #${id} a été livrée. Confirmez la réception dans l’application.`,
  [STATUT.CLOTUREE]: (id) => `Commande #${id} clôturée. Merci pour votre confiance !`,
  [STATUT.ECHEC_LIVRAISON]: (id) => `La livraison de votre commande #${id} n’a pas pu être effectuée.`,
  [STATUT.ANNULEE]: (id) => `Votre commande #${id} a été annulée.`,
};

/** Logique métier partagée : panier, frais de livraison, résultat de paiement. */
function createCommerce(db, notifier) {
  function fraisLivraison(ville, sousTotal) {
    const regle =
      db.prepare('SELECT * FROM regles_livraison WHERE ville = ? COLLATE NOCASE').get(String(ville || '').trim()) ||
      db.prepare("SELECT * FROM regles_livraison WHERE ville = '*'").get();
    if (!regle || sousTotal === 0) return 0;
    if (regle.seuil_gratuite !== null && sousTotal >= regle.seuil_gratuite) return 0;
    return regle.frais;
  }

  function panierId(idUser) {
    const row = db.prepare('SELECT id_panier FROM paniers WHERE id_user = ?').get(idUser);
    if (row) return row.id_panier;
    return Number(db.prepare('INSERT INTO paniers (id_user) VALUES (?)').run(idUser).lastInsertRowid);
  }

  /** Contenu du panier avec calcul automatique du sous-total, des frais et du total. */
  function lirePanier(idUser, ville) {
    const id = panierId(idUser);
    const items = db
      .prepare(
        `SELECT pi.id_produit, pi.quantite, p.nom, p.prix_produit, p.image_produit, p.quantite_stock, p.unite,
                p.statut, (p.prix_produit * pi.quantite) AS total_ligne,
                (p.statut = 'publie' AND (b.id_boutique IS NULL OR b.active = 1)) AS disponible
         FROM panier_items pi
         JOIN produits p ON p.id_produit = pi.id_produit
         LEFT JOIN boutiques b ON b.id_boutique = p.id_boutique
         WHERE pi.id_panier = ?
         ORDER BY p.nom`,
      )
      .all(id)
      .map((i) => ({ ...i, disponible: Boolean(i.disponible) }));
    const sous_total = items.reduce((s, i) => s + i.total_ligne, 0);
    const user = db.prepare('SELECT adresse FROM users WHERE id_user = ?').get(idUser);
    const frais_livraison = fraisLivraison(ville, sous_total);
    return {
      id_panier: id,
      items,
      nombre_articles: items.reduce((s, i) => s + i.quantite, 0),
      sous_total,
      frais_livraison,
      total: sous_total + frais_livraison,
      adresse_par_defaut: user?.adresse || null,
    };
  }

  /**
   * Enregistre un changement de statut dans l'historique et prévient le client.
   * À appeler après la mise à jour de commandes.statut_commande.
   */
  function suivreStatut(idCommande, statut, { auteur = null, commentaire = null, message } = {}) {
    db.prepare('INSERT INTO commande_historique (id_commande, statut, commentaire, id_auteur) VALUES (?, ?, ?, ?)').run(
      idCommande,
      statut,
      commentaire,
      auteur,
    );
    const commande = db.prepare('SELECT id_user FROM commandes WHERE id_commande = ?').get(idCommande);
    const texte = message || MESSAGES_STATUT[statut]?.(idCommande) || `Commande #${idCommande} : ${statut}.`;
    notifier.notify(commande.id_user, 'commande', `Commande #${idCommande} : ${STATUT_LIBELLES[statut] || statut}`, texte);
  }

  /** Callback de l'opérateur de paiement (diagramme de séquence « paiement »). */
  function appliquerResultatPaiement(reference, succes, message) {
    const paiement = db.prepare('SELECT * FROM payements WHERE reference_transaction = ?').get(reference);
    if (!paiement || paiement.statut_paie !== 'en_attente') return null;

    const commande = db.prepare('SELECT * FROM commandes WHERE id_commande = ?').get(paiement.id_commande);
    if (!succes) {
      db.prepare("UPDATE payements SET statut_paie = 'echoue', message = ? WHERE id_payement = ?").run(
        message || 'Paiement refusé',
        paiement.id_payement,
      );
      notifier.notify(
        commande.id_user,
        'paiement',
        'Paiement échoué',
        `Le paiement de la commande #${commande.id_commande} a échoué. Vous pouvez réessayer.`,
      );
      return { statut: 'echoue' };
    }

    const confirmee = transaction(db, () => {
      db.prepare("UPDATE payements SET statut_paie = 'reussi', message = ? WHERE id_payement = ?").run(
        message || 'Paiement réussi',
        paiement.id_payement,
      );
      // Mettre à jour statut = Payée -> la commande passe « Confirmée ».
      const { changes } = db.prepare('UPDATE commandes SET statut_commande = ? WHERE id_commande = ? AND statut_commande = ?').run(
        STATUT.EN_COURS,
        commande.id_commande,
        STATUT.EN_ATTENTE_PAIEMENT,
      );
      const annee = new Date().getFullYear();
      const numero = `FAC-${annee}-${String(paiement.id_payement).padStart(6, '0')}`;
      db.prepare("INSERT INTO factures (id_payement, numero_facture, statut_facture) VALUES (?, ?, 'payee')").run(
        paiement.id_payement,
        numero,
      );
      return changes > 0;
    });

    const texte = `Paiement de ${paiement.montant} FCFA reçu : votre commande #${commande.id_commande} est confirmée.`;
    if (confirmee) {
      suivreStatut(commande.id_commande, STATUT.EN_COURS, { commentaire: `Paiement ${paiement.mode_paie} réussi`, message: texte });
    } else {
      notifier.notify(commande.id_user, 'paiement', 'Paiement réussi', texte);
    }
    notifier.notifyAdmins('commande', 'Nouvelle commande payée', `Commande #${commande.id_commande} à préparer.`);
    notifier.notifyPermission(
      PERMISSIONS.LIVRAISONS_EFFECTUER,
      'livraison',
      'Nouvelle livraison disponible',
      `Commande #${commande.id_commande} à livrer à ${commande.ville}.`,
    );
    const vendeurs = db
      .prepare(
        `SELECT DISTINCT b.id_vendeur FROM commande_items ci
         JOIN produits p ON p.id_produit = ci.id_produit
         JOIN boutiques b ON b.id_boutique = p.id_boutique
         WHERE ci.id_commande = ?`,
      )
      .all(commande.id_commande);
    vendeurs.forEach((v) =>
      notifier.notify(v.id_vendeur, 'commande', 'Nouvelle vente', `Vos produits ont été commandés (#${commande.id_commande}).`),
    );
    return { statut: 'reussi' };
  }

  /** Remet en stock les articles d'une commande annulée. */
  function restituerStock(idCommande) {
    const items = db.prepare('SELECT id_produit, quantite FROM commande_items WHERE id_commande = ?').all(idCommande);
    const upd = db.prepare('UPDATE produits SET quantite_stock = quantite_stock + ? WHERE id_produit = ?');
    items.forEach((i) => upd.run(i.quantite, i.id_produit));
  }

  return { fraisLivraison, panierId, lirePanier, suivreStatut, appliquerResultatPaiement, restituerStock };
}

module.exports = { createCommerce };

const path = require('node:path');
const fs = require('node:fs');
const { DatabaseSync } = require('node:sqlite');
const config = require('./config');

// Schéma dérivé du diagramme de classes (Figure 4) :
// USER, ROLE, PERMISSION, CATEGORIE, PRODUIT, PANIER, COMMANDE, PAYEMENT,
// FACTURE, AVIS, MESSAGERIE, NOTIFICATION, complété par les tables
// nécessaires aux cas d'utilisation (boutique, livraison, newsletter).
const SCHEMA = `
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS roles (
  id_role INTEGER PRIMARY KEY AUTOINCREMENT,
  nom TEXT NOT NULL UNIQUE,
  description TEXT
);

CREATE TABLE IF NOT EXISTS permissions (
  id_permission INTEGER PRIMARY KEY AUTOINCREMENT,
  nom TEXT NOT NULL UNIQUE,
  description TEXT
);

CREATE TABLE IF NOT EXISTS role_permissions (
  id_role INTEGER NOT NULL REFERENCES roles(id_role) ON DELETE CASCADE,
  id_permission INTEGER NOT NULL REFERENCES permissions(id_permission) ON DELETE CASCADE,
  PRIMARY KEY (id_role, id_permission)
);

CREATE TABLE IF NOT EXISTS users (
  id_user INTEGER PRIMARY KEY AUTOINCREMENT,
  nom TEXT NOT NULL,
  prenom TEXT NOT NULL,
  email TEXT UNIQUE,
  telephone TEXT NOT NULL UNIQUE,
  adresse TEXT,
  profil TEXT,
  mdp TEXT NOT NULL,
  actif INTEGER NOT NULL DEFAULT 1,
  newsletter INTEGER NOT NULL DEFAULT 0,
  token_version INTEGER NOT NULL DEFAULT 0,
  derniere_connexion TEXT,
  date_creation TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS user_roles (
  id_user INTEGER NOT NULL REFERENCES users(id_user) ON DELETE CASCADE,
  id_role INTEGER NOT NULL REFERENCES roles(id_role) ON DELETE CASCADE,
  PRIMARY KEY (id_user, id_role)
);

CREATE TABLE IF NOT EXISTS boutiques (
  id_boutique INTEGER PRIMARY KEY AUTOINCREMENT,
  id_vendeur INTEGER NOT NULL UNIQUE REFERENCES users(id_user) ON DELETE CASCADE,
  nom TEXT NOT NULL,
  description TEXT,
  adresse TEXT,
  ville TEXT,
  telephone TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  date_creation TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS categories (
  id_categorie INTEGER PRIMARY KEY AUTOINCREMENT,
  nom TEXT NOT NULL UNIQUE,
  description TEXT,
  type TEXT NOT NULL DEFAULT 'phytosanitaire' CHECK (type IN ('phytosanitaire', 'elevage'))
);

CREATE TABLE IF NOT EXISTS produits (
  id_produit INTEGER PRIMARY KEY AUTOINCREMENT,
  id_categorie INTEGER NOT NULL REFERENCES categories(id_categorie),
  id_boutique INTEGER REFERENCES boutiques(id_boutique) ON DELETE CASCADE,
  nom TEXT NOT NULL,
  description TEXT,
  prix_produit INTEGER NOT NULL CHECK (prix_produit >= 0),
  quantite_stock INTEGER NOT NULL DEFAULT 0 CHECK (quantite_stock >= 0),
  unite TEXT,
  image_produit TEXT,
  statut TEXT NOT NULL DEFAULT 'publie' CHECK (statut IN ('brouillon', 'publie', 'retire')),
  date_creation TEXT NOT NULL DEFAULT (datetime('now')),
  date_modification TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS paniers (
  id_panier INTEGER PRIMARY KEY AUTOINCREMENT,
  id_user INTEGER NOT NULL UNIQUE REFERENCES users(id_user) ON DELETE CASCADE,
  statut_panier TEXT NOT NULL DEFAULT 'actif',
  date_creation TEXT NOT NULL DEFAULT (datetime('now')),
  date_modification TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS panier_items (
  id_panier INTEGER NOT NULL REFERENCES paniers(id_panier) ON DELETE CASCADE,
  id_produit INTEGER NOT NULL REFERENCES produits(id_produit) ON DELETE CASCADE,
  quantite INTEGER NOT NULL CHECK (quantite > 0),
  PRIMARY KEY (id_panier, id_produit)
);

CREATE TABLE IF NOT EXISTS commandes (
  id_commande INTEGER PRIMARY KEY AUTOINCREMENT,
  id_user INTEGER NOT NULL REFERENCES users(id_user),
  date_commande TEXT NOT NULL DEFAULT (datetime('now')),
  statut_commande TEXT NOT NULL,
  sous_total INTEGER NOT NULL,
  frais_livraison INTEGER NOT NULL,
  total_commande INTEGER NOT NULL,
  adresse_livraison TEXT NOT NULL,
  ville TEXT NOT NULL,
  telephone_livraison TEXT NOT NULL,
  id_livreur INTEGER REFERENCES users(id_user),
  motif_echec TEXT,
  date_livraison TEXT
);

CREATE TABLE IF NOT EXISTS commande_items (
  id_commande INTEGER NOT NULL REFERENCES commandes(id_commande) ON DELETE CASCADE,
  id_produit INTEGER NOT NULL REFERENCES produits(id_produit),
  nom_produit TEXT NOT NULL,
  prix_unitaire INTEGER NOT NULL,
  quantite INTEGER NOT NULL,
  PRIMARY KEY (id_commande, id_produit)
);

CREATE TABLE IF NOT EXISTS payements (
  id_payement INTEGER PRIMARY KEY AUTOINCREMENT,
  id_commande INTEGER NOT NULL REFERENCES commandes(id_commande),
  montant INTEGER NOT NULL,
  date_paie TEXT NOT NULL DEFAULT (datetime('now')),
  statut_paie TEXT NOT NULL CHECK (statut_paie IN ('en_attente', 'reussi', 'echoue')),
  mode_paie TEXT NOT NULL CHECK (mode_paie IN ('MTN_MOMO', 'ORANGE_MONEY')),
  telephone TEXT NOT NULL,
  reference_transaction TEXT UNIQUE,
  message TEXT
);

CREATE TABLE IF NOT EXISTS factures (
  id_facture INTEGER PRIMARY KEY AUTOINCREMENT,
  id_payement INTEGER NOT NULL UNIQUE REFERENCES payements(id_payement),
  numero_facture TEXT NOT NULL UNIQUE,
  date_facture TEXT NOT NULL DEFAULT (datetime('now')),
  statut_facture TEXT NOT NULL DEFAULT 'payee'
);

CREATE TABLE IF NOT EXISTS avis (
  id_avis INTEGER PRIMARY KEY AUTOINCREMENT,
  id_user INTEGER NOT NULL REFERENCES users(id_user) ON DELETE CASCADE,
  id_produit INTEGER REFERENCES produits(id_produit) ON DELETE CASCADE,
  id_commande INTEGER REFERENCES commandes(id_commande) ON DELETE CASCADE,
  note_avis INTEGER NOT NULL CHECK (note_avis BETWEEN 1 AND 5),
  commentaire TEXT,
  date_avis TEXT NOT NULL DEFAULT (datetime('now')),
  CHECK ((id_produit IS NULL) <> (id_commande IS NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_avis_produit ON avis(id_user, id_produit) WHERE id_produit IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_avis_commande ON avis(id_user, id_commande) WHERE id_commande IS NOT NULL;

CREATE TABLE IF NOT EXISTS messagerie (
  id_messagerie INTEGER PRIMARY KEY AUTOINCREMENT,
  id_expediteur INTEGER NOT NULL REFERENCES users(id_user) ON DELETE CASCADE,
  id_destinataire INTEGER NOT NULL REFERENCES users(id_user) ON DELETE CASCADE,
  sujet TEXT,
  contenu TEXT NOT NULL,
  date_envoie TEXT NOT NULL DEFAULT (datetime('now')),
  date_lecture TEXT
);

CREATE TABLE IF NOT EXISTS notifications (
  id_notification INTEGER PRIMARY KEY AUTOINCREMENT,
  id_user INTEGER NOT NULL REFERENCES users(id_user) ON DELETE CASCADE,
  type TEXT NOT NULL,
  titre TEXT NOT NULL,
  message TEXT NOT NULL,
  lu INTEGER NOT NULL DEFAULT 0,
  date TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS notification_logs (
  id_log INTEGER PRIMARY KEY AUTOINCREMENT,
  id_notification INTEGER NOT NULL REFERENCES notifications(id_notification) ON DELETE CASCADE,
  canal TEXT NOT NULL,
  destinataire TEXT,
  statut TEXT NOT NULL,
  date TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS regles_livraison (
  id_regle INTEGER PRIMARY KEY AUTOINCREMENT,
  ville TEXT NOT NULL UNIQUE COLLATE NOCASE,
  frais INTEGER NOT NULL CHECK (frais >= 0),
  seuil_gratuite INTEGER
);

CREATE TABLE IF NOT EXISTS parametres (
  cle TEXT PRIMARY KEY,
  valeur TEXT NOT NULL,
  date_modification TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS newsletter (
  id_abonne INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL UNIQUE COLLATE NOCASE,
  date_inscription TEXT NOT NULL DEFAULT (datetime('now'))
);
`;

function open(file = config.dbFile) {
  if (file !== ':memory:') fs.mkdirSync(path.dirname(file), { recursive: true });
  const db = new DatabaseSync(file);
  db.exec(SCHEMA);
  return db;
}

/** Exécute fn dans une transaction ; annule tout en cas d'exception. */
function transaction(db, fn) {
  db.exec('BEGIN');
  try {
    const result = fn();
    db.exec('COMMIT');
    return result;
  } catch (err) {
    db.exec('ROLLBACK');
    throw err;
  }
}

module.exports = { open, transaction };

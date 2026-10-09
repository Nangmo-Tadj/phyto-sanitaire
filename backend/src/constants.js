// Statuts de commande (diagrammes de séquence commande / paiement / livraison).
const STATUT = Object.freeze({
  EN_ATTENTE_PAIEMENT: 'en_attente_paiement',
  EN_COURS: 'en_cours', // payée, en préparation
  EN_LIVRAISON: 'en_livraison',
  LIVREE: 'livree',
  ECHEC_LIVRAISON: 'echec_livraison',
  ANNULEE: 'annulee',
});

const PERMISSIONS = Object.freeze({
  PRODUITS_GERER: 'produits.gerer',
  PRODUITS_MODERER: 'produits.moderer',
  CATEGORIES_GERER: 'categories.gerer',
  UTILISATEURS_GERER: 'utilisateurs.gerer',
  ROLES_GERER: 'roles.gerer',
  COMMANDES_GERER: 'commandes.gerer',
  PAIEMENTS_VOIR: 'paiements.voir',
  LIVRAISONS_EFFECTUER: 'livraisons.effectuer',
  LIVRAISON_REGLES: 'livraison.regles',
  BOUTIQUE_GERER: 'boutique.gerer',
  STATISTIQUES_VOIR: 'statistiques.voir',
});

const PERMISSION_DESCRIPTIONS = {
  [PERMISSIONS.PRODUITS_GERER]: 'Ajouter, modifier, supprimer ses produits et gérer le stock',
  [PERMISSIONS.PRODUITS_MODERER]: 'Gérer les produits de toutes les boutiques',
  [PERMISSIONS.CATEGORIES_GERER]: 'Créer et organiser les catégories',
  [PERMISSIONS.UTILISATEURS_GERER]: 'Lister, activer ou désactiver les comptes',
  [PERMISSIONS.ROLES_GERER]: 'Attribuer les rôles et permissions',
  [PERMISSIONS.COMMANDES_GERER]: 'Consulter toutes les commandes et changer leur statut',
  [PERMISSIONS.PAIEMENTS_VOIR]: 'Consulter les paiements',
  [PERMISSIONS.LIVRAISONS_EFFECTUER]: 'Prendre en charge et confirmer les livraisons',
  [PERMISSIONS.LIVRAISON_REGLES]: 'Configurer les règles de livraison',
  [PERMISSIONS.BOUTIQUE_GERER]: 'Créer et gérer sa boutique',
  [PERMISSIONS.STATISTIQUES_VOIR]: 'Consulter les lots et statistiques des ventes',
};

// Rôles par défaut (acteurs du diagramme de cas d'utilisation).
const ROLES = Object.freeze({
  CLIENT: 'client',
  VENDEUR: 'vendeur',
  LIVREUR: 'livreur',
  ADMIN: 'admin',
});

const DEFAULT_ROLES = {
  [ROLES.CLIENT]: { description: 'Achète des produits', permissions: [] },
  [ROLES.VENDEUR]: {
    description: 'Gère sa boutique et ses stocks',
    permissions: [PERMISSIONS.BOUTIQUE_GERER, PERMISSIONS.PRODUITS_GERER],
  },
  [ROLES.LIVREUR]: {
    description: 'Livre les commandes',
    permissions: [PERMISSIONS.LIVRAISONS_EFFECTUER],
  },
  [ROLES.ADMIN]: {
    description: 'Gestionnaire principal de la plateforme',
    permissions: Object.values(PERMISSIONS),
  },
};

const MODES_PAIEMENT = ['MTN_MOMO', 'ORANGE_MONEY'];

// Comptes de démonstration créés par « npm run seed », par profil (téléphone).
const DEMO_ACCOUNTS = { client: '690000004', vendeur: '690000002', livreur: '690000003', admin: '690000001' };

module.exports = { DEMO_ACCOUNTS, STATUT, PERMISSIONS, PERMISSION_DESCRIPTIONS, ROLES, DEFAULT_ROLES, MODES_PAIEMENT };

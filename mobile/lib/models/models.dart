// Modèles issus du diagramme de classes.

int _int(dynamic v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
int? _intN(dynamic v) => v == null ? null : _int(v);
double _double(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
bool _bool(dynamic v) => v == true || v == 1;
DateTime? _date(dynamic v) {
  if (v == null) return null;
  // SQLite renvoie des dates UTC « YYYY-MM-DD HH:MM:SS ».
  return DateTime.tryParse('${v.toString().replaceFirst(' ', 'T')}Z')?.toLocal();
}

List<String> _strings(dynamic v) => (v as List? ?? []).map((e) => '$e').toList();

class BoutiqueResume {
  final int id;
  final String nom;
  BoutiqueResume(this.id, this.nom);
}

class User {
  final int id;
  final String nom;
  final String prenom;
  final String? email;
  final String telephone;
  final String? adresse;
  final String? profil;
  final bool actif;
  final bool newsletter;
  final DateTime? derniereConnexion;
  final List<String> roles;
  final List<String> permissions;
  final BoutiqueResume? boutique;

  User({
    required this.id,
    required this.nom,
    required this.prenom,
    this.email,
    required this.telephone,
    this.adresse,
    this.profil,
    this.actif = true,
    this.newsletter = false,
    this.derniereConnexion,
    this.roles = const [],
    this.permissions = const [],
    this.boutique,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
    id: _int(j['id_user']),
    nom: j['nom'] ?? '',
    prenom: j['prenom'] ?? '',
    email: j['email'],
    telephone: j['telephone'] ?? '',
    adresse: j['adresse'],
    profil: j['profil'],
    actif: j['actif'] == null ? true : _bool(j['actif']),
    newsletter: _bool(j['newsletter']),
    derniereConnexion: _date(j['derniere_connexion']),
    roles: _strings(j['roles']),
    permissions: _strings(j['permissions']),
    boutique: j['boutique'] == null ? null : BoutiqueResume(_int(j['boutique']['id_boutique']), j['boutique']['nom'] ?? ''),
  );

  String get nomComplet => '$prenom $nom';
  bool can(String permission) => permissions.contains(permission);
  bool hasRole(String role) => roles.contains(role);
}

/// Noms des permissions exposées par l'API.
class Perm {
  static const produitsGerer = 'produits.gerer';
  static const produitsModerer = 'produits.moderer';
  static const categoriesGerer = 'categories.gerer';
  static const utilisateursGerer = 'utilisateurs.gerer';
  static const rolesGerer = 'roles.gerer';
  static const commandesGerer = 'commandes.gerer';
  static const paiementsVoir = 'paiements.voir';
  static const livraisonsEffectuer = 'livraisons.effectuer';
  static const livraisonRegles = 'livraison.regles';
  static const boutiqueGerer = 'boutique.gerer';
  static const statistiquesVoir = 'statistiques.voir';
}

class Categorie {
  final int id;
  final String nom;
  final String? description;
  final String type; // phytosanitaire | elevage
  final int nbProduits;

  Categorie({required this.id, required this.nom, this.description, required this.type, this.nbProduits = 0});

  factory Categorie.fromJson(Map<String, dynamic> j) => Categorie(
    id: _int(j['id_categorie']),
    nom: j['nom'] ?? '',
    description: j['description'],
    type: j['type'] ?? 'phytosanitaire',
    nbProduits: _int(j['nb_produits']),
  );
}

class Produit {
  final int id;
  final int idCategorie;
  final int? idBoutique;
  final String nom;
  final String? description;
  final int prix;
  final int stock;
  final String? unite;
  final String? image;
  final String statut; // brouillon | publie | retire
  final String categorie;
  final String typeCategorie;
  final String? boutique;
  final String? villeBoutique;
  final int? idVendeur;
  final String? telephoneBoutique;
  final double noteMoyenne;
  final int nbAvis;

  Produit({
    required this.id,
    required this.idCategorie,
    this.idBoutique,
    required this.nom,
    this.description,
    required this.prix,
    required this.stock,
    this.unite,
    this.image,
    required this.statut,
    required this.categorie,
    required this.typeCategorie,
    this.boutique,
    this.villeBoutique,
    this.idVendeur,
    this.telephoneBoutique,
    this.noteMoyenne = 0,
    this.nbAvis = 0,
  });

  factory Produit.fromJson(Map<String, dynamic> j) => Produit(
    id: _int(j['id_produit']),
    idCategorie: _int(j['id_categorie']),
    idBoutique: _intN(j['id_boutique']),
    nom: j['nom'] ?? '',
    description: j['description'],
    prix: _int(j['prix_produit']),
    stock: _int(j['quantite_stock']),
    unite: j['unite'],
    image: j['image_produit'],
    statut: j['statut'] ?? 'publie',
    categorie: j['categorie'] ?? '',
    typeCategorie: j['type_categorie'] ?? 'phytosanitaire',
    boutique: j['boutique'],
    villeBoutique: j['ville_boutique'],
    idVendeur: _intN(j['id_vendeur']),
    telephoneBoutique: j['telephone_boutique'],
    noteMoyenne: _double(j['note_moyenne']),
    nbAvis: _int(j['nb_avis']),
  );

  bool get enStock => stock > 0;
}

class Avis {
  final int id;
  final int note;
  final String? commentaire;
  final DateTime? date;
  final String auteur;

  Avis({required this.id, required this.note, this.commentaire, this.date, required this.auteur});

  factory Avis.fromJson(Map<String, dynamic> j) => Avis(
    id: _int(j['id_avis']),
    note: _int(j['note_avis']),
    commentaire: j['commentaire'],
    date: _date(j['date_avis']),
    auteur: '${j['prenom'] ?? ''} ${j['nom'] ?? ''}'.trim(),
  );
}

class PanierItem {
  final int idProduit;
  final String nom;
  final int prix;
  final int quantite;
  final int stock;
  final String? image;
  final String? unite;
  final int totalLigne;
  final bool disponible;

  PanierItem({
    required this.idProduit,
    required this.nom,
    required this.prix,
    required this.quantite,
    required this.stock,
    this.image,
    this.unite,
    required this.totalLigne,
    required this.disponible,
  });

  factory PanierItem.fromJson(Map<String, dynamic> j) => PanierItem(
    idProduit: _int(j['id_produit']),
    nom: j['nom'] ?? '',
    prix: _int(j['prix_produit']),
    quantite: _int(j['quantite']),
    stock: _int(j['quantite_stock']),
    image: j['image_produit'],
    unite: j['unite'],
    totalLigne: _int(j['total_ligne']),
    disponible: _bool(j['disponible']),
  );
}

class Panier {
  final List<PanierItem> items;
  final int nombreArticles;
  final int sousTotal;
  final int fraisLivraison;
  final int total;
  final String? adresseParDefaut;

  Panier({
    this.items = const [],
    this.nombreArticles = 0,
    this.sousTotal = 0,
    this.fraisLivraison = 0,
    this.total = 0,
    this.adresseParDefaut,
  });

  factory Panier.fromJson(Map<String, dynamic> j) => Panier(
    items: (j['items'] as List? ?? []).map((e) => PanierItem.fromJson(e)).toList(),
    nombreArticles: _int(j['nombre_articles']),
    sousTotal: _int(j['sous_total']),
    fraisLivraison: _int(j['frais_livraison']),
    total: _int(j['total']),
    adresseParDefaut: j['adresse_par_defaut'],
  );

  bool get estVide => items.isEmpty;
}

/// Statuts de commande (voir backend/src/constants.js).
class StatutCommande {
  static const enAttentePaiement = 'en_attente_paiement';
  static const enCours = 'en_cours';
  static const enLivraison = 'en_livraison';
  static const livree = 'livree';
  static const echecLivraison = 'echec_livraison';
  static const annulee = 'annulee';
  static const tous = [enAttentePaiement, enCours, enLivraison, livree, echecLivraison, annulee];
}

class CommandeItem {
  final int idProduit;
  final String nom;
  final int prixUnitaire;
  final int quantite;
  final int totalLigne;
  final String? image;

  CommandeItem({
    required this.idProduit,
    required this.nom,
    required this.prixUnitaire,
    required this.quantite,
    required this.totalLigne,
    this.image,
  });

  factory CommandeItem.fromJson(Map<String, dynamic> j) => CommandeItem(
    idProduit: _int(j['id_produit']),
    nom: j['nom_produit'] ?? '',
    prixUnitaire: _int(j['prix_unitaire']),
    quantite: _int(j['quantite']),
    totalLigne: _int(j['total_ligne'] ?? _int(j['prix_unitaire']) * _int(j['quantite'])),
    image: j['image_produit'],
  );
}

class Paiement {
  final int id;
  final int idCommande;
  final int montant;
  final DateTime? date;
  final String statut; // en_attente | reussi | echoue
  final String mode; // MTN_MOMO | ORANGE_MONEY
  final String telephone;
  final String? reference;
  final String? message;
  final String? numeroFacture;
  final String? client;

  Paiement({
    required this.id,
    required this.idCommande,
    required this.montant,
    this.date,
    required this.statut,
    required this.mode,
    required this.telephone,
    this.reference,
    this.message,
    this.numeroFacture,
    this.client,
  });

  factory Paiement.fromJson(Map<String, dynamic> j) => Paiement(
    id: _int(j['id_payement']),
    idCommande: _int(j['id_commande']),
    montant: _int(j['montant']),
    date: _date(j['date_paie']),
    statut: j['statut_paie'] ?? 'en_attente',
    mode: j['mode_paie'] ?? '',
    telephone: j['telephone'] ?? '',
    reference: j['reference_transaction'],
    message: j['message'],
    numeroFacture: j['numero_facture'],
    client: j['client_prenom'] == null ? null : '${j['client_prenom']} ${j['client_nom'] ?? ''}'.trim(),
  );
}

class Commande {
  final int id;
  final int idUser;
  final DateTime? date;
  final String statut;
  final int sousTotal;
  final int fraisLivraison;
  final int total;
  final String adresse;
  final String ville;
  final String telephoneLivraison;
  final int? idLivreur;
  final String? motifEchec;
  final DateTime? dateLivraison;
  final String? client;
  final String? clientTelephone;
  final String? livreur;
  final String? livreurTelephone;
  final int nbArticles;
  final List<CommandeItem> items;
  final List<Paiement> paiements;
  final int? noteAvis;

  Commande({
    required this.id,
    required this.idUser,
    this.date,
    required this.statut,
    required this.sousTotal,
    required this.fraisLivraison,
    required this.total,
    required this.adresse,
    required this.ville,
    required this.telephoneLivraison,
    this.idLivreur,
    this.motifEchec,
    this.dateLivraison,
    this.client,
    this.clientTelephone,
    this.livreur,
    this.livreurTelephone,
    this.nbArticles = 0,
    this.items = const [],
    this.paiements = const [],
    this.noteAvis,
  });

  factory Commande.fromJson(Map<String, dynamic> j) => Commande(
    id: _int(j['id_commande']),
    idUser: _int(j['id_user']),
    date: _date(j['date_commande']),
    statut: j['statut_commande'] ?? '',
    sousTotal: _int(j['sous_total']),
    fraisLivraison: _int(j['frais_livraison']),
    total: _int(j['total_commande']),
    adresse: j['adresse_livraison'] ?? '',
    ville: j['ville'] ?? '',
    telephoneLivraison: j['telephone_livraison'] ?? '',
    idLivreur: _intN(j['id_livreur']),
    motifEchec: j['motif_echec'],
    dateLivraison: _date(j['date_livraison']),
    client: j['client_prenom'] == null ? null : '${j['client_prenom']} ${j['client_nom'] ?? ''}'.trim(),
    clientTelephone: j['client_telephone'],
    livreur: j['livreur_prenom'] == null ? null : '${j['livreur_prenom']} ${j['livreur_nom'] ?? ''}'.trim(),
    livreurTelephone: j['livreur_telephone'],
    nbArticles: _int(j['nb_articles'] ?? (j['items'] as List?)?.length),
    items: (j['items'] as List? ?? []).map((e) => CommandeItem.fromJson(e)).toList(),
    paiements: (j['paiements'] as List? ?? []).map((e) => Paiement.fromJson(e)).toList(),
    noteAvis: j['avis'] == null ? null : _int(j['avis']['note_avis']),
  );

  bool get payable => statut == StatutCommande.enAttentePaiement;
  bool get paiementEnCours => paiements.any((p) => p.statut == 'en_attente');
}

class Boutique {
  final int id;
  final int idVendeur;
  final String nom;
  final String? description;
  final String? adresse;
  final String? ville;
  final String? telephone;
  final bool active;
  final String? vendeur;
  final int nbProduits;

  Boutique({
    required this.id,
    required this.idVendeur,
    required this.nom,
    this.description,
    this.adresse,
    this.ville,
    this.telephone,
    this.active = true,
    this.vendeur,
    this.nbProduits = 0,
  });

  factory Boutique.fromJson(Map<String, dynamic> j) => Boutique(
    id: _int(j['id_boutique']),
    idVendeur: _int(j['id_vendeur']),
    nom: j['nom'] ?? '',
    description: j['description'],
    adresse: j['adresse'],
    ville: j['ville'],
    telephone: j['telephone'],
    active: j['active'] == null ? true : _bool(j['active']),
    vendeur: j['vendeur_prenom'] == null ? null : '${j['vendeur_prenom']} ${j['vendeur_nom'] ?? ''}'.trim(),
    nbProduits: _int(j['nb_produits']),
  );
}

class Vente {
  final int idCommande;
  final DateTime? date;
  final String statut;
  final String ville;
  final String produit;
  final int quantite;
  final int montant;

  Vente({
    required this.idCommande,
    this.date,
    required this.statut,
    required this.ville,
    required this.produit,
    required this.quantite,
    required this.montant,
  });

  factory Vente.fromJson(Map<String, dynamic> j) => Vente(
    idCommande: _int(j['id_commande']),
    date: _date(j['date_commande']),
    statut: j['statut_commande'] ?? '',
    ville: j['ville'] ?? '',
    produit: j['nom_produit'] ?? '',
    quantite: _int(j['quantite']),
    montant: _int(j['montant']),
  );
}

class Message {
  final int id;
  final int idExpediteur;
  final int idDestinataire;
  final String contenu;
  final DateTime? dateEnvoi;
  final DateTime? dateLecture;

  Message({
    required this.id,
    required this.idExpediteur,
    required this.idDestinataire,
    required this.contenu,
    this.dateEnvoi,
    this.dateLecture,
  });

  factory Message.fromJson(Map<String, dynamic> j) => Message(
    id: _int(j['id_messagerie']),
    idExpediteur: _int(j['id_expediteur']),
    idDestinataire: _int(j['id_destinataire']),
    contenu: j['contenu'] ?? '',
    dateEnvoi: _date(j['date_envoie']),
    dateLecture: _date(j['date_lecture']),
  );
}

class Conversation {
  final int idUser;
  final String nom;
  final String telephone;
  final String? dernierMessage;
  final DateTime? date;
  final int nonLus;

  Conversation({
    required this.idUser,
    required this.nom,
    required this.telephone,
    this.dernierMessage,
    this.date,
    this.nonLus = 0,
  });

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
    idUser: _int(j['id_user']),
    nom: '${j['prenom'] ?? ''} ${j['nom'] ?? ''}'.trim(),
    telephone: j['telephone'] ?? '',
    dernierMessage: j['dernier_message'],
    date: _date(j['date_dernier_message']),
    nonLus: _int(j['non_lus']),
  );
}

class AppNotification {
  final int id;
  final String type;
  final String titre;
  final String message;
  final bool lu;
  final DateTime? date;

  AppNotification({
    required this.id,
    required this.type,
    required this.titre,
    required this.message,
    required this.lu,
    this.date,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: _int(j['id_notification']),
    type: j['type'] ?? '',
    titre: j['titre'] ?? '',
    message: j['message'] ?? '',
    lu: _bool(j['lu']),
    date: _date(j['date']),
  );
}

class RegleLivraison {
  final int id;
  final String ville;
  final int frais;
  final int? seuilGratuite;

  RegleLivraison({required this.id, required this.ville, required this.frais, this.seuilGratuite});

  factory RegleLivraison.fromJson(Map<String, dynamic> j) => RegleLivraison(
    id: _int(j['id_regle']),
    ville: j['ville'] ?? '',
    frais: _int(j['frais']),
    seuilGratuite: _intN(j['seuil_gratuite']),
  );
}

class Role {
  final int id;
  final String nom;
  final String? description;
  final List<String> permissions;

  Role({required this.id, required this.nom, this.description, this.permissions = const []});

  factory Role.fromJson(Map<String, dynamic> j) =>
      Role(id: _int(j['id_role']), nom: j['nom'] ?? '', description: j['description'], permissions: _strings(j['permissions']));
}

class PermissionInfo {
  final String nom;
  final String? description;
  PermissionInfo(this.nom, this.description);
  factory PermissionInfo.fromJson(Map<String, dynamic> j) => PermissionInfo(j['nom'] ?? '', j['description']);
}

class Livraisons {
  final List<Commande> disponibles;
  final List<Commande> mesLivraisons;
  Livraisons(this.disponibles, this.mesLivraisons);

  factory Livraisons.fromJson(Map<String, dynamic> j) => Livraisons(
    (j['disponibles'] as List? ?? []).map((e) => Commande.fromJson(e)).toList(),
    (j['mes_livraisons'] as List? ?? []).map((e) => Commande.fromJson(e)).toList(),
  );
}

class Statistiques {
  final int chiffreAffaires;
  final int nbCommandes;
  final int nbClients;
  final int nbProduits;
  final int panierMoyen;
  final Map<String, int> commandesParStatut;
  final List<({String jour, int commandes, int montant})> ventesParJour;
  final List<({String nom, int quantite, int montant})> topProduits;
  final List<({int id, String nom, int stock})> stockBas;

  Statistiques({
    required this.chiffreAffaires,
    required this.nbCommandes,
    required this.nbClients,
    required this.nbProduits,
    required this.panierMoyen,
    required this.commandesParStatut,
    required this.ventesParJour,
    required this.topProduits,
    required this.stockBas,
  });

  factory Statistiques.fromJson(Map<String, dynamic> j) => Statistiques(
    chiffreAffaires: _int(j['chiffre_affaires']),
    nbCommandes: _int(j['nb_commandes']),
    nbClients: _int(j['nb_clients']),
    nbProduits: _int(j['nb_produits']),
    panierMoyen: _int(j['panier_moyen']),
    commandesParStatut: {for (final s in (j['commandes_par_statut'] as List? ?? [])) '${s['statut']}': _int(s['nombre'])},
    ventesParJour: [
      for (final v in (j['ventes_par_jour'] as List? ?? []))
        (jour: '${v['jour']}', commandes: _int(v['commandes']), montant: _int(v['montant'])),
    ],
    topProduits: [
      for (final p in (j['top_produits'] as List? ?? []))
        (nom: '${p['nom']}', quantite: _int(p['quantite']), montant: _int(p['montant'])),
    ],
    stockBas: [
      for (final p in (j['stock_bas'] as List? ?? []))
        (id: _int(p['id_produit']), nom: '${p['nom']}', stock: _int(p['quantite_stock'])),
    ],
  );
}

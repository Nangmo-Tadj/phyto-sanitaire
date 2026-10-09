// Données de démonstration. Usage : npm run seed  (réinitialise la base)
const fs = require('node:fs');
const bcrypt = require('bcryptjs');
const config = require('./config');
const { open, transaction } = require('./db');
const { ensureDefaults } = require('./bootstrap');

for (const suffix of ['', '-wal', '-shm']) fs.rmSync(config.dbFile + suffix, { force: true });
const db = open(config.dbFile);
ensureDefaults(db);

const MDP = 'password123';

transaction(db, () => {
  const hash = bcrypt.hashSync(MDP, 10);
  const addUser = (nom, prenom, email, telephone, adresse, roles) => {
    const id = Number(
      db.prepare('INSERT INTO users (nom, prenom, email, telephone, adresse, mdp) VALUES (?, ?, ?, ?, ?, ?)')
        .run(nom, prenom, email, telephone, adresse, hash).lastInsertRowid,
    );
    roles.forEach((r) => db.prepare('INSERT INTO user_roles (id_user, id_role) SELECT ?, id_role FROM roles WHERE nom = ?').run(id, r));
    return id;
  };

  addUser('Voukeng', 'Charles', 'admin@agrophyto.cm', '690000001', 'Yaoundé, Bastos', ['client', 'vendeur', 'admin']);
  const vendeur = addUser('Nkeng', 'Paul', 'vendeur@agrophyto.cm', '690000002', 'Bafoussam, Marché A', ['client', 'vendeur']);
  const vendeur2 = addUser('Mbarga', 'Alice', 'alice@agrophyto.cm', '690000005', 'Douala, Ndokoti', ['client', 'vendeur']);
  addUser('Fotso', 'Jean', 'livreur@agrophyto.cm', '690000003', 'Yaoundé, Mvog-Mbi', ['client', 'livreur']);
  addUser('Ngo', 'Marie', 'client@agrophyto.cm', '690000004', 'Yaoundé, Essos', ['client']);

  const boutique = (idVendeur, nom, desc, ville, tel) =>
    Number(db.prepare('INSERT INTO boutiques (id_vendeur, nom, description, adresse, ville, telephone) VALUES (?, ?, ?, ?, ?, ?)')
      .run(idVendeur, nom, desc, 'Marché central', ville, tel).lastInsertRowid);
  const b1 = boutique(vendeur, 'Agro-Intrants de l’Ouest', 'Produits phytosanitaires homologués', 'Bafoussam', '690000002');
  const b2 = boutique(vendeur2, 'Élevage Plus Douala', 'Provende et produits vétérinaires', 'Douala', '690000005');

  const cat = (nom, description, type) =>
    Number(db.prepare('INSERT INTO categories (nom, description, type) VALUES (?, ?, ?)').run(nom, description, type).lastInsertRowid);
  const herbicides = cat('Herbicides', 'Désherbants sélectifs et totaux', 'phytosanitaire');
  const insecticides = cat('Insecticides', 'Protection contre les ravageurs', 'phytosanitaire');
  const fongicides = cat('Fongicides', 'Traitement des maladies fongiques', 'phytosanitaire');
  const engrais = cat('Engrais', 'Fertilisants minéraux et organiques', 'phytosanitaire');
  const volaille = cat('Aliments volaille', 'Provendes poulets de chair et pondeuses', 'elevage');
  const porcs = cat('Aliments porcs', 'Provendes croissance et finition', 'elevage');
  const veto = cat('Produits vétérinaires', 'Vitamines, vaccins et antiparasitaires', 'elevage');

  const produits = [
    [herbicides, b1, 'Glyphosate 360 SL', 'Herbicide systémique total non sélectif. Dose : 3 à 6 L/ha.', 4500, 40, 'bidon 1 L'],
    [herbicides, b1, 'Nicosulfuron 40 SC', 'Herbicide sélectif du maïs, post-levée.', 6000, 25, 'flacon 1 L'],
    [insecticides, b1, 'Cypercal 50 EC', 'Insecticide à base de cyperméthrine pour cultures maraîchères.', 3800, 60, 'flacon 1 L'],
    [insecticides, b1, 'Emamectine 19 EC', 'Contre la chenille légionnaire d’automne.', 5200, 4, 'flacon 250 mL'],
    [fongicides, b1, 'Mancozèbe 80 WP', 'Fongicide de contact contre le mildiou (tomate, pomme de terre, cacao).', 3500, 80, 'sachet 1 kg'],
    [fongicides, b1, 'Ridomil Gold Plus', 'Fongicide systémique pour cacaoyer contre la pourriture brune.', 2500, 120, 'sachet 50 g'],
    [engrais, b1, 'NPK 20-10-10', 'Engrais complet pour maïs et cultures vivrières.', 22000, 30, 'sac 50 kg'],
    [engrais, b1, 'Urée 46 %', 'Engrais azoté pour la croissance végétative.', 20000, 3, 'sac 50 kg'],
    [volaille, b2, 'Provende démarrage poulet de chair', 'Aliment complet 0 à 21 jours, 22 % de protéines.', 17500, 50, 'sac 50 kg'],
    [volaille, b2, 'Provende finition poulet de chair', 'Aliment complet 22 à 45 jours.', 16500, 45, 'sac 50 kg'],
    [volaille, b2, 'Aliment pondeuses', 'Riche en calcium pour une meilleure ponte.', 15000, 35, 'sac 50 kg'],
    [porcs, b2, 'Aliment porc croissance', 'Aliment complet pour porcs de 25 à 60 kg.', 14000, 20, 'sac 50 kg'],
    [veto, b2, 'Anti-stress vitaminé', 'Vitamines A, D3, E et électrolytes pour volailles.', 2000, 100, 'sachet 100 g'],
    [veto, b2, 'Vaccin Newcastle HB1', 'Vaccin contre la maladie de Newcastle, 1000 doses.', 4500, 15, 'flacon'],
    [veto, null, 'Ivermectine 1 %', 'Antiparasitaire injectable bovins, ovins, porcins.', 7500, 18, 'flacon 50 mL'],
  ];
  const ins = db.prepare(
    'INSERT INTO produits (id_categorie, id_boutique, nom, description, prix_produit, quantite_stock, unite) VALUES (?, ?, ?, ?, ?, ?, ?)',
  );
  produits.forEach((p) => ins.run(...p));

  const regle = db.prepare('INSERT OR REPLACE INTO regles_livraison (ville, frais, seuil_gratuite) VALUES (?, ?, ?)');
  regle.run('*', 3000, 150000);
  regle.run('Yaoundé', 1500, 100000);
  regle.run('Douala', 1500, 100000);
  regle.run('Bafoussam', 1000, 80000);
});

db.close();
console.log(`Base initialisée : ${config.dbFile}`);
console.log(`Comptes (mot de passe « ${MDP} ») :
  admin    690000001 / admin@agrophyto.cm
  vendeur  690000002 / vendeur@agrophyto.cm
  livreur  690000003 / livreur@agrophyto.cm
  client   690000004 / client@agrophyto.cm`);

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const { open } = require('../src/db');
const { createApp } = require('../src/app');
const { createMockPaymentProvider } = require('../src/services/payment');

let server;
let base;
let db;
let provider;
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'fonction-phyto-'));

async function api(method, url, { token, body } = {}) {
  const res = await fetch(base + url, {
    method,
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  return { status: res.status, data: text ? JSON.parse(text) : null };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitPaiement(id, token) {
  for (let i = 0; i < 50; i++) {
    const { data } = await api('GET', `/api/paiements/${id}`, { token });
    if (data.statut_paie !== 'en_attente') return data;
    await sleep(20);
  }
  throw new Error('paiement non résolu');
}

async function inscrire(telephone, extra = {}) {
  const r = await api('POST', '/api/auth/inscription', {
    body: { nom: 'Test', prenom: telephone, telephone, mot_de_passe: 'secret1', ...extra },
  });
  assert.equal(r.status, 201, JSON.stringify(r.data));
  return r.data;
}

function donnerRole(idUser, role) {
  db.prepare('INSERT OR IGNORE INTO user_roles (id_user, id_role) SELECT ?, id_role FROM roles WHERE nom = ?').run(idUser, role);
}

const T = {};

before(async () => {
  db = open(':memory:');
  provider = createMockPaymentProvider({ delayMs: 30 });
  const app = createApp({ db, paymentProvider: provider, config: { uploadDir: tmp } });
  await new Promise((resolve) => {
    server = app.listen(0, resolve);
  });
  base = `http://127.0.0.1:${server.address().port}`;

  const admin = await inscrire('600000001');
  donnerRole(admin.utilisateur.id_user, 'admin');
  T.admin = (await api('POST', '/api/auth/connexion', { body: { identifiant: '600000001', mot_de_passe: 'secret1' } })).data.token;

  T.vendeurInfo = await inscrire('600000002', { type_compte: 'vendeur' });
  T.vendeur = T.vendeurInfo.token;
  T.livreurInfo = await inscrire('600000003');
  donnerRole(T.livreurInfo.utilisateur.id_user, 'livreur');
  T.livreur = T.livreurInfo.token;
  T.clientInfo = await inscrire('600000004', { email: 'client@test.cm' });
  T.client = T.clientInfo.token;
});

after(() => {
  provider.close();
  server.close();
  db.close();
  fs.rmSync(tmp, { recursive: true, force: true });
});

test('authentification : identifiants incorrects puis déconnexion', async () => {
  const ko = await api('POST', '/api/auth/connexion', { body: { identifiant: '600000004', mot_de_passe: 'faux' } });
  assert.equal(ko.status, 401);
  assert.equal(ko.data.erreur, "Nom d'utilisateur ou mot de passe incorrect");

  await inscrire('600000099');
  const login = await api('POST', '/api/auth/connexion', { body: { identifiant: '600000099', mot_de_passe: 'secret1' } });
  assert.equal(login.status, 200);
  assert.ok(login.data.utilisateur.derniere_connexion);
  assert.deepEqual(login.data.utilisateur.roles, ['client']);
  assert.equal((await api('POST', '/api/auth/deconnexion', { token: login.data.token })).status, 200);
  assert.equal((await api('GET', '/api/compte', { token: login.data.token })).status, 401);
});

test('compte de démonstration : connexion sans mot de passe par profil', async () => {
  // Compte client de démonstration (téléphone du jeu de données « npm run seed »).
  await inscrire('690000004');

  const ok = await api('POST', '/api/auth/demo', { body: { profil: 'client' } });
  assert.equal(ok.status, 200);
  assert.deepEqual(ok.data.utilisateur.roles, ['client']);
  assert.equal((await api('GET', '/api/compte', { token: ok.data.token })).status, 200);

  // Compte partagé : une déconnexion n'invalide pas la session des autres visiteurs.
  const autre = await api('POST', '/api/auth/demo', { body: { profil: 'client' } });
  assert.equal((await api('POST', '/api/auth/deconnexion', { token: autre.data.token })).status, 200);
  assert.equal((await api('GET', '/api/compte', { token: ok.data.token })).status, 200);

  assert.equal((await api('POST', '/api/auth/demo', { body: { profil: 'constructor' } })).status, 400);
  assert.equal((await api('POST', '/api/auth/demo', { body: { profil: 'admin' } })).status, 404);
});

test('gestion des produits : permissions, doublon, modification, suppression', async () => {
  const cat = await api('POST', '/api/categories', { token: T.admin, body: { nom: 'Herbicides', type: 'phytosanitaire' } });
  assert.equal(cat.status, 201);
  T.categorie = cat.data.id_categorie;
  assert.equal((await api('POST', '/api/categories', { token: T.client, body: { nom: 'X' } })).status, 403);

  const produit = { nom: 'Glyphosate', id_categorie: T.categorie, prix_produit: 5000, quantite_stock: 10 };
  const sansBoutique = await api('POST', '/api/produits', { token: T.vendeur, body: produit });
  assert.equal(sansBoutique.status, 400);

  assert.equal((await api('POST', '/api/boutiques', { token: T.vendeur, body: { nom: 'Ma boutique', ville: 'Yaoundé' } })).status, 201);
  const ajout = await api('POST', '/api/produits', { token: T.vendeur, body: produit });
  assert.equal(ajout.status, 201);
  T.produit = ajout.data.id_produit;
  const doublon = await api('POST', '/api/produits', { token: T.vendeur, body: produit });
  assert.equal(doublon.status, 409);
  assert.equal(doublon.data.erreur, 'Produit existant');

  assert.equal((await api('PUT', `/api/produits/${T.produit}`, { token: T.client, body: { prix_produit: 1 } })).status, 403);
  const modif = await api('PUT', `/api/produits/${T.produit}`, { token: T.vendeur, body: { prix_produit: 4500 } });
  assert.equal(modif.data.prix_produit, 4500);
  assert.equal((await api('PUT', '/api/produits/9999', { token: T.vendeur, body: produit })).status, 404);

  const tmpProduit = await api('POST', '/api/produits', { token: T.vendeur, body: { ...produit, nom: 'Temp' } });
  assert.equal((await api('DELETE', `/api/produits/${tmpProduit.data.id_produit}`, { token: T.vendeur })).status, 204);
  assert.equal((await api('DELETE', `/api/produits/${tmpProduit.data.id_produit}`, { token: T.vendeur })).status, 404);

  const brouillon = await api('POST', '/api/produits', { token: T.vendeur, body: { ...produit, nom: 'Caché', statut: 'brouillon' } });
  const recherche = await api('GET', '/api/produits?q=a&prix_max=10000');
  assert.ok(recherche.data.some((p) => p.id_produit === T.produit));
  assert.ok(!recherche.data.some((p) => p.id_produit === brouillon.data.id_produit));
});

test('panier, commande, paiement, livraison et avis (parcours complet)', async () => {
  const vide = await api('POST', '/api/commandes/recapitulatif', { token: T.client, body: {} });
  assert.equal(vide.status, 400);
  assert.equal(vide.data.erreur, 'Panier vide');

  assert.equal((await api('POST', '/api/panier/items', { token: T.client, body: { id_produit: T.produit, quantite: 20 } })).status, 409);
  let panier = await api('POST', '/api/panier/items', { token: T.client, body: { id_produit: T.produit, quantite: 2 } });
  panier = await api('PATCH', `/api/panier/items/${T.produit}`, { token: T.client, body: { quantite: 3 } });
  assert.equal(panier.data.sous_total, 13500);

  const recap = await api('POST', '/api/commandes/recapitulatif', { token: T.client, body: { ville: 'Yaoundé' } });
  assert.equal(recap.data.frais_livraison, 2000);
  assert.equal(recap.data.total, 15500);

  const avisTropTot = await api('POST', `/api/produits/${T.produit}/avis`, { token: T.client, body: { note_avis: 5 } });
  assert.equal(avisTropTot.status, 403);

  const cmd = await api('POST', '/api/commandes', {
    token: T.client,
    body: { adresse_livraison: 'Essos', ville: 'Yaoundé', telephone_livraison: '600000004' },
  });
  assert.equal(cmd.status, 201);
  assert.equal(cmd.data.statut_commande, 'en_attente_paiement');
  assert.equal(cmd.data.total_commande, 15500);
  const id = cmd.data.id_commande;
  assert.equal((await api('GET', `/api/produits/${T.produit}`)).data.quantite_stock, 7);
  assert.equal((await api('GET', '/api/panier', { token: T.client })).data.items.length, 0);
  assert.equal((await api('GET', `/api/commandes/${id}`, { token: T.livreur })).status, 404);

  // Paiement refusé puis réessai accepté.
  const refuse = await api('POST', '/api/paiements', { token: T.client, body: { id_commande: id, mode_paie: 'MTN_MOMO', telephone: '670000000' } });
  assert.equal(refuse.status, 202);
  assert.equal((await waitPaiement(refuse.data.id_payement, T.client)).statut_paie, 'echoue');

  const ok = await api('POST', '/api/paiements', { token: T.client, body: { id_commande: id, mode_paie: 'ORANGE_MONEY', telephone: '690000004' } });
  const doublePaiement = await api('POST', '/api/paiements', { token: T.client, body: { id_commande: id, mode_paie: 'MTN_MOMO', telephone: '690000004' } });
  assert.equal(doublePaiement.status, 409);
  const reussi = await waitPaiement(ok.data.id_payement, T.client);
  assert.equal(reussi.statut_paie, 'reussi');
  assert.match(reussi.numero_facture, /^FAC-/);
  assert.equal(reussi.statut_commande, 'en_cours');

  const dejaPayee = await api('POST', '/api/paiements', { token: T.client, body: { id_commande: id, mode_paie: 'MTN_MOMO', telephone: '690000004' } });
  assert.equal(dejaPayee.data.erreur, 'Commande introuvable ou déjà payée');

  // Livraison.
  assert.equal((await api('GET', '/api/livraisons', { token: T.client })).status, 403);
  const liste = await api('GET', '/api/livraisons', { token: T.livreur });
  assert.ok(liste.data.disponibles.some((c) => c.id_commande === id));
  assert.equal((await api('POST', `/api/livraisons/${id}/confirmer`, { token: T.livreur })).status, 409);
  const prise = await api('POST', `/api/livraisons/${id}/prendre`, { token: T.livreur });
  assert.equal(prise.data.statut_commande, 'en_livraison');
  assert.equal((await api('POST', `/api/livraisons/${id}/prendre`, { token: T.livreur })).data.erreur, 'Commande indisponible');
  const livree = await api('POST', `/api/livraisons/${id}/confirmer`, { token: T.livreur });
  assert.equal(livree.data.statut_commande, 'livree');

  // Avis produit et commande.
  const avis = await api('POST', `/api/produits/${T.produit}/avis`, { token: T.client, body: { note_avis: 4, commentaire: 'Efficace' } });
  assert.equal(avis.status, 201);
  assert.equal((await api('GET', `/api/produits/${T.produit}`)).data.note_moyenne, 4);
  assert.equal((await api('POST', `/api/commandes/${id}/avis`, { token: T.client, body: { note_avis: 5 } })).status, 201);

  // Notifications et ventes vendeur.
  const notifs = await api('GET', '/api/notifications', { token: T.client });
  assert.ok(notifs.data.items.some((n) => n.titre === `Commande #${id} : Confirmée` && /Paiement de 15500 FCFA/.test(n.message)));
  assert.ok(notifs.data.items.some((n) => n.titre === `Commande #${id} : Livrée`));

  // Le client confirme la réception : la commande est clôturée, chaque étape est historisée.
  assert.equal((await api('POST', `/api/commandes/${id}/reception`, { token: T.livreur })).status, 404);
  const cloturee = await api('POST', `/api/commandes/${id}/reception`, { token: T.client });
  assert.equal(cloturee.data.statut_commande, 'cloturee');
  assert.equal(cloturee.data.libelle_statut, 'Clôturée');
  assert.deepEqual(
    cloturee.data.historique.map((h) => h.libelle),
    ['Reçue', 'Confirmée', 'En cours de livraison', 'Livrée', 'Clôturée'],
  );
  assert.equal((await api('POST', `/api/commandes/${id}/reception`, { token: T.client })).status, 409);
  const ventes = await api('GET', '/api/boutiques/moi/ventes', { token: T.vendeur });
  assert.equal(ventes.data[0].quantite, 3);

  // Statistiques admin.
  const stats = await api('GET', '/api/admin/statistiques', { token: T.admin });
  assert.equal(stats.data.chiffre_affaires, 15500);
  assert.equal((await api('GET', '/api/admin/statistiques', { token: T.vendeur })).status, 403);
});

test('annulation restitue le stock et échec de livraison', async () => {
  await api('POST', '/api/panier/items', { token: T.client, body: { id_produit: T.produit, quantite: 2 } });
  const body = { adresse_livraison: 'Essos', ville: 'Yaoundé', telephone_livraison: '600000004' };
  const c1 = await api('POST', '/api/commandes', { token: T.client, body });
  assert.equal((await api('GET', `/api/produits/${T.produit}`)).data.quantite_stock, 5);
  const annule = await api('POST', `/api/commandes/${c1.data.id_commande}/annuler`, { token: T.client });
  assert.equal(annule.data.statut_commande, 'annulee');
  assert.equal((await api('GET', `/api/produits/${T.produit}`)).data.quantite_stock, 7);

  await api('POST', '/api/panier/items', { token: T.client, body: { id_produit: T.produit, quantite: 1 } });
  const c2 = await api('POST', '/api/commandes', { token: T.client, body });
  const p = await api('POST', '/api/paiements', { token: T.client, body: { id_commande: c2.data.id_commande, mode_paie: 'MTN_MOMO', telephone: '690000004' } });
  await waitPaiement(p.data.id_payement, T.client);
  await api('POST', `/api/livraisons/${c2.data.id_commande}/prendre`, { token: T.livreur });
  const echec = await api('POST', `/api/livraisons/${c2.data.id_commande}/echec`, { token: T.livreur, body: { motif: 'Client absent' } });
  assert.equal(echec.data.statut_commande, 'echec_livraison');
  assert.equal(echec.data.motif_echec, 'Client absent');

  const relance = await api('PATCH', `/api/admin/commandes/${c2.data.id_commande}/statut`, { token: T.admin, body: { statut: 'en_preparation' } });
  assert.equal(relance.data.statut_commande, 'en_preparation');
  assert.equal(relance.data.id_livreur, null);
  const interdit = await api('PATCH', `/api/admin/commandes/${c2.data.id_commande}/statut`, { token: T.admin, body: { statut: 'livree' } });
  assert.equal(interdit.status, 409);
});

test('administration : utilisateurs, rôles, règles de livraison', async () => {
  const users = await api('GET', '/api/admin/utilisateurs?role=livreur', { token: T.admin });
  assert.equal(users.data.length, 1);
  const livreurs = await api('GET', '/api/admin/livreurs', { token: T.admin });
  const idsLivreurs = livreurs.data.map((u) => u.id_user);
  assert.ok(idsLivreurs.includes(T.livreurInfo.utilisateur.id_user));
  assert.ok(!idsLivreurs.includes(T.clientInfo.utilisateur.id_user));

  const idClient = T.clientInfo.utilisateur.id_user;
  await api('PATCH', `/api/admin/utilisateurs/${idClient}/actif`, { token: T.admin, body: { actif: false } });
  assert.equal((await api('GET', '/api/compte', { token: T.client })).status, 401);
  const bloque = await api('POST', '/api/auth/connexion', { body: { identifiant: 'client@test.cm', mot_de_passe: 'secret1' } });
  assert.equal(bloque.status, 403);
  await api('PATCH', `/api/admin/utilisateurs/${idClient}/actif`, { token: T.admin, body: { actif: true } });
  T.client = (await api('POST', '/api/auth/connexion', { body: { identifiant: 'client@test.cm', mot_de_passe: 'secret1' } })).data.token;

  const roles = await api('PUT', `/api/admin/utilisateurs/${idClient}/roles`, { token: T.admin, body: { roles: ['client', 'livreur'] } });
  assert.ok(roles.data.permissions.includes('livraisons.effectuer'));
  assert.equal((await api('GET', '/api/livraisons', { token: T.client })).status, 200);

  await api('POST', '/api/admin/regles-livraison', { token: T.admin, body: { ville: 'Douala', frais: 1000, seuil_gratuite: 10000 } });
  const frais = await api('GET', '/api/livraisons/frais?ville=douala&sous_total=5000');
  assert.equal(frais.data.frais_livraison, 1000);
  assert.equal((await api('GET', '/api/livraisons/frais?ville=Douala&sous_total=20000')).data.frais_livraison, 0);
});

test('messagerie entre client et vendeur', async () => {
  const idVendeur = T.vendeurInfo.utilisateur.id_user;
  const envoi = await api('POST', '/api/messages', { token: T.client, body: { id_destinataire: idVendeur, contenu: 'Bonjour, livrez-vous à Douala ?' } });
  assert.equal(envoi.status, 201);
  const conv = await api('GET', '/api/messages/conversations', { token: T.vendeur });
  assert.equal(conv.data[0].non_lus, 1);
  const fil = await api('GET', `/api/messages/${T.clientInfo.utilisateur.id_user}`, { token: T.vendeur });
  assert.equal(fil.data.messages.length, 1);
  assert.equal((await api('GET', '/api/messages/non-lus', { token: T.vendeur })).data.non_lus, 0);
  assert.equal((await api('GET', '/api/messages/support', { token: T.client })).status, 200);
});

test('paramètres : l’administrateur ferme puis rouvre la création de boutiques', async () => {
  assert.equal((await api('GET', '/api/parametres')).data.creation_boutique, true);
  assert.equal((await api('PUT', '/api/admin/parametres', { token: T.client, body: { creation_boutique: false } })).status, 403);
  assert.equal((await api('PUT', '/api/admin/parametres', { token: T.admin, body: { inconnu: true } })).status, 400);
  assert.equal((await api('PUT', '/api/admin/parametres', { token: T.admin, body: { creation_boutique: 'non' } })).status, 400);

  const ferme = await api('PUT', '/api/admin/parametres', { token: T.admin, body: { creation_boutique: false } });
  assert.equal(ferme.status, 200);
  assert.equal(ferme.data.creation_boutique, false);
  assert.equal((await api('GET', '/api/parametres')).data.creation_boutique, false);

  // Un utilisateur ne peut plus ouvrir de boutique ni s'inscrire comme vendeur.
  const client = await inscrire('600000150');
  const refus = await api('POST', '/api/boutiques', { token: client.token, body: { nom: 'Ma boutique' } });
  assert.equal(refus.status, 403);
  const inscriptionVendeur = await api('POST', '/api/auth/inscription', {
    body: { nom: 'V', prenom: 'V', telephone: '600000151', mot_de_passe: 'secret1', type_compte: 'vendeur' },
  });
  assert.equal(inscriptionVendeur.status, 403);
  // L'administrateur, lui, le peut toujours.
  assert.equal((await api('POST', '/api/boutiques', { token: T.admin, body: { nom: 'Boutique admin' } })).status, 201);

  await api('PUT', '/api/admin/parametres', { token: T.admin, body: { creation_boutique: true } });
  assert.equal((await api('POST', '/api/boutiques', { token: client.token, body: { nom: 'Ma boutique' } })).status, 201);
});

test('suivi de livraison : validation, préparation, affectation d’un livreur, tableau de bord', async () => {
  await api('POST', '/api/panier/items', { token: T.client, body: { id_produit: T.produit, quantite: 1 } });
  const cmd = await api('POST', '/api/commandes', {
    token: T.client,
    body: { adresse_livraison: 'Bastos', ville: 'Douala', telephone_livraison: '600000004' },
  });
  const id = cmd.data.id_commande;
  const patch = (url, body, token = T.admin) => api('PATCH', `/api/admin/commandes/${id}${url}`, { token, body });

  // Filtres de la liste administrateur.
  const filtre = await api('GET', '/api/admin/commandes?statut=en_attente_paiement,en_cours&ville=douala', { token: T.admin });
  assert.ok(filtre.data.some((c) => c.id_commande === id && c.libelle_statut === 'Reçue'));
  assert.equal((await api('GET', `/api/admin/commandes?q=%23${id}`, { token: T.admin })).data.length, 1);
  assert.equal((await api('GET', '/api/admin/commandes?du=2020-13-01', { token: T.admin })).status, 400);

  // Validation manuelle (paiement à la livraison), puis préparation.
  assert.equal((await patch('/livreur', { id_livreur: T.livreurInfo.utilisateur.id_user })).status, 409);
  assert.equal((await patch('/statut', { statut: 'en_cours' })).data.statut_commande, 'en_cours');
  assert.equal((await patch('/statut', { statut: 'en_preparation' })).data.statut_commande, 'en_preparation');

  // Affectation : la commande n'est plus proposée aux autres livreurs mais apparaît chez le livreur désigné.
  assert.equal((await patch('/livreur', { id_livreur: T.vendeurInfo.utilisateur.id_user })).status, 400);
  const affectee = await patch('/livreur', { id_livreur: T.livreurInfo.utilisateur.id_user });
  assert.equal(affectee.data.id_livreur, T.livreurInfo.utilisateur.id_user);
  assert.equal(affectee.data.statut_commande, 'en_preparation');
  const tournee = await api('GET', '/api/livraisons', { token: T.livreur });
  assert.ok(!tournee.data.disponibles.some((c) => c.id_commande === id));
  assert.ok(tournee.data.mes_livraisons.some((c) => c.id_commande === id));

  const stats = await api('GET', '/api/admin/statistiques', { token: T.admin });
  for (const cle of ['commandes_jour', 'chiffre_affaires_jour', 'chiffre_affaires_mois', 'livraisons_en_cours', 'a_preparer']) {
    assert.equal(typeof stats.data[cle], 'number', cle);
  }
  assert.ok(stats.data.a_preparer >= 1);

  assert.equal((await api('POST', `/api/livraisons/${id}/prendre`, { token: T.livreur })).data.statut_commande, 'en_livraison');
  assert.equal((await api('GET', '/api/admin/statistiques', { token: T.admin })).data.livraisons_en_cours, stats.data.livraisons_en_cours + 1);
  await api('POST', `/api/livraisons/${id}/confirmer`, { token: T.livreur });
  const fin = await patch('/statut', { statut: 'cloturee' });
  assert.equal(fin.data.statut_commande, 'cloturee');
  assert.ok(fin.data.historique.some((h) => /Livreur affecté/.test(h.commentaire || '')));

  // Le client a été prévenu à chaque étape.
  const notifs = (await api('GET', '/api/notifications', { token: T.client })).data.items.map((n) => n.titre);
  for (const libelle of ['Reçue', 'Confirmée', 'En préparation', 'En cours de livraison', 'Livrée', 'Clôturée']) {
    assert.ok(notifs.includes(`Commande #${id} : ${libelle}`), libelle);
  }
});

test('sécurité : double authentification, blocage après échecs, journal d’activité', async () => {
  const totp = require('../src/services/totp');
  const tel = '600000009';
  const compte = await inscrire(tel);
  const token = compte.token;

  assert.equal((await api('POST', '/api/compte/2fa/initier', { token, body: { mot_de_passe: 'mauvais' } })).status, 400);
  const init = await api('POST', '/api/compte/2fa/initier', { token, body: { mot_de_passe: 'secret1' } });
  assert.match(init.data.otpauth, /^otpauth:\/\/totp\/fonction%20Phyto/);
  assert.equal((await api('POST', '/api/compte/2fa/activer', { token, body: { code: '000000' } })).status, 400);
  const active = await api('POST', '/api/compte/2fa/activer', { token, body: { code: totp.codeTotp(init.data.secret) } });
  assert.equal(active.data.totp_actif, true);
  assert.equal(active.data.totp_secret, undefined);

  // Connexion en deux étapes.
  const etape1 = await api('POST', '/api/auth/connexion', { body: { identifiant: tel, mot_de_passe: 'secret1' } });
  assert.equal(etape1.data.deux_facteurs, true);
  assert.equal(etape1.data.token, undefined);
  const etape2 = await api('POST', '/api/auth/connexion', {
    body: { identifiant: tel, mot_de_passe: 'secret1', code: totp.codeTotp(init.data.secret) },
  });
  assert.ok(etape2.data.token);

  // Blocage après 5 échecs, même avec le bon mot de passe.
  for (let i = 0; i < 5; i++) {
    await api('POST', '/api/auth/connexion', { body: { identifiant: tel, mot_de_passe: 'secret1', code: '000000' } });
  }
  assert.equal((await api('POST', '/api/auth/connexion', { body: { identifiant: tel, mot_de_passe: 'secret1' } })).status, 429);

  const journal = await api('GET', `/api/admin/journal?id_user=${compte.utilisateur.id_user}`, { token: T.admin });
  const actions = journal.data.map((j) => j.action);
  assert.ok(actions.includes('compte.2fa.activer'));
  assert.ok(actions.includes('connexion'));
  assert.ok(actions.includes('connexion.echec'));
  assert.equal((await api('GET', '/api/admin/journal', { token: T.client })).status, 403);

  // Mot de passe fort exigé des administrateurs.
  const faible = await api('PUT', '/api/compte/mot-de-passe', { token: T.admin, body: { ancien: 'secret1', nouveau: 'simple1' } });
  assert.equal(faible.status, 400);
});

test('suppression de compte : données personnelles effacées, connexion impossible', async () => {
  const tel = '600000010';
  const compte = await inscrire(tel, { email: 'efface@test.cm' });
  assert.equal((await api('DELETE', '/api/compte', { token: compte.token, body: { mot_de_passe: 'faux' } })).status, 400);
  assert.equal((await api('DELETE', '/api/compte', { token: compte.token, body: { mot_de_passe: 'secret1' } })).status, 204);
  assert.equal((await api('GET', '/api/compte', { token: compte.token })).status, 401);
  assert.equal((await api('POST', '/api/auth/connexion', { body: { identifiant: tel, mot_de_passe: 'secret1' } })).status, 401);
  const u = db.prepare('SELECT * FROM users WHERE id_user = ?').get(compte.utilisateur.id_user);
  assert.equal(u.email, null);
  assert.equal(u.telephone, `supprime-${u.id_user}`);
  // L'identifiant est de nouveau libre.
  await inscrire(tel);
});

/** Paramètres de la plateforme modifiables par l'administrateur (stockés en texte, exposés typés). */
const DEFAUTS = {
  // Les utilisateurs peuvent-ils ouvrir une boutique (devenir vendeur) eux-mêmes ?
  creation_boutique: true,
};

function lireParametres(db) {
  const rows = db.prepare('SELECT cle, valeur FROM parametres').all();
  const valeurs = Object.fromEntries(rows.map((r) => [r.cle, r.valeur]));
  return Object.fromEntries(
    Object.entries(DEFAUTS).map(([cle, defaut]) => [cle, cle in valeurs ? valeurs[cle] === '1' : defaut]),
  );
}

function ecrireParametre(db, cle, valeur) {
  db.prepare(
    `INSERT INTO parametres (cle, valeur) VALUES (?, ?)
     ON CONFLICT (cle) DO UPDATE SET valeur = excluded.valeur, date_modification = datetime('now')`,
  ).run(cle, valeur ? '1' : '0');
}

module.exports = { DEFAUTS_PARAMETRES: DEFAUTS, lireParametres, ecrireParametre };

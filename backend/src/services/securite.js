const { HttpError, badRequest } = require('../errors');

/** Mot de passe fort exigé des administrateurs : 10 caractères, minuscule, majuscule et chiffre. */
function verifierMotDePasseFort(mdp) {
  const s = String(mdp || '');
  if (s.length < 10 || !/[a-z]/.test(s) || !/[A-Z]/.test(s) || !/\d/.test(s)) {
    throw badRequest('Mot de passe administrateur trop faible : 10 caractères minimum, avec majuscule, minuscule et chiffre');
  }
}

/**
 * Limite les tentatives de connexion par identifiant : après MAX échecs,
 * l'identifiant est bloqué pendant DUREE (protège mot de passe et code 2FA).
 */
function createLimiteur({ max = 5, dureeMs = 15 * 60 * 1000 } = {}) {
  const echecs = new Map();
  const cle = (identifiant) => String(identifiant).trim().toLowerCase();

  function verifier(identifiant) {
    const e = echecs.get(cle(identifiant));
    if (!e) return;
    if (e.jusqua && e.jusqua > Date.now()) {
      const minutes = Math.ceil((e.jusqua - Date.now()) / 60000);
      throw new HttpError(429, `Trop de tentatives. Réessayez dans ${minutes} min.`);
    }
    if (e.jusqua) echecs.delete(cle(identifiant));
  }

  function echec(identifiant) {
    const k = cle(identifiant);
    const e = echecs.get(k) || { nombre: 0, jusqua: null };
    e.nombre += 1;
    if (e.nombre >= max) e.jusqua = Date.now() + dureeMs;
    echecs.set(k, e);
  }

  const reussite = (identifiant) => echecs.delete(cle(identifiant));

  return { verifier, echec, reussite };
}

module.exports = { verifierMotDePasseFort, createLimiteur };

class HttpError extends Error {
  constructor(status, message, details) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

const badRequest = (msg, details) => new HttpError(400, msg, details);
const unauthorized = (msg = 'Authentification requise') => new HttpError(401, msg);
const forbidden = (msg = 'Accès refusé') => new HttpError(403, msg);
const notFound = (msg = 'Ressource introuvable') => new HttpError(404, msg);
const conflict = (msg, details) => new HttpError(409, msg, details);

/** Vérifie les champs obligatoires d'un corps de requête. */
function requireFields(body, fields) {
  const manquants = fields.filter((f) => body?.[f] === undefined || body[f] === null || String(body[f]).trim() === '');
  if (manquants.length) throw badRequest(`Champs obligatoires manquants : ${manquants.join(', ')}`);
}

function toInt(value, name, { min } = {}) {
  const n = Number(value);
  if (!Number.isInteger(n) || (min !== undefined && n < min)) {
    throw badRequest(`${name} doit être un entier${min !== undefined ? ` ≥ ${min}` : ''}`);
  }
  return n;
}

module.exports = { HttpError, badRequest, unauthorized, forbidden, notFound, conflict, requireFields, toInt };

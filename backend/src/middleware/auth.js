const jwt = require('jsonwebtoken');
const config = require('../config');
const { unauthorized, forbidden } = require('../errors');

function signToken(user) {
  return jwt.sign({ sub: user.id_user, tv: user.token_version }, config.jwtSecret, {
    expiresIn: config.jwtExpiresIn,
  });
}

function loadRolesAndPermissions(db, idUser) {
  const roles = db
    .prepare('SELECT r.nom FROM roles r JOIN user_roles ur ON ur.id_role = r.id_role WHERE ur.id_user = ?')
    .all(idUser)
    .map((r) => r.nom);
  const permissions = db
    .prepare(
      `SELECT DISTINCT p.nom FROM permissions p
       JOIN role_permissions rp ON rp.id_permission = p.id_permission
       JOIN user_roles ur ON ur.id_role = rp.id_role
       WHERE ur.id_user = ?`,
    )
    .all(idUser)
    .map((p) => p.nom);
  return { roles, permissions };
}

/** Middleware : exige un jeton valide et un compte actif ; renseigne req.user. */
function authenticate(db, { optional = false } = {}) {
  return (req, _res, next) => {
    const header = req.get('authorization') || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token) {
      if (optional) return next();
      throw unauthorized();
    }
    let payload;
    try {
      payload = jwt.verify(token, config.jwtSecret);
    } catch {
      throw unauthorized('Session expirée ou invalide');
    }
    const user = db.prepare('SELECT * FROM users WHERE id_user = ?').get(payload.sub);
    if (!user || user.token_version !== payload.tv) throw unauthorized('Session expirée ou invalide');
    if (!user.actif) throw forbidden('Compte désactivé');
    req.user = { ...user, ...loadRolesAndPermissions(db, user.id_user) };
    next();
  };
}

/** Middleware : exige au moins une des permissions données. */
function requirePermission(...perms) {
  return (req, _res, next) => {
    if (!req.user) throw unauthorized();
    if (!perms.some((p) => req.user.permissions.includes(p))) throw forbidden();
    next();
  };
}

const hasPermission = (user, perm) => Boolean(user?.permissions.includes(perm));

module.exports = { signToken, authenticate, requirePermission, hasPermission, loadRolesAndPermissions };

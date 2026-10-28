const crypto = require('node:crypto');

// Double authentification par code à usage unique (RFC 6238), compatible
// Google Authenticator, Microsoft Authenticator, 2FAS…
const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const PERIODE = 30;

function base32Encode(buf) {
  let bits = 0;
  let valeur = 0;
  let out = '';
  for (const octet of buf) {
    valeur = (valeur << 8) | octet;
    bits += 8;
    while (bits >= 5) {
      out += ALPHABET[(valeur >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += ALPHABET[(valeur << (5 - bits)) & 31];
  return out;
}

function base32Decode(str) {
  let bits = 0;
  let valeur = 0;
  const out = [];
  for (const c of str.replace(/=+$/, '').toUpperCase()) {
    const i = ALPHABET.indexOf(c);
    if (i < 0) continue;
    valeur = (valeur << 5) | i;
    bits += 5;
    if (bits >= 8) {
      out.push((valeur >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return Buffer.from(out);
}

const genererSecret = () => base32Encode(crypto.randomBytes(20));

function codeTotp(secret, instant = Date.now()) {
  const compteur = Buffer.alloc(8);
  compteur.writeBigUInt64BE(BigInt(Math.floor(instant / 1000 / PERIODE)));
  const hmac = crypto.createHmac('sha1', base32Decode(secret)).update(compteur).digest();
  const offset = hmac[hmac.length - 1] & 0xf;
  const n = (hmac.readUInt32BE(offset) & 0x7fffffff) % 1_000_000;
  return String(n).padStart(6, '0');
}

/** Vérifie un code en tolérant un décalage d'horloge de ±30 s. */
function verifierCode(secret, code, instant = Date.now()) {
  const saisi = String(code || '').replace(/\s/g, '');
  if (!/^\d{6}$/.test(saisi)) return false;
  return [-1, 0, 1].some((d) => codeTotp(secret, instant + d * PERIODE * 1000) === saisi);
}

const lienOtpauth = (secret, compte, emetteur = 'fonction Phyto') =>
  `otpauth://totp/${encodeURIComponent(`${emetteur}:${compte}`)}?secret=${secret}&issuer=${encodeURIComponent(emetteur)}`;

module.exports = { genererSecret, codeTotp, verifierCode, lienOtpauth };

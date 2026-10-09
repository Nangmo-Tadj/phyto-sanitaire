const crypto = require('node:crypto');

/**
 * Acteur externe « Système de paiement » (MTN MoMo / Orange Money).
 *
 * Contrat d'un fournisseur :
 *   requestPayment({ reference, montant, telephone, mode }) -> Promise<void>
 *     Envoie la demande ; le client confirme sur son téléphone, puis
 *     l'opérateur renvoie le résultat via onResult(reference, succes, message)
 *     (en production : webhook POST /api/paiements/callback).
 *
 * Le fournisseur simulé ci-dessous accepte tous les paiements, sauf pour les
 * numéros se terminant par « 0000 » (utile pour tester le cas « Paiement refusé »).
 */
function createMockPaymentProvider({ delayMs = 4000 } = {}) {
  let onResult = () => {};
  const timers = new Set();

  return {
    name: 'mock',
    setResultHandler(fn) {
      onResult = fn;
    },
    async requestPayment({ reference, telephone }) {
      const refuse = String(telephone).endsWith('0000');
      const t = setTimeout(() => {
        timers.delete(t);
        onResult(
          reference,
          !refuse,
          refuse ? 'Transaction refusée par l’opérateur (solde insuffisant)' : 'Paiement confirmé par l’opérateur',
        );
      }, delayMs);
      timers.add(t);
    },
    close() {
      timers.forEach(clearTimeout);
      timers.clear();
    },
  };
}

const newReference = () => `TX-${Date.now()}-${crypto.randomBytes(4).toString('hex').toUpperCase()}`;

module.exports = { createMockPaymentProvider, newReference };

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';

final _fcfa = NumberFormat.decimalPattern('fr_FR');

String fcfa(int montant) => '${_fcfa.format(montant).replaceAll(' ', ' ')} FCFA';

String dateCourte(DateTime? d) => d == null ? '' : DateFormat('dd/MM/yyyy').format(d);
String dateHeure(DateTime? d) => d == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(d);
String heure(DateTime? d) => d == null ? '' : DateFormat('HH:mm').format(d);

String libelleStatut(String statut) =>
    const {
      StatutCommande.enAttentePaiement: 'En attente de paiement',
      StatutCommande.enCours: 'Payée · en préparation',
      StatutCommande.enLivraison: 'En livraison',
      StatutCommande.livree: 'Livrée',
      StatutCommande.echecLivraison: 'Échec de livraison',
      StatutCommande.annulee: 'Annulée',
    }[statut] ??
    statut;

Color couleurStatut(String statut) =>
    const {
      StatutCommande.enAttentePaiement: Color(0xFFB26A00),
      StatutCommande.enCours: Color(0xFF1565C0),
      StatutCommande.enLivraison: Color(0xFF6A1B9A),
      StatutCommande.livree: Color(0xFF2E7D32),
      StatutCommande.echecLivraison: Color(0xFFC62828),
      StatutCommande.annulee: Color(0xFF616161),
    }[statut] ??
    Colors.grey;

String libelleModePaiement(String mode) => mode == 'MTN_MOMO'
    ? 'MTN Mobile Money'
    : mode == 'ORANGE_MONEY'
    ? 'Orange Money'
    : mode;

String libelleStatutProduit(String statut) =>
    const {'publie': 'Publié', 'brouillon': 'Brouillon', 'retire': 'Retiré'}[statut] ?? statut;

String libelleRole(String role) =>
    const {'client': 'Client', 'vendeur': 'Vendeur', 'livreur': 'Livreur', 'admin': 'Administrateur'}[role] ?? role;

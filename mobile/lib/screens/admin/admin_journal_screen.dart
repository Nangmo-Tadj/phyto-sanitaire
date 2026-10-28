import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

const _filtres = <(String, String?)>[
  ('Tout', null),
  ('Connexions', 'connexion'),
  ('Commandes', 'commande'),
  ('Utilisateurs', 'utilisateur'),
  ('Rôles', 'role'),
  ('Paramètres', 'parametres'),
  ('Compte', 'compte'),
];

const _libellesActions = {
  'connexion': 'Connexion',
  'connexion.echec': 'Échec de connexion',
  'connexion.demo': 'Connexion de démonstration',
  'commande.statut': 'Statut de commande modifié',
  'commande.livreur': 'Livreur affecté',
  'utilisateur.activer': 'Compte activé',
  'utilisateur.desactiver': 'Compte désactivé',
  'utilisateur.roles': 'Rôles modifiés',
  'role.creer': 'Rôle créé',
  'role.permissions': 'Permissions d\'un rôle modifiées',
  'parametres.modifier': 'Paramètres modifiés',
  'boutique.activer': 'Boutique activée',
  'boutique.desactiver': 'Boutique désactivée',
  'livraison.regle': 'Règle de livraison enregistrée',
  'livraison.regle.supprimer': 'Règle de livraison supprimée',
  'compte.mot_de_passe': 'Mot de passe changé',
  'compte.2fa.activer': 'Double authentification activée',
  'compte.2fa.desactiver': 'Double authentification désactivée',
  'admin.creer': 'Administrateur créé',
  'admin.promouvoir': 'Administrateur promu',
};

IconData _iconeAction(String action) => switch (action.split('.').first) {
  'connexion' => Icons.login,
  'commande' => Icons.receipt_long,
  'utilisateur' => Icons.person_outline,
  'role' => Icons.admin_panel_settings_outlined,
  'parametres' => Icons.tune,
  'boutique' => Icons.storefront_outlined,
  'livraison' => Icons.local_shipping_outlined,
  'compte' => Icons.lock_outline,
  'admin' => Icons.shield_outlined,
  _ => Icons.history,
};

/// Journal d'activité : connexions et actions d'administration.
class AdminJournalScreen extends StatefulWidget {
  const AdminJournalScreen({super.key});

  @override
  State<AdminJournalScreen> createState() => _AdminJournalScreenState();
}

class _AdminJournalScreenState extends State<AdminJournalScreen> {
  final _entrees = <EntreeJournal>[];
  String? _action;
  bool _chargement = false;
  bool _fin = false;
  Object? _erreur;

  @override
  void initState() {
    super.initState();
    _charger(reinitialiser: true);
  }

  Future<void> _charger({bool reinitialiser = false}) async {
    if (_chargement) return;
    setState(() {
      _chargement = true;
      _erreur = null;
      if (reinitialiser) {
        _entrees.clear();
        _fin = false;
      }
    });
    try {
      final page = await context.read<Api>().journal(
        action: _action,
        avant: _entrees.isEmpty ? null : _entrees.last.id,
      );
      if (!mounted) return;
      setState(() {
        _entrees.addAll(page);
        // L'API renvoie au plus 50 entrées par page.
        _fin = page.length < 50;
      });
    } catch (e) {
      if (mounted) setState(() => _erreur = e);
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  void _filtrer(String? action) {
    if (action == _action) return;
    _action = action;
    _charger(reinitialiser: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Journal d\'activité')),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              children: [
                for (final (label, action) in _filtres)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _action == action,
                      onSelected: (_) => _filtrer(action),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(onRefresh: () => _charger(reinitialiser: true), child: _contenu()),
          ),
        ],
      ),
    );
  }

  Widget _contenu() {
    if (_entrees.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 60),
          if (_chargement)
            const Center(child: CircularProgressIndicator())
          else if (_erreur != null)
            EmptyState(
              icon: Icons.cloud_off,
              titre: 'Chargement impossible',
              message: '$_erreur',
              action: OutlinedButton(onPressed: () => _charger(reinitialiser: true), child: const Text('Réessayer')),
            )
          else
            const EmptyState(icon: Icons.history, titre: 'Aucune activité'),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _entrees.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i < _entrees.length) return _EntreeCard(entree: _entrees[i]);
        if (_fin) return const SizedBox(height: 8);
        return Center(
          child: _chargement
              ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())
              : TextButton.icon(
                  onPressed: _charger,
                  icon: const Icon(Icons.expand_more),
                  label: Text(_erreur == null ? 'Charger la suite' : 'Réessayer'),
                ),
        );
      },
    );
  }
}

class _EntreeCard extends StatelessWidget {
  const _EntreeCard({required this.entree});
  final EntreeJournal entree;

  @override
  Widget build(BuildContext context) {
    final e = entree;
    final echec = e.action == 'connexion.echec';
    final couleur = echec ? Colors.red.shade700 : AppColors.vert;
    final gris = TextStyle(color: Colors.grey.shade600, fontSize: 12);
    return Card(
      color: echec ? Colors.red.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: couleur.withValues(alpha: 0.12),
              child: Icon(echec ? Icons.gpp_bad_outlined : _iconeAction(e.action), color: couleur, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _libellesActions[e.action] ?? e.action,
                    style: TextStyle(fontWeight: FontWeight.w600, color: echec ? couleur : null),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    e.utilisateur == null
                        ? 'Système'
                        : '${e.utilisateur}${e.telephone == null ? '' : ' · ${e.telephone}'}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  Text([dateHeure(e.date), if (e.ip != null) 'IP ${e.ip}'].join(' · '), style: gris),
                  if (e.details != null && e.details!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      e.details!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: gris.copyWith(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

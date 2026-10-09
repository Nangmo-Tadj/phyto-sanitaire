import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../utils/format.dart';

/// Gestion des utilisateurs (activation, attribution des rôles) et des boutiques.
class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Utilisateurs'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.people_outline), text: 'Utilisateurs'),
              Tab(icon: Icon(Icons.storefront_outlined), text: 'Boutiques'),
            ],
          ),
        ),
        body: const TabBarView(children: [_UtilisateursTab(), _BoutiquesTab()]),
      ),
    );
  }
}

// --- Utilisateurs -----------------------------------------------------------------

class _UtilisateursTab extends StatefulWidget {
  const _UtilisateursTab();

  @override
  State<_UtilisateursTab> createState() => _UtilisateursTabState();
}

class _UtilisateursTabState extends State<_UtilisateursTab> with AutomaticKeepAliveClientMixin {
  final _recherche = TextEditingController();
  Timer? _debounce;
  String? _role;
  List<Role> _roles = [];
  Future<List<User>>? _future;

  /// Changements d'activation appliqués localement (évite un rechargement complet).
  final Map<int, bool> _actifs = {};
  final Set<int> _enCours = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _charger();
    _chargerRoles();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _recherche.dispose();
    super.dispose();
  }

  void _charger() {
    _actifs.clear();
    _future = context.read<Api>().utilisateurs(q: _recherche.text.trim(), role: _role);
  }

  Future<void> _chargerRoles() async {
    try {
      final roles = await context.read<Api>().roles();
      if (mounted) setState(() => _roles = roles);
    } catch (_) {
      // Les filtres par rôle restent simplement indisponibles.
    }
  }

  Future<void> _rafraichir() async {
    setState(_charger);
    try {
      await _future;
    } catch (_) {}
  }

  void _onRecherche(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(_charger);
    });
  }

  Future<void> _basculerActif(User u, bool actif) async {
    if (!actif) {
      final ok = await confirmer(
        context,
        'Désactiver le compte',
        '${u.nomComplet} ne pourra plus se connecter et sa session sera fermée. Continuer ?',
        action: 'Désactiver',
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _enCours.add(u.id));
    try {
      await context.read<Api>().activerUtilisateur(u.id, actif);
      if (!mounted) return;
      setState(() => _actifs[u.id] = actif);
      showMessage(context, actif ? 'Compte activé' : 'Compte désactivé');
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    } finally {
      if (mounted) setState(() => _enCours.remove(u.id));
    }
  }

  Future<void> _modifierRoles(User u) async {
    final enregistre = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RolesSheet(user: u, roles: _roles),
    );
    if (enregistre == true && mounted) {
      showMessage(context, 'Rôles mis à jour');
      _rafraichir();
      // Ses propres rôles ont changé : recharger les permissions de la session.
      final auth = context.read<AuthState>();
      if (u.id == auth.user?.id) auth.rafraichir().catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final moi = context.watch<AuthState>().user;
    final peutAttribuer = moi?.can(Perm.rolesGerer) ?? false;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _recherche,
            onChanged: _onRecherche,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Nom, téléphone ou email',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: ListenableBuilder(
                listenable: _recherche,
                builder: (_, _) => _recherche.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _recherche.clear();
                          setState(_charger);
                        },
                      ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            children: [
              for (final r in [null, ..._roles.map((r) => r.nom)])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(r == null ? 'Tous' : libelleRole(r)),
                    selected: _role == r,
                    onSelected: (_) => setState(() {
                      _role = r;
                      _charger();
                    }),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _rafraichir,
            child: AsyncView<List<User>>(
              future: _future,
              onRetry: () => setState(_charger),
              builder: (context, users) {
                if (users.isEmpty) {
                  return ListView(
                    children: const [
                      SizedBox(height: 60),
                      EmptyState(icon: Icons.person_search, titre: 'Aucun utilisateur trouvé'),
                    ],
                  );
                }
                return ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: users.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final u = users[i];
                    final actif = _actifs[u.id] ?? u.actif;
                    final estMoi = u.id == moi?.id;
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: peutAttribuer ? () => _modifierRoles(u) : null,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: actif ? AppColors.vertClair : Colors.grey.shade200,
                                child: Text(
                                  u.prenom.isNotEmpty ? u.prenom[0].toUpperCase() : '?',
                                  style: TextStyle(
                                    color: actif ? AppColors.vert : Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      estMoi ? '${u.nomComplet} (vous)' : u.nomComplet,
                                      style: TextStyle(fontWeight: FontWeight.w600, color: actif ? null : Colors.grey),
                                    ),
                                    Text(u.telephone, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                    if (u.email != null && u.email!.isNotEmpty)
                                      Text(
                                        u.email!,
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: [
                                        for (final r in u.roles)
                                          Tag(libelleRole(r), color: r == 'admin' ? AppColors.terre : AppColors.vert),
                                        if (!actif) Tag('Désactivé', color: Colors.red.shade700),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              _enCours.contains(u.id)
                                  ? const Padding(
                                      padding: EdgeInsets.all(14),
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2.5),
                                      ),
                                    )
                                  : Tooltip(
                                      message: estMoi
                                          ? 'Vous ne pouvez pas désactiver votre compte'
                                          : (actif ? 'Désactiver' : 'Activer'),
                                      child: Switch(
                                        value: actif,
                                        onChanged: estMoi ? null : (v) => _basculerActif(u, v),
                                      ),
                                    ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _RolesSheet extends StatefulWidget {
  const _RolesSheet({required this.user, required this.roles});
  final User user;
  final List<Role> roles;

  @override
  State<_RolesSheet> createState() => _RolesSheetState();
}

class _RolesSheetState extends State<_RolesSheet> {
  late final Set<String> _selection = {...widget.user.roles};
  late Future<List<Role>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.roles.isNotEmpty ? Future.value(widget.roles) : context.read<Api>().roles();
  }

  Future<void> _enregistrer() async {
    // Conserver l'ordre des rôles tel que défini côté serveur.
    final roles = await _future;
    final noms = [
      ...roles.map((r) => r.nom).where(_selection.contains),
      ..._selection.where((n) => !roles.any((r) => r.nom == n)),
    ];
    if (!mounted) return;
    await context.read<Api>().attribuerRoles(widget.user.id, noms);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Rôles de ${widget.user.nomComplet}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Sélectionnez au moins un rôle.', style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Flexible(
              child: AsyncView<List<Role>>(
                future: _future,
                onRetry: () => setState(() {
                  _future = context.read<Api>().roles();
                }),
                builder: (context, roles) => ListView(
                  shrinkWrap: true,
                  children: [
                    for (final r in roles)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _selection.contains(r.nom),
                        title: Text(libelleRole(r.nom)),
                        subtitle: r.description == null ? null : Text(r.description!),
                        onChanged: (v) => setState(() => v == true ? _selection.add(r.nom) : _selection.remove(r.nom)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            BusyButton(label: 'Enregistrer', icon: Icons.check, onPressed: _selection.isEmpty ? null : _enregistrer),
          ],
        ),
      ),
    );
  }
}

// --- Boutiques ----------------------------------------------------------------------

class _BoutiquesTab extends StatefulWidget {
  const _BoutiquesTab();

  @override
  State<_BoutiquesTab> createState() => _BoutiquesTabState();
}

class _BoutiquesTabState extends State<_BoutiquesTab> with AutomaticKeepAliveClientMixin {
  Future<List<Boutique>>? _future;
  final Map<int, bool> _actives = {};
  final Set<int> _enCours = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  void _charger() {
    _actives.clear();
    _future = context.read<Api>().boutiques();
  }

  Future<void> _rafraichir() async {
    setState(_charger);
    try {
      await _future;
    } catch (_) {}
  }

  Future<void> _basculer(Boutique b, bool active) async {
    if (!active) {
      final ok = await confirmer(
        context,
        'Désactiver la boutique',
        'Les produits de « ${b.nom} » ne seront plus visibles par les clients. Continuer ?',
        action: 'Désactiver',
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _enCours.add(b.id));
    try {
      await context.read<Api>().activerBoutique(b.id, active);
      if (!mounted) return;
      setState(() => _actives[b.id] = active);
      showMessage(context, active ? 'Boutique activée' : 'Boutique désactivée');
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    } finally {
      if (mounted) setState(() => _enCours.remove(b.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _rafraichir,
      child: AsyncView<List<Boutique>>(
        future: _future,
        onRetry: () => setState(_charger),
        builder: (context, boutiques) {
          if (boutiques.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 60),
                EmptyState(icon: Icons.storefront_outlined, titre: 'Aucune boutique'),
              ],
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: boutiques.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final b = boutiques[i];
              final active = _actives[b.id] ?? b.active;
              final details = [
                if (b.vendeur != null) 'Vendeur : ${b.vendeur}',
                [b.ville, b.telephone].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                '${b.nbProduits} produit${b.nbProduits > 1 ? 's' : ''}',
              ].where((s) => s.isNotEmpty);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: active ? AppColors.vertClair : Colors.grey.shade200,
                        child: Icon(Icons.storefront, color: active ? AppColors.vert : Colors.grey),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              b.nom,
                              style: TextStyle(fontWeight: FontWeight.w600, color: active ? null : Colors.grey),
                            ),
                            for (final d in details)
                              Text(d, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                            if (!active) ...[const SizedBox(height: 4), Tag('Désactivée', color: Colors.red.shade700)],
                          ],
                        ),
                      ),
                      _enCours.contains(b.id)
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              ),
                            )
                          : Switch(value: active, onChanged: (v) => _basculer(b, v)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

/// Rôles et permissions granulaires.
class AdminRolesScreen extends StatefulWidget {
  const AdminRolesScreen({super.key});

  @override
  State<AdminRolesScreen> createState() => _AdminRolesScreenState();
}

class _AdminRolesScreenState extends State<AdminRolesScreen> {
  Future<(List<Role>, List<PermissionInfo>)>? _future;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  void _charger() {
    final api = context.read<Api>();
    _future = (api.roles(), api.permissions()).wait;
  }

  Future<void> _rafraichir() async {
    setState(_charger);
    try {
      await _future;
    } catch (_) {}
  }

  Future<void> _ouvrir(Role role, List<PermissionInfo> permissions) async {
    final modifie = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _RolePermissionsScreen(role: role, permissions: permissions),
      ),
    );
    if (modifie == true && mounted) {
      showMessage(context, 'Permissions du rôle « ${libelleRole(role.nom)} » enregistrées');
      _rafraichir();
      // Le rôle modifié peut être le sien : recharger les permissions de la session.
      context.read<AuthState>().rafraichir().catchError((_) {});
    }
  }

  Future<void> _creerRole() async {
    final role = await showDialog<Role>(context: context, builder: (_) => const _NouveauRoleDialog());
    if (role == null || !mounted) return;
    showMessage(context, 'Rôle « ${role.nom} » créé. Choisissez ses permissions.');
    try {
      final permissions = await context.read<Api>().permissions();
      if (!mounted) return;
      await _ouvrir(role, permissions);
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    }
    if (mounted) _rafraichir();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rôles & permissions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creerRole,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau rôle'),
      ),
      body: RefreshIndicator(
        onRefresh: _rafraichir,
        child: AsyncView<(List<Role>, List<PermissionInfo>)>(
          future: _future,
          onRetry: () => setState(_charger),
          builder: (context, data) {
            final (roles, permissions) = data;
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: roles.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final r = roles[i];
                final admin = r.nom == 'admin';
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _ouvrir(r, permissions),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                admin ? Icons.lock_outline : Icons.badge_outlined,
                                color: admin ? AppColors.terre : AppColors.vert,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  libelleRole(r.nom),
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                ),
                              ),
                              Text(
                                '${r.permissions.length} permission${r.permissions.length > 1 ? 's' : ''}',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                              ),
                              const Icon(Icons.chevron_right, color: Colors.grey),
                            ],
                          ),
                          if (r.description != null && r.description!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(r.description!, style: TextStyle(color: Colors.grey.shade700)),
                            ),
                          const SizedBox(height: 8),
                          r.permissions.isEmpty
                              ? Text(
                                  'Aucune permission',
                                  style: TextStyle(color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                                )
                              : Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    for (final p in r.permissions)
                                      Tag(p, color: admin ? AppColors.terre : AppColors.vert),
                                  ],
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
    );
  }
}

class _NouveauRoleDialog extends StatefulWidget {
  const _NouveauRoleDialog();

  @override
  State<_NouveauRoleDialog> createState() => _NouveauRoleDialogState();
}

class _NouveauRoleDialogState extends State<_NouveauRoleDialog> {
  final _form = GlobalKey<FormState>();
  final _nom = TextEditingController();
  final _description = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _nom.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _creer() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final description = _description.text.trim();
      final role = await context.read<Api>().creerRole(_nom.text.trim(), description.isEmpty ? null : description);
      if (mounted) Navigator.pop(context, role);
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau rôle'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nom,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nom du rôle', hintText: 'ex. moderateur'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Le nom est requis' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description (facultatif)'),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: _busy ? null : _creer,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Créer'),
        ),
      ],
    );
  }
}

class _RolePermissionsScreen extends StatefulWidget {
  const _RolePermissionsScreen({required this.role, required this.permissions});
  final Role role;
  final List<PermissionInfo> permissions;

  @override
  State<_RolePermissionsScreen> createState() => _RolePermissionsScreenState();
}

class _RolePermissionsScreenState extends State<_RolePermissionsScreen> {
  late final Set<String> _selection = {...widget.role.permissions};

  bool get _lectureSeule => widget.role.nom == 'admin';

  bool get _modifie =>
      _selection.length != widget.role.permissions.length || !widget.role.permissions.every(_selection.contains);

  Future<void> _enregistrer() async {
    final permissions = widget.permissions.map((p) => p.nom).where(_selection.contains).toList();
    await context.read<Api>().permissionsRole(widget.role.id, permissions);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Rôle « ${libelleRole(widget.role.nom)} »')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_lectureSeule)
            Card(
              color: AppColors.terre.withValues(alpha: 0.08),
              child: const ListTile(
                leading: Icon(Icons.lock_outline, color: AppColors.terre),
                title: Text('Rôle protégé'),
                subtitle: Text('Les permissions du rôle administrateur ne sont pas modifiables.'),
              ),
            ),
          if (widget.role.description != null && widget.role.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
              child: Text(widget.role.description!, style: TextStyle(color: Colors.grey.shade700)),
            ),
          SectionTitle(
            'Permissions',
            trailing: _lectureSeule
                ? null
                : TextButton(
                    onPressed: () => setState(() {
                      final tout = _selection.length == widget.permissions.length;
                      _selection.clear();
                      if (!tout) _selection.addAll(widget.permissions.map((p) => p.nom));
                    }),
                    child: Text(_selection.length == widget.permissions.length ? 'Tout décocher' : 'Tout cocher'),
                  ),
          ),
          Card(
            child: Column(
              children: [
                for (final p in widget.permissions)
                  CheckboxListTile(
                    value: _selection.contains(p.nom),
                    title: Text(p.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: p.description == null ? null : Text(p.description!),
                    onChanged: _lectureSeule
                        ? null
                        : (v) => setState(() => v == true ? _selection.add(p.nom) : _selection.remove(p.nom)),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _lectureSeule
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: BusyButton(label: 'Enregistrer', icon: Icons.check, onPressed: _modifie ? _enregistrer : null),
              ),
            ),
    );
  }
}

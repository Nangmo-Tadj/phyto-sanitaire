import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

const _types = {'phytosanitaire': 'Produits phytosanitaires', 'elevage': 'Alimentation animale (élevage)'};

/// Gestion des catégories de produits.
class AdminCategoriesScreen extends StatefulWidget {
  const AdminCategoriesScreen({super.key});

  @override
  State<AdminCategoriesScreen> createState() => _AdminCategoriesScreenState();
}

class _AdminCategoriesScreenState extends State<AdminCategoriesScreen> {
  Future<List<Categorie>>? _future;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  void _charger() => _future = context.read<Api>().categories();

  Future<void> _rafraichir() async {
    setState(_charger);
    try {
      await _future;
    } catch (_) {}
  }

  Future<void> _editer([Categorie? categorie]) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _CategorieDialog(categorie: categorie),
    );
    if (ok == true && mounted) {
      showMessage(context, categorie == null ? 'Catégorie créée' : 'Catégorie modifiée');
      _rafraichir();
    }
  }

  Future<void> _supprimer(Categorie c) async {
    final ok = await confirmer(
      context,
      'Supprimer la catégorie',
      'Supprimer définitivement « ${c.nom} » ?',
      action: 'Supprimer',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await context.read<Api>().supprimerCategorie(c.id);
      if (!mounted) return;
      showMessage(context, 'Catégorie supprimée');
      _rafraichir();
    } catch (e) {
      // 409 : la catégorie contient des produits (message du serveur).
      if (mounted) showMessage(context, e, erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catégories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editer(),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      body: RefreshIndicator(
        onRefresh: _rafraichir,
        child: AsyncView<List<Categorie>>(
          future: _future,
          onRetry: () => setState(_charger),
          builder: (context, categories) {
            if (categories.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 60),
                  EmptyState(
                    icon: Icons.category_outlined,
                    titre: 'Aucune catégorie',
                    message: 'Ajoutez une première catégorie.',
                  ),
                ],
              );
            }
            final types = {..._types.keys, ...categories.map((c) => c.type)};
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              children: [
                for (final type in types) ...[
                  SectionTitle(_types[type] ?? type),
                  _groupe(type, categories.where((c) => c.type == type).toList()),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _groupe(String type, List<Categorie> categories) {
    final elevage = type == 'elevage';
    final couleur = elevage ? AppColors.elevage : AppColors.vert;
    if (categories.isEmpty) {
      return Card(
        child: ListTile(
          title: Text('Aucune catégorie', style: TextStyle(color: Colors.grey.shade600)),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (final (i, c) in categories.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: couleur.withValues(alpha: 0.12),
                child: Icon(elevage ? Icons.pets : Icons.eco, color: couleur),
              ),
              title: Text(c.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                [
                  if (c.description != null && c.description!.isNotEmpty) c.description!,
                  '${c.nbProduits} produit${c.nbProduits > 1 ? 's' : ''}',
                ].join('\n'),
              ),
              isThreeLine: c.description != null && c.description!.isNotEmpty,
              onTap: () => _editer(c),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => v == 'modifier' ? _editer(c) : _supprimer(c),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'modifier',
                    child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Modifier')),
                  ),
                  PopupMenuItem(
                    value: 'supprimer',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: Colors.red.shade700),
                      title: Text('Supprimer', style: TextStyle(color: Colors.red.shade700)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategorieDialog extends StatefulWidget {
  const _CategorieDialog({this.categorie});
  final Categorie? categorie;

  @override
  State<_CategorieDialog> createState() => _CategorieDialogState();
}

class _CategorieDialogState extends State<_CategorieDialog> {
  final _form = GlobalKey<FormState>();
  late final _nom = TextEditingController(text: widget.categorie?.nom);
  late final _description = TextEditingController(text: widget.categorie?.description);
  late String _type = widget.categorie?.type ?? 'phytosanitaire';
  bool _busy = false;

  @override
  void dispose() {
    _nom.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final data = {
      'nom': _nom.text.trim(),
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'type': _type,
    };
    try {
      final api = context.read<Api>();
      if (widget.categorie == null) {
        await api.creerCategorie(data);
      } else {
        await api.modifierCategorie(widget.categorie!.id, data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.categorie == null ? 'Nouvelle catégorie' : 'Modifier la catégorie'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nom,
                autofocus: widget.categorie == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Le nom est requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Description (facultatif)'),
                maxLines: 3,
                minLines: 1,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final e in _types.entries)
                    DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: _busy ? null : _enregistrer,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}

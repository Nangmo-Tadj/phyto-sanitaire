import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Création / modification d'un produit (vendeur ou administrateur).
/// Renvoie `true` via [Navigator.pop] quand le produit est enregistré.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.produit});

  final Produit? produit;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nom;
  late final TextEditingController _description;
  late final TextEditingController _prix;
  late final TextEditingController _stock;
  late final TextEditingController _unite;

  late Future<List<Categorie>> _categories;
  int? _idCategorie;
  late String _statut;
  String? _image;
  bool _upload = false;

  bool get _edition => widget.produit != null;

  @override
  void initState() {
    super.initState();
    final p = widget.produit;
    _nom = TextEditingController(text: p?.nom);
    _description = TextEditingController(text: p?.description);
    _prix = TextEditingController(text: p == null ? '' : '${p.prix}');
    _stock = TextEditingController(text: p == null ? '' : '${p.stock}');
    _unite = TextEditingController(text: p?.unite);
    _idCategorie = p?.idCategorie;
    _statut = p?.statut ?? 'publie';
    _image = p?.image;
    _categories = context.read<Api>().categories();
  }

  @override
  void dispose() {
    for (final c in [_nom, _description, _prix, _stock, _unite]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _choisirImage() async {
    final fichier = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
    if (fichier == null || !mounted) return;
    setState(() => _upload = true);
    try {
      final url = await context.read<Api>().uploadImage(File(fichier.path));
      if (mounted) setState(() => _image = url);
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    } finally {
      if (mounted) setState(() => _upload = false);
    }
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;
    final api = context.read<Api>();
    final data = {
      'nom': _nom.text.trim(),
      'id_categorie': _idCategorie,
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'prix_produit': int.parse(_prix.text.trim()),
      'quantite_stock': int.parse(_stock.text.trim()),
      'unite': _unite.text.trim().isEmpty ? null : _unite.text.trim(),
      'image_produit': _image,
      'statut': _statut,
    };
    try {
      final produit = _edition ? await api.modifierProduit(widget.produit!.id, data) : await api.creerProduit(data);
      if (!mounted) return;
      showMessage(context, _edition ? 'Produit « ${produit.nom} » mis à jour' : 'Produit « ${produit.nom} » ajouté');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      // 409 « Produit existant » : un produit du même nom existe déjà dans la boutique.
      if (mounted) showMessage(context, e, erreur: true);
    }
  }

  String? _entier(String? v, String champ) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null) return '$champ obligatoire';
    if (n < 0) return '$champ invalide';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_edition ? 'Modifier le produit' : 'Nouveau produit')),
      body: AsyncView<List<Categorie>>(
        future: _categories,
        onRetry: () => setState(() {
          _categories = context.read<Api>().categories();
        }),
        builder: (context, categories) => Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _imagePicker(),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nom,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nom du produit *'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Nom obligatoire' : null,
              ),
              const SizedBox(height: 12),
              _categorieField(categories),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _prix,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Prix *', suffixText: 'FCFA'),
                      validator: (v) => _entier(v, 'Prix'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _stock,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Quantité en stock *'),
                      validator: (v) => _entier(v, 'Quantité'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _unite,
                decoration: const InputDecoration(labelText: 'Unité', hintText: 'ex. sac 50 kg, bidon 1 L'),
              ),
              const SizedBox(height: 16),
              Text('Statut', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: [
                  const ButtonSegment(value: 'publie', label: Text('Publié'), icon: Icon(Icons.public)),
                  const ButtonSegment(value: 'brouillon', label: Text('Brouillon'), icon: Icon(Icons.edit_note)),
                  if (widget.produit?.statut == 'retire')
                    const ButtonSegment(value: 'retire', label: Text('Retiré'), icon: Icon(Icons.block)),
                ],
                selected: {_statut},
                onSelectionChanged: (s) => setState(() => _statut = s.first),
              ),
              const SizedBox(height: 6),
              Text(
                _statut == 'publie'
                    ? 'Visible dans le catalogue par les clients.'
                    : _statut == 'brouillon'
                    ? 'Enregistré mais non visible par les clients.'
                    : 'Retiré du catalogue.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 24),
              BusyButton(
                label: _edition ? 'Enregistrer les modifications' : 'Ajouter le produit',
                icon: Icons.check,
                onPressed: _upload ? null : _enregistrer,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imagePicker() {
    final type = widget.produit?.typeCategorie ?? 'phytosanitaire';
    return Center(
      child: Stack(
        children: [
          ProductImage(path: _image, type: type, size: 140, radius: 16),
          if (_upload)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          Positioned(
            right: 6,
            bottom: 6,
            child: Row(
              children: [
                if (_image != null && !_upload)
                  IconButton.filledTonal(
                    tooltip: 'Retirer l’image',
                    onPressed: () => setState(() => _image = null),
                    icon: const Icon(Icons.delete_outline),
                  ),
                IconButton.filled(
                  tooltip: 'Choisir une image',
                  onPressed: _upload ? null : _choisirImage,
                  icon: const Icon(Icons.photo_camera),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _categorieField(List<Categorie> categories) {
    const types = {'phytosanitaire': 'Produits phytosanitaires', 'elevage': 'Aliments pour élevage'};
    final items = <DropdownMenuItem<int>>[];
    for (final type in types.keys) {
      final liste = categories.where((c) => c.type == type).toList();
      if (liste.isEmpty) continue;
      items.add(
        DropdownMenuItem(
          value: -items.length - 1, // en-tête de groupe, non sélectionnable
          enabled: false,
          child: Text(
            types[type]!.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: type == 'elevage' ? AppColors.elevage : AppColors.vert,
            ),
          ),
        ),
      );
      for (final c in liste) {
        items.add(
          DropdownMenuItem(
            value: c.id,
            child: Padding(padding: const EdgeInsets.only(left: 12), child: Text(c.nom)),
          ),
        );
      }
    }
    final connue = categories.any((c) => c.id == _idCategorie);
    return DropdownButtonFormField<int>(
      initialValue: connue ? _idCategorie : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Catégorie *'),
      items: items,
      selectedItemBuilder: (context) => [
        for (final item in items)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              categories
                      .where((c) => c.id == item.value)
                      .map((c) => '${c.nom} · ${_libelleType(c.type)}')
                      .firstOrNull ??
                  '',
            ),
          ),
      ],
      onChanged: (v) => setState(() => _idCategorie = v),
      validator: (v) => v == null || v < 0 ? 'Catégorie obligatoire' : null,
    );
  }
}

String _libelleType(String type) => type == 'elevage' ? 'Élevage' : 'Phytosanitaire';

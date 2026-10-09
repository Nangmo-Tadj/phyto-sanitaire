import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/api.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

const _villeDefaut = '*';

String _libelleVille(String ville) => ville == _villeDefaut ? 'Par défaut (toutes villes)' : ville;

/// Configuration des frais de livraison par ville.
class AdminDeliveryRulesScreen extends StatefulWidget {
  const AdminDeliveryRulesScreen({super.key});

  @override
  State<AdminDeliveryRulesScreen> createState() => _AdminDeliveryRulesScreenState();
}

class _AdminDeliveryRulesScreenState extends State<AdminDeliveryRulesScreen> {
  Future<List<RegleLivraison>>? _future;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  void _charger() => _future = context.read<Api>().reglesLivraison();

  Future<void> _rafraichir() async {
    setState(_charger);
    try {
      await _future;
    } catch (_) {}
  }

  Future<void> _editer([RegleLivraison? regle]) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _RegleDialog(regle: regle),
    );
    if (ok == true && mounted) {
      showMessage(context, 'Règle de livraison enregistrée');
      _rafraichir();
    }
  }

  Future<void> _supprimer(RegleLivraison r) async {
    final ok = await confirmer(
      context,
      'Supprimer la règle',
      'Supprimer la règle pour ${r.ville} ? La règle par défaut s\'appliquera à cette ville.',
      action: 'Supprimer',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await context.read<Api>().supprimerRegle(r.id);
      if (!mounted) return;
      showMessage(context, 'Règle supprimée');
      _rafraichir();
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Règles de livraison')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editer(),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter une ville'),
      ),
      body: RefreshIndicator(
        onRefresh: _rafraichir,
        child: AsyncView<List<RegleLivraison>>(
          future: _future,
          onRetry: () => setState(_charger),
          builder: (context, regles) {
            final triees = [...regles]
              ..sort((a, b) {
                if (a.ville == _villeDefaut) return -1;
                if (b.ville == _villeDefaut) return 1;
                return a.ville.toLowerCase().compareTo(b.ville.toLowerCase());
              });
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Text(
                  'Les frais sont appliqués selon la ville de livraison. La livraison est gratuite lorsque le sous-total '
                  'atteint le seuil de gratuité.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                if (triees.isEmpty)
                  const EmptyState(icon: Icons.local_shipping_outlined, titre: 'Aucune règle de livraison'),
                for (final r in triees) Padding(padding: const EdgeInsets.only(bottom: 8), child: _regleCard(r)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _regleCard(RegleLivraison r) {
    final defaut = r.ville == _villeDefaut;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => _editer(r),
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        leading: CircleAvatar(
          backgroundColor: (defaut ? AppColors.terre : AppColors.vert).withValues(alpha: 0.12),
          child: Icon(defaut ? Icons.public : Icons.location_city, color: defaut ? AppColors.terre : AppColors.vert),
        ),
        title: Text(_libelleVille(r.ville), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          'Frais : ${r.frais == 0 ? 'gratuit' : fcfa(r.frais)}\n'
          '${r.seuilGratuite == null ? 'Pas de seuil de gratuité' : 'Gratuit dès ${fcfa(r.seuilGratuite!)}'}',
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(tooltip: 'Modifier', icon: const Icon(Icons.edit_outlined), onPressed: () => _editer(r)),
            if (!defaut)
              IconButton(
                tooltip: 'Supprimer',
                icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
                onPressed: () => _supprimer(r),
              ),
          ],
        ),
      ),
    );
  }
}

class _RegleDialog extends StatefulWidget {
  const _RegleDialog({this.regle});
  final RegleLivraison? regle;

  @override
  State<_RegleDialog> createState() => _RegleDialogState();
}

class _RegleDialogState extends State<_RegleDialog> {
  final _form = GlobalKey<FormState>();
  late final _ville = TextEditingController(text: widget.regle == null ? '' : _libelleVille(widget.regle!.ville));
  late final _frais = TextEditingController(text: widget.regle == null ? '' : '${widget.regle!.frais}');
  late final _seuil = TextEditingController(text: widget.regle?.seuilGratuite?.toString() ?? '');
  bool _busy = false;

  bool get _edition => widget.regle != null;

  @override
  void dispose() {
    _ville.dispose();
    _frais.dispose();
    _seuil.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      // La ville n'est pas modifiable en édition : l'enregistrement se fait par ville (upsert).
      final ville = _edition ? widget.regle!.ville : _ville.text.trim();
      final seuil = _seuil.text.trim();
      await context.read<Api>().enregistrerRegle(
        ville,
        int.parse(_frais.text.trim()),
        seuil.isEmpty ? null : int.parse(seuil),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, e, erreur: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _montant(String? v, {bool requis = false}) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return requis ? 'Montant requis' : null;
    return int.tryParse(t) == null ? 'Montant invalide' : null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_edition ? 'Modifier la règle' : 'Nouvelle règle'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _ville,
                enabled: !_edition,
                autofocus: !_edition,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Ville', prefixIcon: Icon(Icons.location_city)),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'La ville est requise';
                  if (t == _villeDefaut) return 'Modifiez la règle par défaut existante';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _frais,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Frais de livraison', suffixText: 'FCFA'),
                validator: (v) => _montant(v, requis: true),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _seuil,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Seuil de gratuité (facultatif)',
                  helperText: 'Livraison gratuite à partir de ce sous-total',
                  suffixText: 'FCFA',
                ),
                validator: _montant,
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

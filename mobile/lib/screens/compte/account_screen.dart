import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../admin/admin_home_screen.dart';
import '../livreur/deliveries_screen.dart';
import '../notifications/notifications_screen.dart';
import '../vendeur/shop_screen.dart';
import 'change_password_screen.dart';
import 'edit_profile_screen.dart';

/// Gérer son compte, et accès aux espaces selon les rôles (vendeur, livreur, administrateur).
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  void _ouvrir(BuildContext context, Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  Future<void> _newsletter(BuildContext context, bool abonne) async {
    final auth = context.read<AuthState>();
    if (abonne && (auth.user!.email == null || auth.user!.email!.isEmpty)) {
      showMessage(context, 'Ajoutez une adresse email à votre profil pour recevoir la newsletter', erreur: true);
      return;
    }
    try {
      await auth.api.newsletterCompte(abonne);
      await auth.rafraichir();
      if (context.mounted) {
        showMessage(context, abonne ? 'Inscription à la newsletter confirmée' : 'Désinscription effectuée');
      }
    } catch (e) {
      if (context.mounted) showMessage(context, e, erreur: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final user = auth.user!;
    final estAdmin = [
      Perm.statistiquesVoir,
      Perm.utilisateursGerer,
      Perm.commandesGerer,
      Perm.categoriesGerer,
    ].any(user.can);

    return Scaffold(
      appBar: AppBar(title: const Text('Mon compte')),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([
          auth.rafraichir().catchError((_) {}),
          context.read<ParametresState>().charger().catchError((_) {}),
        ]),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: AppColors.vert,
                      child: Text(
                        '${user.prenom.isEmpty ? '' : user.prenom[0]}${user.nom.isEmpty ? '' : user.nom[0]}'
                            .toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.nomComplet,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(user.telephone),
                          if (user.email != null) Text(user.email!, style: TextStyle(color: Colors.grey.shade700)),
                          const SizedBox(height: 6),
                          Wrap(spacing: 6, runSpacing: 4, children: [for (final r in user.roles) Tag(libelleRole(r))]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (user.can(Perm.boutiqueGerer) || user.can(Perm.livraisonsEffectuer) || estAdmin) ...[
              const SectionTitle('Mes espaces'),
              Card(
                child: Column(
                  children: [
                    if (user.can(Perm.boutiqueGerer))
                      ListTile(
                        leading: const Icon(Icons.storefront, color: AppColors.vert),
                        title: Text(
                          user.boutique == null ? 'Créer ma boutique' : 'Ma boutique · ${user.boutique!.nom}',
                        ),
                        subtitle: const Text('Produits, stocks, publication, ventes'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _ouvrir(context, const ShopScreen()),
                      ),
                    if (user.can(Perm.livraisonsEffectuer))
                      ListTile(
                        leading: const Icon(Icons.delivery_dining, color: AppColors.terre),
                        title: const Text('Mes livraisons'),
                        subtitle: const Text('Commandes à livrer et confirmations'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _ouvrir(context, const DeliveriesScreen()),
                      ),
                    if (estAdmin)
                      ListTile(
                        leading: const Icon(Icons.admin_panel_settings, color: Colors.indigo),
                        title: const Text('Administration'),
                        subtitle: const Text('Statistiques, utilisateurs, commandes, paiements'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _ouvrir(context, const AdminHomeScreen()),
                      ),
                  ],
                ),
              ),
            ] else if (context.watch<ParametresState>().creationBoutique) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.storefront_outlined, color: AppColors.vert),
                  title: const Text('Vous vendez des produits ?'),
                  subtitle: const Text('Créez votre boutique en ligne gratuitement'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _ouvrir(context, const ShopScreen()),
                ),
              ),
            ],
            const SectionTitle('Paramètres'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('Modifier mon profil'),
                    subtitle: user.adresse == null ? null : Text(user.adresse!),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _ouvrir(context, const EditProfileScreen()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Changer le mot de passe'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _ouvrir(context, const ChangePasswordScreen()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: const Text('Notifications'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _ouvrir(context, const NotificationsScreen()),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.mark_email_unread_outlined),
                    title: const Text('Newsletter'),
                    subtitle: const Text('Promotions et conseils agricoles'),
                    value: user.newsletter,
                    onChanged: (v) => _newsletter(context, v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async {
                if (await confirmer(
                  context,
                  'Déconnexion',
                  'Voulez-vous vous déconnecter ?',
                  action: 'Se déconnecter',
                )) {
                  if (!context.mounted) return;
                  context.read<CartState>().reinitialiser();
                  await auth.deconnexion();
                }
              },
              icon: const Icon(Icons.logout),
              label: const Text('Se déconnecter'),
            ),
            const SizedBox(height: 8),
            if (user.derniereConnexion != null)
              Center(
                child: Text(
                  'Dernière connexion : ${dateHeure(user.derniereConnexion)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

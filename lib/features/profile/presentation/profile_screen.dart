import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/text_prompt.dart';
import '../../authentication/state/session.dart';
import '../../notifications/repositories/push_service.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Your ChitChat')),
    body: ref
        .watch(profileProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => StatusView(
            'Could not load settings',
            retry: () => ref.invalidate(profileProvider),
          ),
          data: (p) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              InitialAvatar(p?['name'] ?? 'Guest'),
              const SizedBox(height: 12),
              Text(
                p?['name'] ?? 'Guest',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('Blocked users'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/blocked'),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Change display name'),
                  subtitle: const Text('You can stay anonymous.'),
                  onTap: () async {
                    final name = await textPrompt(
                      context,
                      'What should we call you?',
                      initial: p?['name'] ?? '',
                      maxLength: 60,
                    );
                    if (name == null || name.isEmpty) {
                      return;
                    }
                    try {
                      final c = ref.read(clientProvider);
                      await c
                          .from('profiles')
                          .update({'name': name})
                          .eq('id', c.auth.currentUser!.id)
                          .select()
                          .single();
                      ref.invalidate(profileProvider);
                    } catch (e) {
                      if (context.mounted) {
                        showError(context, e);
                      }
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<ThemeMode>(
                initialValue: ref.watch(themeModeProvider),
                decoration: const InputDecoration(labelText: 'Appearance'),
                items: const [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text('System'),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text('Light'),
                  ),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                ],
                onChanged: (v) => ref.read(themeModeProvider.notifier).set(v!),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  try {
                    final c = ref.read(clientProvider);
                    await c
                        .from('profiles')
                        .update({'push_enabled': true})
                        .eq('id', c.auth.currentUser!.id);
                    await ref.read(pushServiceProvider).enable();
                    ref.invalidate(profileProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Notifications enabled')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      showError(context, e);
                    }
                  }
                },
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Enable notifications'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await ref.read(pushServiceProvider).disable();
                    final c = ref.read(clientProvider);
                    await c
                        .from('profiles')
                        .update({'push_enabled': false})
                        .eq('id', c.auth.currentUser!.id);
                    ref.invalidate(profileProvider);
                  } catch (e) {
                    if (context.mounted) {
                      showError(context, e);
                    }
                  }
                },
                child: const Text('Turn off all notifications'),
              ),
              if (!FirebaseConfiguration.enabled)
                const Text(
                  'Push notifications need Firebase configuration for this build.',
                  style: TextStyle(fontSize: 12),
                ),
              if (FirebaseConfiguration.failure != null)
                Text(FirebaseConfiguration.failure!),
              const SizedBox(height: 24),
              const Text(
                'Groups created with Spill the Chaya expire after one hour. Community chat remains open. Android protects screenshots and screen recordings; another camera can still photograph a screen.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () async {
                  final guest =
                      ref.read(clientProvider).auth.currentUser?.isAnonymous ??
                      false;
                  if (guest) {
                    final leave = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Leave this guest account?'),
                        content: const Text(
                          'You won’t be able to recover this anonymous identity after signing out.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Stay'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Sign out'),
                          ),
                        ],
                      ),
                    );
                    if (leave != true) {
                      return;
                    }
                  }
                  try {
                    await ref.read(pushServiceProvider).signOut();
                  } catch (e) {
                    if (context.mounted) {
                      showError(context, e);
                    }
                  }
                },
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
              TextButton(
                onPressed: () async {
                  final confirm = await textPrompt(
                    context,
                    'Type DELETE to delete your account and messages',
                    maxLength: 6,
                  );
                  if (confirm != 'DELETE') {
                    return;
                  }
                  try {
                    await ref.read(pushServiceProvider).disable();
                    await ref
                        .read(clientProvider)
                        .functions
                        .invoke('delete-account');
                    await ref.read(clientProvider).auth.signOut();
                  } catch (e) {
                    if (context.mounted) {
                      showError(context, e);
                    }
                  }
                },
                child: const Text('Delete account'),
              ),
            ],
          ),
        ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common.dart';
import '../../authentication/state/session.dart';
import '../repositories/moderation_repository.dart';

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Blocked users')),
    body: ref
        .watch(blockedUsersProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => StatusView(
            'Could not load blocked users',
            retry: () => ref.invalidate(blockedUsersProvider),
          ),
          data: (users) => users.isEmpty
              ? const StatusView('No blocked users')
              : ListView(
                  children: users
                      .map(
                        (user) => ListTile(
                          leading: InitialAvatar(
                            user['profiles']?['name'] ?? 'Guest',
                          ),
                          title: Text(user['profiles']?['name'] ?? 'Guest'),
                          trailing: TextButton(
                            onPressed: () async {
                              try {
                                final c = ref.read(clientProvider);
                                await c
                                    .from('user_blocks')
                                    .delete()
                                    .eq('blocker_id', c.auth.currentUser!.id)
                                    .eq('blocked_id', user['blocked_id']);
                                ref.invalidate(blockedUsersProvider);
                                ref
                                    .read(blockRevisionProvider.notifier)
                                    .changed();
                              } catch (e) {
                                if (context.mounted) {
                                  showError(context, e);
                                }
                              }
                            },
                            child: const Text('Unblock'),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
  );
}

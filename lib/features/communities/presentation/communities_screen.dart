import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/common.dart';
import '../repositories/community_repository.dart';

class CommunitiesScreen extends ConsumerWidget {
  const CommunitiesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Row(
        children: [
          Icon(Icons.bubble_chart_rounded),
          SizedBox(width: 8),
          Text('ChitChat', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Your name and notifications',
          onPressed: () => context.push('/settings'),
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => context.push('/spill'),
      icon: const Icon(Icons.local_cafe_outlined),
      label: const Text('Spill the Chaya'),
    ),
    body: RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(roomsProvider);
        await ref.read(roomsProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
        children: [
          Text(
            'A little chat.\nA lot of connection.',
            style: Theme.of(context).textTheme.headlineLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          const Text(
            'Say hello to everyone, or spill the chaya in a group that disappears after one hour.',
          ),
          const SizedBox(height: 24),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: ListTile(
              contentPadding: const EdgeInsets.all(20),
              leading: const Icon(Icons.forum_rounded, size: 36),
              title: const Text(
                'Community chat',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
              subtitle: const Text(
                'Everyone’s welcome. Join the conversation.',
              ),
              trailing: const Icon(Icons.arrow_forward_rounded),
              onTap: () => context.push('/chat/$loungeId'),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Fresh chaya',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text('Open groups · one hour only'),
          const SizedBox(height: 12),
          ref
              .watch(roomsProvider)
              .when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => StatusView(
                  'Could not load groups',
                  detail: friendlyError(e),
                  retry: () => ref.invalidate(roomsProvider),
                ),
                data: (rooms) {
                  final groups = rooms.where((r) => !r.isLounge).toList();
                  return groups.isEmpty
                      ? const Card(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No groups brewing yet. Tap Spill the Chaya to start one.',
                            ),
                          ),
                        )
                      : Column(
                          children: groups
                              .map(
                                (r) => Card(
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    leading: InitialAvatar(r.name),
                                    title: Text(
                                      r.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Expires ${TimeOfDay.fromDateTime(r.expiresAt!.toLocal()).format(context)}',
                                    ),
                                    trailing: const Icon(Icons.arrow_forward),
                                    onTap: () => context.push('/chat/${r.id}'),
                                  ),
                                ),
                              )
                              .toList(),
                        );
                },
              ),
          const SizedBox(height: 24),
          const Row(
            children: [
              Icon(Icons.screenshot_monitor_outlined, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Screenshots and screen recordings are protected on Android.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

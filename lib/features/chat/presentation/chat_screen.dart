import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/widgets/common.dart';
import '../../authentication/state/session.dart';
import '../../communities/repositories/community_repository.dart';
import '../models/chat_message.dart';
import '../models/message_merge.dart';
import '../repositories/chat_repository.dart';
import '../../moderation/repositories/moderation_repository.dart';

class PendingMessage {
  PendingMessage(this.message);
  final ChatMessage message;
  bool failed = false;
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen(this.room, {super.key});
  final String room;
  @override
  ConsumerState<ChatScreen> createState() => _ChatState();
}

class _ChatState extends ConsumerState<ChatScreen> {
  final input = TextEditingController();
  final pending = <String, PendingMessage>{}, history = <String, ChatMessage>{};
  late Future<void> access;
  late Timer clock;
  late final repository = ref.read(chatRepositoryProvider);
  bool olderLoading = false, hasOlder = true, muted = false;
  @override
  void initState() {
    super.initState();
    access = enter();
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> enter() async {
    final c = ref.read(clientProvider);
    await c.rpc('enter_room', params: {'rid': widget.room});
    final member = await c
        .from('room_members')
        .select('muted')
        .eq('room_id', widget.room)
        .eq('user_id', c.auth.currentUser!.id)
        .single();
    muted = member['muted'];
    ref.invalidate(messagesProvider(widget.room));
  }

  @override
  void dispose() {
    clock.cancel();
    input.dispose();
    super.dispose();
  }

  Future<void> send([PendingMessage? retry]) async {
    final body = input.text.trim();
    if (retry == null && (body.isEmpty || body.length > 2000)) {
      return;
    }
    final p =
        retry ??
        PendingMessage(
          ChatMessage(
            id: const Uuid().v4(),
            senderId: ref.read(clientProvider).auth.currentUser!.id,
            body: body,
            createdAt: DateTime.now().toUtc(),
          ),
        );
    setState(() {
      pending[p.message.id] = p;
      p.failed = false;
      if (retry == null) {
        input.clear();
      }
    });
    try {
      await repository.send(widget.room, p.message);
    } catch (e) {
      if (mounted) {
        setState(() => p.failed = true);
        showError(context, e);
      }
    }
  }

  Future<void> loadOlder(List<ChatMessage> messages) async {
    if (messages.isEmpty || olderLoading) {
      return;
    }
    setState(() => olderLoading = true);
    try {
      final rows = await repository.older(widget.room, messages.last);
      if (mounted) {
        setState(() {
          for (final m in rows) {
            history[m.id] = m;
          }
          hasOlder = rows.length == 50;
        });
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => olderLoading = false);
      }
    }
  }

  Future<void> messageOptions(ChatMessage message) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Report message'),
              onTap: () => Navigator.pop(context, 'report'),
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Block user'),
              subtitle: const Text(
                'Hide messages and stop notifications between you.',
              ),
              onTap: () => Navigator.pop(context, 'block'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    try {
      final c = ref.read(clientProvider);
      if (action == 'block') {
        await c.from('user_blocks').insert({'blocked_id': message.senderId});
        ref.read(blockRevisionProvider.notifier).changed();
        ref.invalidate(blockedUsersProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User blocked. Manage blocked users in Settings.'),
            ),
          );
        }
      } else {
        final reason = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text('Why are you reporting this message?'),
                ),
                for (final reason in ['spam', 'harassment', 'unsafe', 'other'])
                  ListTile(
                    title: Text(reason[0].toUpperCase() + reason.substring(1)),
                    onTap: () => Navigator.pop(context, reason),
                  ),
              ],
            ),
          ),
        );
        if (reason == null) {
          return;
        }
        await c.rpc(
          'report_message',
          params: {'mid': message.id, 'reason': reason},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Report submitted. Thank you.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(blockRevisionProvider, (_, next) {
      history.clear();
      ref.invalidate(messagesProvider(widget.room));
    });
    ref.listen(messagesProvider(widget.room), (_, next) {
      final live = next.asData?.value;
      if (live != null) {
        for (final m in live) {
          pending.remove(m.id);
        }
      }
    });
    final room = ref.watch(roomProvider(widget.room));
    final offset =
        ref.watch(clockOffsetProvider).asData?.value ?? Duration.zero;
    final detail = room.asData?.value;
    final remaining = detail?.expiresAt?.difference(
      DateTime.now().toUtc().add(offset),
    );
    final expired =
        (remaining != null && remaining <= Duration.zero) ||
        (room.hasValue && detail == null);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to chats',
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              detail?.name ?? 'ChitChat',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              expired
                  ? 'This chaya has ended'
                  : remaining == null
                  ? 'Everyone’s welcome'
                  : 'Disappears in ${remaining.inMinutes.toString().padLeft(2, '0')}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
        actions: [
          if (!expired)
            IconButton(
              tooltip: muted ? 'Unmute notifications' : 'Mute notifications',
              icon: Icon(
                muted
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_outlined,
              ),
              onPressed: () async {
                try {
                  final c = ref.read(clientProvider);
                  await c
                      .from('room_members')
                      .update({'muted': !muted})
                      .eq('room_id', widget.room)
                      .eq('user_id', c.auth.currentUser!.id)
                      .select()
                      .single();
                  if (mounted) {
                    setState(() => muted = !muted);
                  }
                } catch (e) {
                  if (context.mounted) {
                    showError(context, e);
                  }
                }
              },
            ),
        ],
      ),
      body: expired
          ? StatusView(
              'This chaya has ended',
              detail: 'The group and its conversation are no longer available.',
              retry: () => context.go('/'),
            )
          : FutureBuilder<void>(
              future: access,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return StatusView(
                    'Could not enter this chat',
                    detail: friendlyError(snapshot.error!),
                    retry: () => setState(() => access = enter()),
                  );
                }
                return Column(
                  children: [
                    Expanded(
                      child: ref
                          .watch(messagesProvider(widget.room))
                          .when(
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (e, _) => StatusView(
                              'Chat is offline or unavailable',
                              detail: friendlyError(e),
                              retry: () =>
                                  ref.invalidate(messagesProvider(widget.room)),
                            ),
                            data: (live) {
                              final items = mergeMessages(
                                history.values,
                                pending.values.map((p) => p.message),
                                live,
                              );
                              final confirmed = live.map((m) => m.id).toSet();
                              if (items.isEmpty) {
                                return const StatusView(
                                  'Start the conversation',
                                  detail: 'Say hello. Keep it kind.',
                                );
                              }
                              return ListView.builder(
                                reverse: true,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                itemCount: items.length + 1,
                                itemBuilder: (context, i) {
                                  if (i == items.length) {
                                    return hasOlder
                                        ? TextButton(
                                            onPressed: olderLoading
                                                ? null
                                                : () => loadOlder(items),
                                            child: Text(
                                              olderLoading
                                                  ? 'Loading…'
                                                  : 'Earlier messages',
                                            ),
                                          )
                                        : const SizedBox.shrink();
                                  }
                                  final m = items[i],
                                      own =
                                          m.senderId ==
                                          ref
                                              .read(clientProvider)
                                              .auth
                                              .currentUser!
                                              .id;
                                  final p = confirmed.contains(m.id)
                                      ? null
                                      : pending[m.id];
                                  final name =
                                      ref
                                          .watch(senderProvider(m.senderId))
                                          .asData
                                          ?.value ??
                                      'Guest';
                                  return Align(
                                    alignment: own
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth:
                                            MediaQuery.sizeOf(context).width *
                                            .82,
                                      ),
                                      child: Card(
                                        color: own
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primaryContainer
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (!own)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 4,
                                                      ),
                                                  child: Text(
                                                    name,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary,
                                                    ),
                                                  ),
                                                ),
                                              Semantics(
                                                button: !own,
                                                label: own
                                                    ? null
                                                    : 'Message from $name. Long press to block or report.',
                                                child: GestureDetector(
                                                  onLongPress: own
                                                      ? null
                                                      : () => messageOptions(m),
                                                  child: Text(m.body),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                '${DateFormat.Hm().format(m.createdAt.toLocal())}${p == null
                                                    ? ' · sent'
                                                    : p.failed
                                                    ? ' · failed'
                                                    : ' · sending…'}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall,
                                              ),
                                              if (p?.failed == true)
                                                TextButton.icon(
                                                  onPressed: () => send(p),
                                                  icon: const Icon(
                                                    Icons.refresh,
                                                  ),
                                                  label: const Text('Retry'),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: input,
                                minLines: 1,
                                maxLines: 4,
                                maxLength: 2000,
                                decoration: const InputDecoration(
                                  hintText: 'Spill the chaya…',
                                  counterText: '',
                                ),
                                textCapitalization:
                                    TextCapitalization.sentences,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              tooltip: 'Send message',
                              onPressed: () => send(),
                              icon: const Icon(Icons.send_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/common.dart';
import '../../authentication/state/session.dart';
import '../repositories/community_repository.dart';

class CreateCommunityScreen extends ConsumerStatefulWidget {
  const CreateCommunityScreen({super.key});
  @override
  ConsumerState<CreateCommunityScreen> createState() => _CreateState();
}

class _CreateState extends ConsumerState<CreateCommunityScreen> {
  final name = TextEditingController(), form = GlobalKey<FormState>();
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> create() async {
    if (!form.currentState!.validate()) {
      return;
    }
    setState(() => busy = true);
    try {
      final id =
          await ref
                  .read(clientProvider)
                  .rpc('create_room', params: {'p_name': name.text.trim()})
              as String;
      ref.invalidate(roomsProvider);
      if (mounted) {
        context.go('/chat/$id');
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Spill the Chaya')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Form(
          key: form,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Icon(
                Icons.local_cafe_rounded,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Fresh gossip.\nGone in an hour.',
                style: Theme.of(context).textTheme.headlineLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Pick a name and jump in. Everyone can join. Your group and its messages disappear automatically after one hour.',
              ),
              const SizedBox(height: 28),
              TextFormField(
                controller: name,
                maxLength: 60,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Group name',
                  hintText: 'What’s brewing?',
                ),
                validator: (v) => (v?.trim().length ?? 0) >= 3
                    ? null
                    : 'Use at least 3 characters',
                onFieldSubmitted: busy ? null : (_) => create(),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: busy ? null : create,
                icon: const Icon(Icons.local_cafe_outlined),
                label: Text(busy ? 'Brewing…' : 'Create & start chatting'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/common.dart';
import 'environment.dart';

final configurationRevisionProvider =
    NotifierProvider<ConfigurationRevision, int>(ConfigurationRevision.new);

class ConfigurationRevision extends Notifier<int> {
  @override
  int build() => 0;
  void reload() => state++;
}

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});
  @override
  ConsumerState<SetupScreen> createState() => _SetupState();
}

class _SetupState extends ConsumerState<SetupScreen> {
  final url = TextEditingController(), key = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false;
  @override
  void dispose() {
    url.dispose();
    key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.bubble_chart_rounded,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Welcome to ChitChat',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'One-time setup: connect the Supabase project prepared using README.md. Only public app configuration belongs here.',
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Supabase project URL',
                    hintText: 'https://your-project.supabase.co',
                  ),
                  validator: (v) {
                    final u = Uri.tryParse(v?.trim() ?? '');
                    return u != null && u.scheme == 'https' && u.host.isNotEmpty
                        ? null
                        : 'Enter your HTTPS Supabase URL';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: key,
                  decoration: const InputDecoration(
                    labelText: 'Public publishable key',
                  ),
                  validator: (v) =>
                      Environment.isPublicKey(v?.trim() ?? '') ? null : 'Use a publishable or legacy anon key. Never a secret key.',
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (!form.currentState!.validate()) {
                            return;
                          }
                          setState(() => busy = true);
                          try {
                            await Supabase.initialize(
                              url: url.text.trim(),
                              publishableKey: key.text.trim(),
                            );
                            await Environment.save(
                              url.text.trim(),
                              key.text.trim(),
                            );
                            ref
                                .read(configurationRevisionProvider.notifier)
                                .reload();
                          } catch (e) {
                            if (context.mounted) {
                              showError(context, e);
                            }
                          } finally {
                            if (mounted) {
                              setState(() => busy = false);
                            }
                          }
                        },
                  child: Text(busy ? 'Connecting…' : 'Connect & continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

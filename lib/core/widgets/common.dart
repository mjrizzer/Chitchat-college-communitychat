import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String friendlyError(Object error) => error is StateError
    ? error.message.toString()
    : error is AuthException
    ? error.message
    : error is PostgrestException
    ? error.message
    : 'Unable to connect. Check your connection and try again.';
void showError(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(friendlyError(error))));

class InitialAvatar extends StatelessWidget {
  const InitialAvatar(this.name, {super.key, this.url});
  final String name;
  final String? url;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
    child: url != null && url!.isNotEmpty
        ? ClipOval(
            child: Image.network(
              url!,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Text(initials(name)),
            ),
          )
        : Text(initials(name)),
  );
}

String initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .take(2);
  return parts.isEmpty
      ? '?'
      : parts.map((p) => p.characters.first.toUpperCase()).join();
}

class StatusView extends StatelessWidget {
  const StatusView(this.title, {super.key, this.detail, this.retry});
  final String title;
  final String? detail;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            retry == null
                ? Icons.auto_awesome_outlined
                : Icons.cloud_off_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(detail!, textAlign: TextAlign.center),
          ],
          if (retry != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: retry, child: const Text('Try again')),
          ],
        ],
      ),
    ),
  );
}

import 'package:flutter/material.dart';

Future<String?> textPrompt(
  BuildContext context,
  String title, {
  String initial = '',
  int maxLength = 2000,
}) async {
  return showDialog<String>(
    context: context,
    builder: (_) =>
        _TextPrompt(title: title, initial: initial, maxLength: maxLength),
  );
}

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.initial,
    required this.maxLength,
  });
  final String title, initial;
  final int maxLength;
  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final input = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: input,
      autofocus: true,
      maxLength: widget.maxLength,
      minLines: 1,
      maxLines: 5,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, input.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}

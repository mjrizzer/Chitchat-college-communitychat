import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'common.dart';

class AsyncList<T> extends StatelessWidget {
  const AsyncList({
    super.key,
    required this.value,
    required this.itemBuilder,
    required this.refresh,
    this.empty = 'Nothing here yet',
    this.footer,
  });
  final AsyncValue<List<T>> value;
  final Widget Function(T) itemBuilder;
  final Future<void> Function() refresh;
  final String empty;
  final Widget? footer;
  @override
  Widget build(BuildContext context) => value.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (e, _) => StatusView(
      'Could not load this page',
      detail: friendlyError(e),
      retry: refresh,
    ),
    data: (items) => RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 80),
              child: StatusView(empty),
            ),
          ...items.map(itemBuilder),
          ?footer,
        ],
      ),
    ),
  );
}

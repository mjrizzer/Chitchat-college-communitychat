import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/state/session.dart';

final blockedUsersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
      (ref) => ref
          .watch(clientProvider)
          .from('user_blocks')
          .select('blocked_id,profiles!blocked_id(name)'),
    );
final blockRevisionProvider = NotifierProvider<BlockRevision, int>(
  BlockRevision.new,
);

class BlockRevision extends Notifier<int> {
  @override
  int build() => 0;
  void changed() => state++;
}

import 'app_database.dart';
import 'local_media_store.dart';

/// Remove only media that no longer has a database reference. Failed cleanup
/// is retried at the next launch, without changing a completed database write.
Future<void> pruneUnreferencedMedia(
  AppDatabase database,
  LocalMediaStore mediaStore,
) async {
  try {
    final referenced = database.photoPaths(await database.snapshot());
    await mediaStore.pruneUnreferenced(referenced);
  } catch (_) {
    // A media cleanup failure must not turn a committed edit into a failed edit.
  }
}

Future<void> removeUnreferencedMedia(
  AppDatabase database,
  LocalMediaStore mediaStore,
  Iterable<String> candidates,
) async {
  final names = candidates.toSet();
  if (names.isEmpty) return;
  try {
    final referenced = database.photoPaths(await database.snapshot());
    await mediaStore.deleteFiles(names.difference(referenced));
  } catch (_) {
    // Launch-time pruning retries files left by a failed cleanup.
  }
}

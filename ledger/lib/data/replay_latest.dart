import 'dart:async';

/// Wraps a stream so that every listener immediately receives the latest
/// value, even if it starts listening after that value was emitted.
///
/// Firestore's `snapshots()` is a broadcast stream: a second widget that
/// subscribes after the first snapshot arrived gets nothing until the data
/// changes again, so it stays on its loading state. Screens that share one
/// transactions stream between the list and the download button hit exactly
/// that. With this wrapper, a late listener gets the current data at once.
///
/// One underlying subscription is shared by all listeners and cancelled when
/// the last listener goes away.
Stream<T> replayLatest<T>(Stream<T> source) {
  final listeners = <MultiStreamController<T>>{};
  StreamSubscription<T>? sub;
  late T latest;
  var hasLatest = false;
  Object? lastError;
  StackTrace? lastStack;

  return Stream<T>.multi((controller) {
    listeners.add(controller);
    if (hasLatest) {
      controller.add(latest);
    } else if (lastError != null) {
      controller.addError(lastError!, lastStack);
    }

    sub ??= source.listen(
      (value) {
        latest = value;
        hasLatest = true;
        lastError = null;
        for (final l in listeners.toList()) {
          l.add(value);
        }
      },
      onError: (Object e, StackTrace s) {
        lastError = e;
        lastStack = s;
        for (final l in listeners.toList()) {
          l.addError(e, s);
        }
      },
    );

    controller.onCancel = () {
      listeners.remove(controller);
      if (listeners.isEmpty) {
        sub?.cancel();
        sub = null;
        hasLatest = false;
        lastError = null;
      }
    };
  }, isBroadcast: true);
}

import 'package:flutter/foundation.dart';

import 'store_update_labels.dart';

/// An update the app forced (`StoreUpdateController.forceUpdate`), as given
/// to the forced prompt, built-in or your own.
///
/// Call [onUpdate] from the prompt's "Update now" button and [onUpdateCancel]
/// from its "Exit" button, or leave [onUpdateCancel] out and run your own
/// logic instead. Nothing closes the prompt: it stays until the app restarts.
@immutable
class ForcedUpdatePrompt {
  const ForcedUpdatePrompt({
    required this.labels,
    required this.onUpdate,
    required this.onUpdateCancel,
    this.busy = false,
    this.failed = false,
    this.progress,
  });

  /// The text to show.
  final StoreUpdateLabels labels;

  /// Starts the update: Play's full-screen update, or the store page.
  final VoidCallback onUpdate;

  /// Declines the update. Runs the controller's `onUpdateCancel`, which
  /// closes the app unless you gave the controller your own.
  final VoidCallback onUpdateCancel;

  /// An update step is under way (for example a background download that
  /// installs when it finishes): show progress rather than "Update now".
  final bool busy;

  /// The last attempt to update failed ([StoreUpdateLabels.forcedFailed]).
  final bool failed;

  /// While [busy] with a background download: 0..1, or null when unknown.
  final double? progress;
}

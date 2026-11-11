import 'package:flutter/material.dart';

import 'store_update_labels.dart';

/// An offer of a newer version, as given to a custom offer prompt.
///
/// Call [onUpdate] from the prompt's "Update" button and [onLater] from its
/// "Later" button. Both close the prompt. [onLater] is null for a [required]
/// offer, which must not offer "Later".
@immutable
class UpdateOffer {
  const UpdateOffer({
    required this.labels,
    required this.onUpdate,
    this.onLater,
    this.storeVersion,
  });

  /// The text to show.
  final StoreUpdateLabels labels;

  /// Closes the prompt and starts the update.
  final VoidCallback onUpdate;

  /// Closes the prompt without updating; null when the update is required.
  final VoidCallback? onLater;

  /// The App Store version, for an iOS App Store offer; null on Google Play.
  final String? storeVersion;

  /// Whether the update is required, so the prompt has no "Later".
  bool get required => onLater == null;
}

/// Shows the offer prompt that [builder] builds, in a route of its own, and
/// completes with `true` for "Update" and `false` or `null` for "Later".
///
/// The prompt's buttons close it with `Navigator.pop`, so [builder] must be
/// shown as a route (a sheet, a dialog or a page). When [required] is true
/// the route must not close on a tap outside it; back is already blocked.
///
/// [showUpdateOfferSheet] is the default; [showUpdateOfferDialog] shows a
/// dialog instead.
typedef OfferPresenter =
    Future<bool?> Function(
      BuildContext context,
      WidgetBuilder builder, {
      required bool required,
    });

/// Shows the offer prompt in a modal bottom sheet with a drag handle (the
/// default [OfferPresenter]).
Future<bool?> showUpdateOfferSheet(
  BuildContext context,
  WidgetBuilder builder, {
  required bool required,
}) => showModalBottomSheet<bool>(
  context: context,
  isDismissible: !required,
  enableDrag: !required,
  showDragHandle: true,
  useSafeArea: true,
  builder: builder,
);

/// Shows the offer prompt in a centred dialog, at most 480 wide.
Future<bool?> showUpdateOfferDialog(
  BuildContext context,
  WidgetBuilder builder, {
  required bool required,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: !required,
  builder: (context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        // UpdateOfferSheet leaves its top to a sheet's drag handle.
        padding: const EdgeInsetsDirectional.only(top: 24),
        child: Builder(builder: builder),
      ),
    ),
  ),
);

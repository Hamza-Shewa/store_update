import 'package:flutter/material.dart';

import '../store_update_controller.dart';
import 'store_update_labels.dart';
import 'update_widgets.dart';

/// Builds a custom offer sheet. It must pop `true` for "Update" and `false`
/// for "Later". [storeVersion] is set for an iOS App Store offer; a
/// [required] offer must not offer "Later".
typedef OfferSheetBuilder =
    Widget Function(
      BuildContext context,
      StoreUpdateLabels labels, {
      String? storeVersion,
      required bool required,
    });

/// Builds a custom download bar. Call `controller.restartToInstall` from its
/// restart button once [StoreUpdateController.phase] is ready to install.
typedef ProgressBarBuilder =
    Widget Function(
      BuildContext context,
      StoreUpdateController controller,
      StoreUpdateLabels labels,
    );

/// Builds a custom required-update page. Call `controller.retryImmediate`
/// and `controller.openStore` from its buttons.
typedef RequiredPageBuilder =
    Widget Function(
      BuildContext context,
      StoreUpdateController controller,
      StoreUpdateLabels labels,
    );

/// Wraps the app with the update UI: the offer sheet, a download bar across
/// the top while a background update downloads, and a page that waits when a
/// required update was not installed.
///
/// It starts [controller]'s checks when first built, so place it where the
/// app is ready for them (for example after onboarding). It must sit below a
/// [Navigator] (for the sheet) and a [MediaQuery].
class StoreUpdateGate extends StatefulWidget {
  const StoreUpdateGate({
    super.key,
    required this.controller,
    required this.child,
    this.appName,
    this.labels,
    this.offerSheetBuilder,
    this.progressBarBuilder,
    this.requiredPageBuilder,
  }) : assert(
         appName != null || labels != null,
         'Give appName for the built-in text, or labels.',
       );

  final StoreUpdateController controller;
  final Widget child;

  /// The app's name in the built-in text ([StoreUpdateLabels.of]).
  final String? appName;

  /// The text to show; the built-in English or Arabic text when null.
  final StoreUpdateLabels Function(BuildContext context)? labels;

  final OfferSheetBuilder? offerSheetBuilder;
  final ProgressBarBuilder? progressBarBuilder;
  final RequiredPageBuilder? requiredPageBuilder;

  /// Key of the download bar.
  static const barKey = Key('store-update-bar');

  /// Key of the required-update page.
  static const requiredKey = Key('store-update-required');

  @override
  State<StoreUpdateGate> createState() => _StoreUpdateGateState();
}

class _StoreUpdateGateState extends State<StoreUpdateGate> {
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    widget.controller.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onChange());
  }

  @override
  void didUpdateWidget(StoreUpdateGate old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChange);
      widget.controller.addListener(_onChange);
      widget.controller.start();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  StoreUpdateLabels _labels(BuildContext context) =>
      widget.labels?.call(context) ??
      StoreUpdateLabels.of(context, appName: widget.appName!);

  void _onChange() {
    if (!mounted || _sheetOpen) return;
    final phase = widget.controller.phase;
    if (phase == UpdatePhase.offerFlexible || phase == UpdatePhase.offerStore) {
      _showOffer();
    }
  }

  Future<void> _showOffer() async {
    _sheetOpen = true;
    final c = widget.controller;
    final required = c.phase == UpdatePhase.offerFlexible && c.offerRequired;
    final storeVersion = c.phase == UpdatePhase.offerStore
        ? c.storeVersion
        : null;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: !required,
      enableDrag: !required,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) {
        final labels = _labels(context);
        final custom = widget.offerSheetBuilder;
        return custom != null
            ? custom(
                context,
                labels,
                storeVersion: storeVersion,
                required: required,
              )
            : UpdateOfferSheet(
                labels: labels,
                storeVersion: storeVersion,
                required: required,
              );
      },
    );
    _sheetOpen = false;
    if (!mounted) return;
    if (accepted == true) {
      await c.accept();
    } else {
      c.dismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      child: widget.child,
      builder: (context, child) {
        final phase = c.phase;
        final showBar =
            phase == UpdatePhase.downloading ||
            phase == UpdatePhase.readyToInstall;
        final blocked = phase == UpdatePhase.required;
        final labels = showBar || blocked ? _labels(context) : null;
        // The same tree shape in every phase, so the app keeps its state.
        return Stack(
          children: [
            Offstage(
              offstage: blocked,
              child: TickerMode(
                enabled: !blocked,
                child: Column(
                  children: [
                    showBar
                        ? KeyedSubtree(
                            key: StoreUpdateGate.barKey,
                            child:
                                widget.progressBarBuilder?.call(
                                  context,
                                  c,
                                  labels!,
                                ) ??
                                UpdateProgressBar(
                                  labels: labels!,
                                  progress: c.progress,
                                  ready: phase == UpdatePhase.readyToInstall,
                                  onRestart: c.restartToInstall,
                                ),
                          )
                        : const SizedBox.shrink(),
                    Expanded(
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: showBar,
                        child: child!,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (blocked)
              Positioned.fill(
                child: KeyedSubtree(
                  key: StoreUpdateGate.requiredKey,
                  child:
                      widget.requiredPageBuilder?.call(context, c, labels!) ??
                      RequiredUpdatePage(
                        labels: labels!,
                        failed: c.immediateFailed,
                        onUpdate: c.retryImmediate,
                        onOpenStore: c.openStore,
                      ),
                ),
              ),
          ],
        );
      },
    );
  }
}

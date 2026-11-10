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
/// the top while a background update downloads, and a page (a route that
/// back cannot leave) that waits when a required update was not installed.
///
/// It starts [controller]'s checks once built with [enabled] true, so turn it
/// on when the app is ready for them (for example after onboarding).
///
/// Where to put it:
/// - In `MaterialApp.builder`, with the app's [navigatorKey], so the
///   required-update page and the download bar cover every route:
///
///   ```dart
///   MaterialApp(
///     navigatorKey: navigatorKey,
///     builder: (context, child) => StoreUpdateGate(
///       controller: updates,
///       navigatorKey: navigatorKey,
///       appName: 'My App',
///       child: child!,
///     ),
///   );
///   ```
/// - Or around one screen (below a [Navigator]). The required-update page
///   still covers every route (it is pushed on the root navigator), but the
///   download bar shows only on that screen.
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
    this.navigatorKey,
    this.enabled = true,
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

  /// The app's navigator, for showing the offer sheet when the gate sits
  /// above it (in `MaterialApp.builder`). When null the sheet uses the
  /// nearest [Navigator] above the gate.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Whether to check and show anything. While false the gate shows only
  /// [child] (with the same widget tree, so [child] keeps its state).
  final bool enabled;

  /// Key of the download bar.
  static const barKey = Key('store-update-bar');

  /// Key of the required-update page.
  static const requiredKey = Key('store-update-required');

  @override
  State<StoreUpdateGate> createState() => _StoreUpdateGateState();
}

class _StoreUpdateGateState extends State<StoreUpdateGate> {
  bool _sheetOpen = false;

  /// The required-update page, pushed on the root navigator so it covers
  /// every route and back cannot leave it.
  Route<void>? _requiredRoute;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    _startIfEnabled();
  }

  @override
  void didUpdateWidget(StoreUpdateGate old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChange);
      widget.controller.addListener(_onChange);
    }
    if (old.controller != widget.controller || old.enabled != widget.enabled) {
      _startIfEnabled();
    }
  }

  void _startIfEnabled() {
    if (widget.enabled) widget.controller.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onChange());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    _removeRequiredRoute();
    super.dispose();
  }

  StoreUpdateLabels _labels(BuildContext context) =>
      widget.labels?.call(context) ??
      StoreUpdateLabels.of(context, appName: widget.appName!);

  NavigatorState? get _navigator =>
      widget.navigatorKey?.currentState ??
      Navigator.maybeOf(context, rootNavigator: true);

  void _onChange() {
    if (!mounted) return;
    final phase = widget.enabled ? widget.controller.phase : UpdatePhase.idle;
    _syncRequiredRoute(phase == UpdatePhase.required);
    if (_sheetOpen) return;
    if (phase == UpdatePhase.offerFlexible || phase == UpdatePhase.offerStore) {
      _showOffer();
    }
  }

  void _syncRequiredRoute(bool blocked) {
    if (blocked && _requiredRoute == null) {
      final navigator = _navigator;
      if (navigator == null) return;
      final c = widget.controller;
      final route = MaterialPageRoute<void>(
        builder: (context) => PopScope(
          canPop: false,
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) {
              final labels = _labels(context);
              return KeyedSubtree(
                key: StoreUpdateGate.requiredKey,
                child:
                    widget.requiredPageBuilder?.call(context, c, labels) ??
                    RequiredUpdatePage(
                      labels: labels,
                      failed: c.immediateFailed,
                      onUpdate: c.retryImmediate,
                      onOpenStore: c.openStore,
                    ),
              );
            },
          ),
        ),
      );
      _requiredRoute = route;
      navigator.push(route);
    } else if (!blocked) {
      _removeRequiredRoute();
    }
  }

  void _removeRequiredRoute() {
    final route = _requiredRoute;
    _requiredRoute = null;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  Future<void> _showOffer() async {
    final navigatorContext = _navigator?.context;
    if (navigatorContext == null) return;
    _sheetOpen = true;
    final c = widget.controller;
    final required = c.phase == UpdatePhase.offerFlexible && c.offerRequired;
    final storeVersion = c.phase == UpdatePhase.offerStore
        ? c.storeVersion
        : null;
    final accepted = await showModalBottomSheet<bool>(
      context: navigatorContext,
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
        final phase = widget.enabled ? c.phase : UpdatePhase.idle;
        final showBar =
            phase == UpdatePhase.downloading ||
            phase == UpdatePhase.readyToInstall;
        final labels = showBar ? _labels(context) : null;
        // The same tree shape in every phase, so the app keeps its state.
        return Column(
          children: [
            showBar
                ? KeyedSubtree(
                    key: StoreUpdateGate.barKey,
                    child:
                        widget.progressBarBuilder?.call(context, c, labels!) ??
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
        );
      },
    );
  }
}

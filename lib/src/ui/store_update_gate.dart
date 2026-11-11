import 'dart:async';

import 'package:flutter/material.dart';

import '../store_update_controller.dart';
import 'forced_update_prompt.dart';
import 'store_update_labels.dart';
import 'update_offer.dart';
import 'update_widgets.dart';

/// Builds a custom offer prompt. Call [UpdateOffer.onUpdate] and
/// [UpdateOffer.onLater] from its buttons; a required offer has no
/// `onLater`. Return [UpdateOfferSheet] to keep the built-in prompt with
/// changes.
typedef OfferBuilder = Widget Function(BuildContext context, UpdateOffer offer);

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

/// Builds the forced-update prompt from [prompt]: call
/// [ForcedUpdatePrompt.onUpdate] and [ForcedUpdatePrompt.onUpdateCancel]
/// from its buttons, or run your own logic instead of `onUpdateCancel`.
/// Return [ForcedUpdateDialog] to keep the built-in prompt with changes. It
/// is shown over a barrier that blocks the app; nothing closes it.
typedef ForcedPromptBuilder =
    Widget Function(BuildContext context, ForcedUpdatePrompt prompt);

/// Wraps the app with the update UI: the offer prompt (a bottom sheet unless
/// [offerPresenter] says otherwise), a download bar across the top while a
/// background update downloads, and a page (a route that back cannot leave)
/// that waits when a required update was not installed.
///
/// It starts [controller]'s checks once built with [enabled] true, so turn it
/// on when the app is ready for them (for example after onboarding).
///
/// Set [forceUpdate] when the app's own backend says this version must
/// update (see [StoreUpdateController.forceUpdate]).
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
    this.offerBuilder,
    this.offerPresenter,
    this.progressBarBuilder,
    this.requiredPageBuilder,
    this.forcedPromptBuilder,
    this.forcedBarrierColor,
    this.navigatorKey,
    this.enabled = true,
    this.forceUpdate = false,
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

  /// Builds the offer prompt; [UpdateOfferSheet] when null.
  final OfferBuilder? offerBuilder;

  /// Shows the offer prompt; [showUpdateOfferSheet] (a bottom sheet) when
  /// null. [showUpdateOfferDialog] shows a dialog instead.
  final OfferPresenter? offerPresenter;

  final ProgressBarBuilder? progressBarBuilder;
  final RequiredPageBuilder? requiredPageBuilder;

  /// Builds the forced-update prompt; [ForcedUpdateDialog] when null.
  final ForcedPromptBuilder? forcedPromptBuilder;

  /// The colour over the app behind the forced prompt; the dialog theme's
  /// barrier colour, or black at 54%, when null.
  final Color? forcedBarrierColor;

  /// The app's navigator, for showing the offer prompt when the gate sits
  /// above it (in `MaterialApp.builder`). When null the prompt uses the
  /// nearest [Navigator] above the gate.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Whether to check and show anything. While false the gate shows only
  /// [child] (with the same widget tree, so [child] keeps its state).
  final bool enabled;

  /// Whether the app requires this version to update, typically from the
  /// app's backend on launch. Once true it calls
  /// [StoreUpdateController.forceUpdate], and the app waits behind a prompt
  /// with "Update now" and "Exit" ([forcedPromptBuilder] to change it);
  /// setting it back to false does not undo that. It applies even while
  /// [enabled] is false.
  final bool forceUpdate;

  /// Key of the download bar.
  static const barKey = Key('store-update-bar');

  /// Key of the required-update page.
  static const requiredKey = Key('store-update-required');

  /// Key of the forced-update prompt.
  static const forcedKey = Key('store-update-forced');

  @override
  State<StoreUpdateGate> createState() => _StoreUpdateGateState();
}

class _StoreUpdateGateState extends State<StoreUpdateGate> {
  bool _offerOpen = false;

  /// The required-update page, pushed on the root navigator so it covers
  /// every route and back cannot leave it.
  Route<void>? _requiredRoute;

  /// Whether a navigator is above the gate. Then the forced prompt is an
  /// entry on the root navigator's overlay ([_ForcedOverlay]); otherwise (in
  /// `MaterialApp.builder`) the gate draws it over [StoreUpdateGate.child].
  bool _belowNavigator = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    _startIfEnabled();
    _forceIfAsked();
  }

  @override
  void didUpdateWidget(StoreUpdateGate old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChange);
      widget.controller.addListener(_onChange);
      // Shown again for the new controller, if it is forced, after the frame.
      _ForcedOverlay.remove(old.controller);
    } else {
      // The entry is outside this subtree, so it rebuilds after the frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ForcedOverlay.of(widget.controller)?.update(_layer());
      });
    }
    if (old.controller != widget.controller || old.enabled != widget.enabled) {
      _startIfEnabled();
    }
    if (old.controller != widget.controller ||
        old.forceUpdate != widget.forceUpdate) {
      // A forced update lasts until the app restarts, so a new controller
      // takes it over even when the flag is now false.
      _forceIfAsked(carryOver: old.controller.forced);
    }
  }

  void _forceIfAsked({bool carryOver = false}) {
    if (!widget.forceUpdate && !carryOver) return;
    // After the frame: forcing notifies listeners, which show the prompt.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (widget.forceUpdate || carryOver)) {
        unawaited(widget.controller.forceUpdate());
      }
    });
  }

  void _startIfEnabled() {
    if (widget.enabled) widget.controller.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onChange());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _belowNavigator = Navigator.maybeOf(context) != null;
  }

  @override
  void dispose() {
    _ForcedOverlay.leaveTree(widget.controller, this);
    widget.controller.removeListener(_onChange);
    _removeRequiredRoute();
    // A forced prompt stays: it lasts until the app restarts, even when the
    // screen this gate wrapped is replaced.
    super.dispose();
  }

  StoreUpdateLabels _labels(BuildContext context) =>
      widget.labels?.call(context) ??
      StoreUpdateLabels.of(context, appName: widget.appName!);

  NavigatorState? get _navigator =>
      widget.navigatorKey?.currentState ??
      Navigator.maybeOf(context, rootNavigator: true);

  /// The controller's phase, or idle while not [StoreUpdateGate.enabled]
  /// (a forced update shows regardless).
  UpdatePhase get _phase {
    final phase = widget.controller.phase;
    return widget.enabled || phase == UpdatePhase.forced
        ? phase
        : UpdatePhase.idle;
  }

  void _onChange() {
    if (!mounted) return;
    final phase = _phase;
    _syncRequiredRoute(phase == UpdatePhase.required);
    _syncForcedEntry(_belowNavigator && phase == UpdatePhase.forced);
    if (_offerOpen) return;
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

  void _syncForcedEntry(bool show) {
    final c = widget.controller;
    if (!show) return _ForcedOverlay.remove(c);
    final shown = _ForcedOverlay.of(c);
    // Still on screen (taken over from a gate that is gone): keep it.
    if (shown != null && shown.live) return shown.update(_layer());
    // A gate in MaterialApp.builder already covers the whole app.
    if (_ForcedOverlay.drawnInTree(c)) return;
    // Gone with a navigator the app replaced: show it on the current one.
    _ForcedOverlay.remove(c);
    final overlay = Navigator.maybeOf(context, rootNavigator: true)?.overlay;
    if (overlay != null) _ForcedOverlay.show(c, overlay, _layer());
  }

  /// The forced prompt for this gate's settings.
  _ForcedLayer _layer() {
    final labels = widget.labels, appName = widget.appName;
    return _ForcedLayer(
      controller: widget.controller,
      builder: widget.forcedPromptBuilder,
      barrierColor: widget.forcedBarrierColor,
      labels: (context) =>
          labels?.call(context) ??
          StoreUpdateLabels.of(context, appName: appName!),
    );
  }

  void _removeRequiredRoute() {
    final route = _requiredRoute;
    _requiredRoute = null;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  Future<void> _showOffer() async {
    final navigatorContext = _navigator?.context;
    if (navigatorContext == null) return;
    _offerOpen = true;
    final c = widget.controller;
    final required = c.phase == UpdatePhase.offerFlexible && c.offerRequired;
    final storeVersion = c.phase == UpdatePhase.offerStore
        ? c.storeVersion
        : null;
    final present = widget.offerPresenter ?? showUpdateOfferSheet;
    bool? accepted;
    try {
      accepted = await present(navigatorContext, (context) {
        final offer = UpdateOffer(
          labels: _labels(context),
          storeVersion: storeVersion,
          onUpdate: () => Navigator.pop(context, true),
          onLater: required ? null : () => Navigator.pop(context, false),
        );
        // Back can't close a required offer, whatever the prompt.
        return PopScope(
          canPop: !required,
          child:
              widget.offerBuilder?.call(context, offer) ??
              UpdateOfferSheet(offer: offer),
        );
      }, required: required);
    } catch (error, stack) {
      // Treated as "Later", so the controller is not left on an offer that
      // nothing shows; the next check offers it again as usual.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'store_update',
          context: ErrorDescription('while showing the update offer'),
        ),
      );
    } finally {
      _offerOpen = false;
    }
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
        final phase = _phase;
        final showBar =
            phase == UpdatePhase.downloading ||
            phase == UpdatePhase.readyToInstall;
        final labels = showBar ? _labels(context) : null;
        // Above a navigator nothing else could cover the app, so the gate
        // draws the forced prompt itself, unless a gate below already shows
        // it on the navigator's overlay.
        final forcedHere =
            phase == UpdatePhase.forced &&
            !_belowNavigator &&
            !(_ForcedOverlay.of(c)?.live ?? false);
        if (forcedHere) {
          _ForcedOverlay.enterTree(c, this);
        } else {
          _ForcedOverlay.leaveTree(c, this);
        }
        // The same tree shape in every phase, so the app keeps its state.
        final app = Column(
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
        return Stack(
          fit: StackFit.expand,
          children: [
            ExcludeFocus(excluding: forcedHere, child: app),
            // Its own overlay, for tooltips and text fields in a custom
            // prompt: there is no navigator above the gate here.
            if (forcedHere) Overlay.wrap(child: _layer()),
          ],
        );
      },
    );
  }
}

/// The forced prompt over a barrier that blocks the app beneath, also from
/// screen readers, holding the keyboard focus while it shows. It holds what
/// it needs itself, so it can outlive the gate.
class _ForcedLayer extends StatefulWidget {
  const _ForcedLayer({
    required this.controller,
    required this.builder,
    required this.barrierColor,
    required this.labels,
  });

  final StoreUpdateController controller;
  final ForcedPromptBuilder? builder;
  final Color? barrierColor;
  final StoreUpdateLabels Function(BuildContext context) labels;

  @override
  State<_ForcedLayer> createState() => _ForcedLayerState();
}

class _ForcedLayerState extends State<_ForcedLayer> {
  final _focus = FocusScopeNode(debugLabel: 'store_update forced prompt');

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_keepFocus);
  }

  /// Takes the focus back from the app beneath (a keyboard, D-pad or switch
  /// could otherwise press its buttons) and from anything that requests it.
  void _keepFocus() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null ||
        focus == _focus ||
        focus.ancestors.contains(_focus) ||
        _focus.context == null) {
      return;
    }
    _focus.requestFocus();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_keepFocus);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final prompt = ForcedUpdatePrompt(
          labels: widget.labels(context),
          onUpdate: c.startForcedUpdate,
          onUpdateCancel: c.cancelForcedUpdate,
          busy: c.forcedBusy,
          failed: c.forcedFailed,
          progress: c.forcedDownloading ? c.progress : null,
        );
        return KeyedSubtree(
          key: StoreUpdateGate.forcedKey,
          child: FocusScope(
            node: _focus,
            autofocus: true,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ModalBarrier(
                  dismissible: false,
                  color:
                      widget.barrierColor ??
                      DialogTheme.of(context).barrierColor ??
                      Colors.black54,
                ),
                widget.builder?.call(context, prompt) ??
                    ForcedUpdateDialog(prompt: prompt),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A controller's forced prompt on the root navigator's overlay. The
/// navigator keeps entries that are not routes above its routes, so no
/// navigation removes or covers it. One per controller: a gate built later
/// takes over the one already showing, or shows it again on a new navigator
/// when the app replaced the old one.
class _ForcedOverlay {
  _ForcedOverlay._(this._overlay, this._layer) {
    _entry = OverlayEntry(builder: (_) => _layer);
  }

  static final _shown = Expando<_ForcedOverlay>('store_update forced prompt');

  /// The gate that draws a controller's prompt itself (in
  /// `MaterialApp.builder`), so gates below don't show a second one.
  static final _inTree = Expando<State>('store_update forced prompt drawer');

  final OverlayState _overlay;
  _ForcedLayer _layer;
  late final OverlayEntry _entry;

  /// Whether its overlay is still on screen.
  bool get live => _overlay.mounted;

  static _ForcedOverlay? of(StoreUpdateController controller) =>
      _shown[controller];

  static void show(
    StoreUpdateController controller,
    OverlayState overlay,
    _ForcedLayer layer,
  ) {
    final shown = _ForcedOverlay._(overlay, layer);
    _shown[controller] = shown;
    overlay.insert(shown._entry);
  }

  static void remove(StoreUpdateController controller) {
    final shown = _shown[controller];
    if (shown == null) return;
    _shown[controller] = null;
    shown._entry
      ..remove()
      ..dispose();
  }

  static bool drawnInTree(StoreUpdateController controller) =>
      _inTree[controller]?.mounted ?? false;

  static void enterTree(StoreUpdateController controller, State gate) {
    if (!drawnInTree(controller)) _inTree[controller] = gate;
  }

  static void leaveTree(StoreUpdateController controller, State gate) {
    if (identical(_inTree[controller], gate)) _inTree[controller] = null;
  }

  void update(_ForcedLayer layer) {
    _layer = layer;
    if (_entry.mounted) _entry.markNeedsBuild();
  }
}

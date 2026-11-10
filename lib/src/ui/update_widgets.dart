import 'package:flutter/material.dart';

import 'store_update_labels.dart';

/// Spacing and sizes of the built-in UI (a 4-point grid).
abstract final class _Space {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const radius = 20.0;

  /// The smallest touch target (Material and WCAG guidance).
  static const target = 48.0;
}

const _minButton = Size(_Space.target, _Space.target);

/// The offer of a newer version: an Android background download, or (with
/// [storeVersion]) an iOS App Store version. Pops `true` for "Update" and
/// `false` for "Later". A [required] offer has no "Later" and back does not
/// close it.
class UpdateOfferSheet extends StatelessWidget {
  const UpdateOfferSheet({
    super.key,
    required this.labels,
    this.storeVersion,
    this.required = false,
  });

  final StoreUpdateLabels labels;
  final String? storeVersion;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final version = storeVersion;
    final title = version != null
        ? labels.storeOfferTitle(version)
        : labels.offerTitle;
    final body = version != null
        ? labels.storeOfferBody
        : required
        ? labels.offerRequiredBody
        : labels.offerBody;
    return PopScope(
      canPop: !required,
      // Scrolls on short screens (a phone in landscape, large text).
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(
          _Space.xl,
          0,
          _Space.xl,
          _Space.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: UpdateBadge(size: 56),
            ),
            const SizedBox(height: _Space.md),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: _Space.xs),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: _Space.xl),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: _minButton),
              onPressed: () => Navigator.pop(context, true),
              child: Text(labels.update),
            ),
            if (!required) ...[
              const SizedBox(height: _Space.xs),
              TextButton(
                style: TextButton.styleFrom(minimumSize: _minButton),
                onPressed: () => Navigator.pop(context, false),
                child: Text(labels.later),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The bar across the top of the app while a background update downloads,
/// then "Restart to update" once it is [ready].
class UpdateProgressBar extends StatelessWidget {
  const UpdateProgressBar({
    super.key,
    required this.labels,
    required this.progress,
    required this.ready,
    required this.onRestart,
  });

  final StoreUpdateLabels labels;

  /// 0..1, or null while the size is unknown (an indeterminate bar).
  final double? progress;
  final bool ready;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final p = progress;
    final percent = p == null ? null : (p * 100).floor().clamp(0, 100);
    final title = ready ? labels.ready : labels.downloading;
    return Material(
      color: cs.surfaceContainerHigh,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            _Space.md,
            _Space.xs,
            _Space.xs,
            _Space.xs,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _Space.target),
            child: Row(
              children: [
                Icon(
                  ready ? Icons.download_done : Icons.downloading,
                  color: cs.primary,
                ),
                const SizedBox(width: _Space.sm),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        liveRegion: true,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                            if (!ready && percent != null)
                              Text(
                                labels.percent(percent),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (!ready) ...[
                        const SizedBox(height: _Space.xxs),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(_Space.radius),
                          child: LinearProgressIndicator(
                            value: p,
                            minHeight: 4,
                            semanticsLabel: title,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (ready) ...[
                  const SizedBox(width: _Space.xs),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(minimumSize: _minButton),
                    onPressed: onRestart,
                    child: Text(labels.restart),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when a required update was not installed: explains why and offers
/// Play's update again, or the store itself. Back does not leave it.
class RequiredUpdatePage extends StatelessWidget {
  const RequiredUpdatePage({
    super.key,
    required this.labels,
    required this.failed,
    required this.onUpdate,
    required this.onOpenStore,
  });

  final StoreUpdateLabels labels;

  /// Play's update failed, rather than being closed by the user.
  final bool failed;
  final VoidCallback onUpdate;
  final VoidCallback onOpenStore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(_Space.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: UpdateBadge(size: 72)),
                    const SizedBox(height: _Space.lg),
                    Text(
                      labels.requiredTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: _Space.sm),
                    Text(
                      labels.requiredBody,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (failed) ...[
                      const SizedBox(height: _Space.md),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          labels.requiredFailed,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.error,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: _Space.xl),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: _minButton),
                      onPressed: onUpdate,
                      child: Text(labels.updateNow),
                    ),
                    const SizedBox(height: _Space.xs),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: _minButton),
                      onPressed: onOpenStore,
                      child: Text(labels.openStore),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The update icon on a rounded tile, in the theme's primary container colour.
class UpdateBadge extends StatelessWidget {
  const UpdateBadge({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(_Space.radius),
        ),
        child: Icon(
          Icons.system_update,
          size: size * 0.5,
          color: cs.onPrimaryContainer,
        ),
      ),
    );
  }
}

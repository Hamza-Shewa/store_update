import 'package:flutter/material.dart';
import 'package:store_update/store_update.dart';

/// The ways the example can show the update offer.
enum PromptStyle {
  sheet('Built-in sheet', 'The default'),
  dialog(
    'Built-in prompt in a dialog',
    'offerPresenter: showUpdateOfferDialog',
  ),
  tweaked(
    'Built-in sheet with changes',
    'UpdateOfferSheet with an icon, release notes and a button colour',
  ),
  custom('Your own prompt', 'offerBuilder returning your own widget');

  const PromptStyle(this.title, this.subtitle);

  final String title;
  final String subtitle;

  /// For `StoreUpdateGate.offerPresenter`; null keeps the bottom sheet.
  OfferPresenter? get presenter =>
      this == PromptStyle.dialog ? showUpdateOfferDialog : null;

  /// For `StoreUpdateGate.offerBuilder`; null keeps the built-in prompt.
  OfferBuilder? get builder => switch (this) {
    PromptStyle.tweaked => tweakedOffer,
    PromptStyle.custom => (context, offer) => CompactOffer(offer: offer),
    _ => null,
  };
}

bool _arabic(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'ar';

/// The built-in prompt with its own icon, release notes and button colour.
Widget tweakedOffer(BuildContext context, UpdateOffer offer) {
  final cs = Theme.of(context).colorScheme;
  final ar = _arabic(context);
  return UpdateOfferSheet(
    offer: offer,
    icon: ExcludeSemantics(
      child: Icon(Icons.rocket_launch_outlined, size: 40, color: cs.tertiary),
    ),
    content: ReleaseNotes(
      title: ar ? 'ما الجديد' : "What's new",
      notes: ar
          ? const ['تسجيل دخول أسرع', 'مظهر داكن', 'عرض أوضح للنص العربي']
          : const ['Faster sign-in', 'A dark theme', 'Clearer Arabic text'],
    ),
    updateButtonStyle: FilledButton.styleFrom(
      backgroundColor: cs.tertiary,
      foregroundColor: cs.onTertiary,
    ),
  );
}

/// A short list of what changed, under the prompt's text.
class ReleaseNotes extends StatelessWidget {
  const ReleaseNotes({super.key, required this.title, required this.notes});

  final String title;
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(Icons.check_circle, size: 20, color: cs.tertiary),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(note, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}

/// A prompt of your own: a compact layout with the buttons side by side and
/// a "Required" tag. It uses the offer's text, so it follows the app's
/// language.
class CompactOffer extends StatelessWidget {
  const CompactOffer({super.key, required this.offer});

  final UpdateOffer offer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final labels = offer.labels;
    final version = offer.storeVersion;
    final onLater = offer.onLater;
    final title = version != null
        ? labels.storeOfferTitle(version)
        : labels.offerTitle;
    final body = version != null
        ? labels.storeOfferBody
        : offer.required
        ? labels.offerRequiredBody
        : labels.offerBody;
    const target = Size(48, 48);
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Icon(Icons.system_update_alt, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              if (offer.required) ...[
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      _arabic(context) ? 'مطلوب' : 'Required',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (onLater != null) ...[
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: target),
                    onPressed: onLater,
                    child: Text(labels.later),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: target),
                  onPressed: offer.onUpdate,
                  child: Text(labels.update),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

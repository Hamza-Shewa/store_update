# store_update example

Shows `StoreUpdateGate` with the real store, or with a simulated store picked
from the list: an optional Google Play update (with a download that fills the
bar), a required one, and a newer App Store version. Switch to Arabic to see
the right-to-left layout.

Under **Offer prompt**, pick how the offer is shown. A simulated store offers
again as soon as you change it:

| Style | Gate setting | Code |
|---|---|---|
| Built-in sheet | none (the default) | – |
| Built-in prompt in a dialog | `offerPresenter: showUpdateOfferDialog` | – |
| Built-in sheet with changes | `offerBuilder` returning `UpdateOfferSheet` with an `icon`, release notes as `content`, and an `updateButtonStyle` | [`tweakedOffer`](lib/prompt_styles.dart) |
| Your own prompt | `offerBuilder` returning your own widget, which calls `offer.onUpdate` and `offer.onLater` | [`CompactOffer`](lib/prompt_styles.dart) |

The simulated store offers again at once (`UpdatePolicy(promptGap:
Duration.zero)`). The real store keeps the default of once a day.

```bash
flutter run
```

To see a real Google Play update, install two builds of this app from Play's
internal app sharing or internal testing track (see the package README).

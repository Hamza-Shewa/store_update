## 0.2.0

* **Breaking:** `offerSheetBuilder` is now `offerBuilder`, and it receives an `UpdateOffer` with `onUpdate` and `onLater` callbacks instead of popping `true` or `false`. `onLater` is null when the update is required. `UpdateOfferSheet` takes the `offer` instead of `labels`, `storeVersion` and `required`.
* `offerPresenter` decides how the offer is shown. The default, `showUpdateOfferSheet`, is the existing bottom sheet; `showUpdateOfferDialog` shows a dialog instead.
* `UpdateOfferSheet` takes an optional `icon`, extra `content` under the text, and `updateButtonStyle` and `laterButtonStyle`, so the built-in prompt can be changed without rebuilding it.
* Back can't close a required offer, even in a custom prompt. A presenter that throws is reported and counts as "Later".
* The example app switches between the offer prompt styles: the built-in sheet, a dialog, the sheet with an icon, release notes and button colour, and a prompt of its own. Its simulated store offers again at once, so each style can be tried.

## 0.1.0

* First release.
* Android: Google Play In-App Updates. A required release (priority 4-5, configurable) opens Play's full-screen update, then a page that waits. Other releases are offered at most once a day as a background download with real progress and "Restart to update".
* iOS: checks the App Store version (storefront configurable) at most once a day, and shows the App Store page inside the app.
* `StoreUpdateGate` works around one screen or in `MaterialApp.builder` (with `navigatorKey`) over every screen. The required-update page is a route on the root navigator, so it covers pushed screens and back can't leave it. `enabled` delays the checks until the app is ready.
* Ready-made UI in English and Arabic (right to left), styled from the app's theme. The text can be changed and each part replaced.
* A failed check, no network, or a build not installed from the store shows nothing.

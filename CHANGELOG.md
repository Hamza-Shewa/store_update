## 0.1.0

* First release.
* Android: Google Play In-App Updates. A required release (priority 4-5, configurable) opens Play's full-screen update, then a page that waits. Other releases are offered at most once a day as a background download with real progress and "Restart to update".
* iOS: checks the App Store version (storefront configurable) at most once a day, and shows the App Store page inside the app.
* `StoreUpdateGate` works around one screen or in `MaterialApp.builder` (with `navigatorKey`) over every screen. The required-update page is a route on the root navigator, so it covers pushed screens and back can't leave it. `enabled` delays the checks until the app is ready.
* Ready-made UI in English and Arabic (right to left), styled from the app's theme. The text can be changed and each part replaced.
* A failed check, no network, or a build not installed from the store shows nothing.

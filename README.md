# store_update

In-app updates for Flutter. When a newer release is in the store, your users
update without leaving the app and watch the download happen.

- **Android:** Google Play In-App Updates. A required release opens Play's
  full-screen update. Any other release downloads in the background, with
  the real percentage shown in your app and then "Restart to update".
- **iOS:** iOS can't update in place, so the package checks the App Store
  version and shows the App Store page over your app.
- **Ready-made UI** in English and Arabic (right to left), styled from your
  `Theme`, with 48 dp touch targets. You can change the text, show the offer
  as a sheet or a dialog, adjust the built-in offer, or replace any part.
- **Force an update from your backend.** Pass a flag and the app waits behind
  **Update now** / **Exit** until the user updates. The prompt can be
  restyled or replaced entirely.
- **Never blocks by accident.** A failed check, no network, or a build not
  installed from the store shows nothing.

<table>
  <tr>
    <td><img width="200" alt="Offer to download a new version in the background" src="https://raw.githubusercontent.com/Hamza-Shewa/store_update/main/screenshots/1_offer.png"></td>
    <td><img width="200" alt="Download progress across the top of the app" src="https://raw.githubusercontent.com/Hamza-Shewa/store_update/main/screenshots/2_downloading.png"></td>
    <td><img width="200" alt="Restart to install the downloaded update" src="https://raw.githubusercontent.com/Hamza-Shewa/store_update/main/screenshots/3_ready.png"></td>
  </tr>
  <tr>
    <td><img width="200" alt="A required update the user closed" src="https://raw.githubusercontent.com/Hamza-Shewa/store_update/main/screenshots/4_required.png"></td>
    <td><img width="200" alt="The offer in Arabic, right to left" src="https://raw.githubusercontent.com/Hamza-Shewa/store_update/main/screenshots/5_offer_arabic.png"></td>
    <td><img width="200" alt="iOS: a newer App Store version" src="https://raw.githubusercontent.com/Hamza-Shewa/store_update/main/screenshots/6_app_store.png"></td>
  </tr>
  <tr>
    <td><img width="200" alt="An update forced from your backend: Update now or Exit" src="https://raw.githubusercontent.com/Hamza-Shewa/store_update/main/screenshots/7_forced.png"></td>
    <td><img width="200" alt="The forced update in Arabic, right to left" src="https://raw.githubusercontent.com/Hamza-Shewa/store_update/main/screenshots/8_forced_arabic.png"></td>
    <td><img width="200" alt="A forced-update prompt of your own design" src="https://raw.githubusercontent.com/Hamza-Shewa/store_update/main/screenshots/9_forced_custom.png"></td>
  </tr>
</table>

| | Android | iOS |
|---|---|---|
| Finds a newer version | Google Play In-App Updates (on the device, through the Play Store app) | Apple's public lookup, at most once a day |
| Required update | Play's full-screen update, then a page that waits | – |
| Forced from your backend | Play's full-screen update, or **Update now** / **Exit** | **Update now** (App Store page) / **Exit** |
| Optional update | Background download with progress, then restart | Opens the App Store page inside the app |
| Permissions | None | None |

## Install

```yaml
dependencies:
  store_update: ^0.3.0
```

There is no native setup. Android needs a minSdk of 24 and iOS needs 15. The
Android plugin uses the Android Gradle Plugin 9's built-in Kotlin, which is
the setup of apps created with Flutter 3.41 or later. Older AGP 8 projects
are untested.

## Use

Create one controller for the app's lifetime and put `StoreUpdateGate` in
`MaterialApp.builder`, so the update UI shows over every screen. The gate starts
checking once `enabled` is true, for example after sign-in or onboarding. It
checks again each time the app comes back to the foreground.

```dart
final updates = StoreUpdateController(
  appStoreCountry: 'us', // the App Store storefront to look in (iOS)
);
final navigatorKey = GlobalKey<NavigatorState>();

MaterialApp(
  navigatorKey: navigatorKey,
  builder: (context, child) => StoreUpdateGate(
    controller: updates,
    navigatorKey: navigatorKey, // needed for the offer prompt
    enabled: signedIn, // nothing is checked or shown while false
    appName: 'My App',
    child: child!,
  ),
  home: const HomeScreen(),
);
```

You can also wrap a single screen instead (`home: StoreUpdateGate(...)`). The
required-update page still covers every screen, because it opens as a route
on the root navigator. The download bar then shows only on that screen.

### When an update is offered or required

On Google Play, a release is **required** when you publish it with an in-app
update priority of 4 or 5. Everything else is optional and is offered at most
once a day. You can change both:

```dart
StoreUpdateController(
  policy: const UpdatePolicy(
    requiredPriority: 5,              // only 5 is required; 6 means never
    promptGap: Duration(hours: 72),   // offer optional updates every 3 days
  ),
);
```

| Situation | What the user sees |
|---|---|
| Optional update | A sheet: **Update** / **Later**. **Update** downloads in the background. A bar across the top shows the percentage, then **Restart to update**. |
| Required update | Play's full-screen update screen. If the user closes it, a page explains that the update is required, with **Update now** and **Open Google Play**. Back doesn't leave it. |
| Required, but Play only allows a background download | The sheet, without **Later**. |
| An update finished downloading while the app was closed | **Restart to update** on the next start. |
| No network, check failed, timeout (10 s), sideloaded build | Nothing. A required-update page that's already showing also goes away. |

Play's "staleness days" never force an update. A phone that was offline for
weeks isn't locked out.

### Forcing an update from your backend

When your own backend decides a version may no longer run (a changed API, a
security fix), pass its answer to the gate. Check on launch, then set
`forceUpdate`:

```dart
MaterialApp(
  navigatorKey: navigatorKey,
  builder: (context, child) => StoreUpdateGate(
    controller: updates,
    navigatorKey: navigatorKey,
    appName: 'My App',
    forceUpdate: mustUpdate, // from your backend, e.g. a minimum version
    child: child!,
  ),
);
```

Or call `updates.forceUpdate()` yourself once the answer arrives. From then
until the app restarts, a prompt over the whole app offers two buttons,
**Update now** and **Exit**:

| Store | What the user sees |
|---|---|
| Google Play has the update for this install | Play's full-screen update starts at once. Closing it counts as **Exit**. |
| A background download is already running | The prompt waits for it, then installs it. |
| Play's update failed, or Play doesn't know the update yet | The prompt. **Update now** runs Play's update, or opens the Play Store page. |
| App Store | The prompt. **Update now** opens the App Store page. |

No navigation removes or covers the prompt, and a tap outside it doesn't close
it. It takes the keyboard focus, so a hardware keyboard, D-pad or switch can't
reach the app beneath. It shows even while `enabled` is false and even without
`navigatorKey`. Setting `forceUpdate` back to false doesn't undo it, and a new
controller given to the gate takes the forced update over.

Some things to know:

- **Put the gate in `MaterialApp.builder`** and keep **one controller for the
  app's lifetime**. In the builder the prompt covers everything, including
  toasts and banners an SDK adds later. Around a single screen, the prompt
  sits on the navigator's overlay. It survives that screen being replaced,
  and shows again if the app rebuilds `MaterialApp`, as long as a gate with
  the same controller is in the new tree. Overlay entries added after it,
  such as some toast packages, can appear above it.
- **The system back button** still works as it always does under the
  prompt, because Flutter handles it before any package can. It may close
  screens hidden beneath the prompt, or send the app to the background,
  without running `onUpdateCancel`. The prompt is still there when the user
  comes back.
- A controller disposed while forced leaves the prompt up and its buttons
  working, but the prompt no longer shows progress or errors.

**Exit** closes the app by default: `exit(0)`, after finishing the activity on
Android. Apple discourages apps that quit themselves, so App Review may
question it on iOS, and in an app that embeds Flutter, `exit(0)` also ends the
host app. Give the controller your own `onUpdateCancel` to do something else;
`StoreUpdateController.exitApp` is there if you still want to close the app
afterwards:

```dart
final updates = StoreUpdateController(
  onUpdateCancel: () async {
    await analytics.log('force_update_declined');
    await StoreUpdateController.exitApp();
  },
);
```

#### Your own forced prompt

Every part of the prompt can change. `forcedPromptBuilder` gets a
`ForcedUpdatePrompt`: the `labels`, `onUpdate`, `onUpdateCancel`, and `busy`,
`failed` and `progress` to show what is happening. Wire `onUpdateCancel` to
your own button, or leave it out and run your own logic instead:

```dart
forcedPromptBuilder: (context, prompt) => MyBlockingPage(
  busy: prompt.busy,               // Play is being asked, or a download runs
  failed: prompt.failed,           // the update couldn't start or open
  onUpdate: prompt.onUpdate,
  onExit: prompt.onUpdateCancel,   // or: () => signOutAndClose()
),
```

Or keep the built-in dialog and change its icon, colours, shape and width,
add content under the text, or restyle its buttons:

```dart
forcedPromptBuilder: (context, prompt) => ForcedUpdateDialog(
  prompt: prompt,
  icon: const Icon(Icons.lock_clock, size: 40),
  content: const Text('This version has a security issue.'),
  exitButtonStyle: TextButton.styleFrom(foregroundColor: Colors.red),
  backgroundColor: Colors.white,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  maxWidth: 420,
),
forcedBarrierColor: Colors.black87, // the gate's colour over the app
```

Your prompt is shown over a barrier inside its own focus scope and overlay,
so tooltips, text fields and menus work in it.

The text is `forcedTitle`, `forcedBody`, `forcedFailed`, `updateNow` and
`exit` in `StoreUpdateLabels` (see below).

### Your own text

The built-in text follows the app's locale: Arabic for `ar`, English
otherwise. To change some of it:

```dart
StoreUpdateGate(
  controller: updates,
  labels: (context) => StoreUpdateLabels.of(context, appName: 'My App')
      .copyWith(requiredBody: 'This version no longer works with our servers.'),
  child: const HomeScreen(),
);
```

For another language, build a `StoreUpdateLabels` yourself.

### Your own offer prompt

The built-in prompt is a bottom sheet. You can change it in three ways, and
each one leaves the others as they are.

Show it somewhere else with `offerPresenter`. `showUpdateOfferDialog` is
built in, and any function that shows a route works:

```dart
StoreUpdateGate(
  controller: updates,
  appName: 'My App',
  offerPresenter: showUpdateOfferDialog, // default: showUpdateOfferSheet
  child: const HomeScreen(),
);
```

Keep the built-in prompt but change its icon, add content under the text, or
restyle its buttons:

```dart
offerBuilder: (context, offer) => UpdateOfferSheet(
  offer: offer,
  icon: const Icon(Icons.rocket_launch, size: 40),
  content: const Text('New: faster transfers and a dark theme.'),
  updateButtonStyle: FilledButton.styleFrom(backgroundColor: Colors.teal),
),
```

Or build your own. Call `offer.onUpdate` and `offer.onLater` from its
buttons. `onLater` is null when the update is required, and back can't close
a required prompt. `offer.storeVersion` is the App Store version on iOS:

```dart
offerBuilder: (context, offer) => MyUpdateCard(
  version: offer.storeVersion,
  onUpdate: offer.onUpdate,
  onLater: offer.onLater, // hide "Later" when null
),
```

### Your own widgets

Replace the download bar, the required-update page or the forced-update
dialog with `progressBarBuilder`, `requiredPageBuilder` or
`forcedPromptBuilder`. You can also skip the gate
entirely: listen to the controller (`phase`, `progress`, `storeVersion`) and
call `accept`, `dismiss`, `restartToInstall`, `retryImmediate`, `openStore`,
`startForcedUpdate` and `cancelForcedUpdate` from your own UI. `UpdateOfferSheet`,
`UpdateProgressBar`, `RequiredUpdatePage` and `ForcedUpdateDialog` are public
if you want to reuse them.

## Marking a release as required (Google Play)

Play reads the priority (0–5) from the release, and it is set **when the
release is created**. It can't be changed afterwards, and the Play Console
website can't set it. Use the Publishing API, or fastlane:

```ruby
upload_to_play_store(track: "internal", aab: aab, in_app_update_priority: 5)
```

Promoting a release to another track keeps its priority. To make an update
required after the fact, upload a new build with the priority you need.

## Testing a real update

In-app updates only work in a build **installed by Google Play**. A build from
`flutter run`, a sideloaded APK, or a debug build gets no update, and the
package correctly shows nothing.

1. **Internal app sharing** (fastest, but can't set a priority):
   1. Turn on internal app sharing in the Play Store's settings on the phone.
   2. Upload a build and install it from its link.
   3. Upload a build with a higher version code and open its link, but don't
      install it.
   4. Open your app.
2. **Internal testing track** (also tests required updates):
   1. Install version N from the opt-in link.
   2. Upload N+1 with `in_app_update_priority: 5`.
   3. Wait for Play to show it to the tester, then open the app.

To try the UI without a store, run the [example](example) and pick a
simulated store from the list. It also switches between the offer prompt
styles described in [Your own offer prompt](#your-own-offer-prompt).

In tests, replace the store with a fake:

```dart
class FakeStore extends StoreUpdatePlatform { /* ... */ }

StoreUpdateController(platform: FakeStore());
// or, for code that uses the default controller:
StoreUpdatePlatform.instance = FakeStore();
```

## Privacy

The package sends nothing to you or to anyone else:

- **Android:** asks the Play Store app on the device.
- **iOS:** sends one request to Apple
  (`https://itunes.apple.com/lookup?bundleId=…&country=…`) with only the bundle
  id and storefront. The iOS privacy manifest declares no tracking and no
  collected data.
- **Both:** the time of the last offer is kept in `shared_preferences`, under
  keys starting with `store_update.`.

## Licence

Apache 2.0. See [LICENSE](LICENSE).

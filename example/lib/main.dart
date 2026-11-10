import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:store_update/store_update.dart';

import 'demo_store.dart';

void main() => runApp(const ExampleApp());

/// Shows the update UI for a real store check (install this app from Google
/// Play's internal testing to see a real update), or for a simulated store
/// picked from the menu.
class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  Locale _locale = const Locale('en');
  DemoStore? _demo;
  late StoreUpdateController _updates = StoreUpdateController();

  void _simulate(DemoScenario? scenario) {
    final old = _updates;
    setState(() {
      _demo = scenario == null ? null : DemoStore(scenario);
      _updates = StoreUpdateController(platform: _demo);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _updates.dispose();
    _demo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'store_update example',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2440DB)),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF2440DB),
        brightness: Brightness.dark,
      ),
      locale: _locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorKey: _navigatorKey,
      // Over every screen: the sheet, the download bar and the required page.
      builder: (context, child) => StoreUpdateGate(
        controller: _updates,
        navigatorKey: _navigatorKey,
        appName: 'Example',
        child: child!,
      ),
      home: _Home(
        simulating: _demo?.scenario,
        onSimulate: _simulate,
        arabic: _locale.languageCode == 'ar',
        onArabic: (ar) => setState(() => _locale = Locale(ar ? 'ar' : 'en')),
      ),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home({
    required this.simulating,
    required this.onSimulate,
    required this.arabic,
    required this.onArabic,
  });

  final DemoScenario? simulating;
  final ValueChanged<DemoScenario?> onSimulate;
  final bool arabic;
  final ValueChanged<bool> onArabic;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('store_update')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Arabic (right to left)'),
            value: arabic,
            onChanged: onArabic,
          ),
          const Divider(),
          const ListTile(title: Text('Store')),
          RadioGroup<DemoScenario?>(
            groupValue: simulating,
            onChanged: onSimulate,
            child: Column(
              children: [
                const RadioListTile<DemoScenario?>(
                  value: null,
                  title: Text('Real store'),
                  subtitle: Text(
                    'Google Play or the App Store. Updates show only in a '
                    'build installed from the store.',
                  ),
                ),
                for (final s in DemoScenario.values)
                  RadioListTile<DemoScenario?>(value: s, title: Text(s.title)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

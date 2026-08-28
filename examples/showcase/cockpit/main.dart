import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:meld_showcase/main.dart';

void main() {
  runApp(
    FlutterCockpitApp(
      config: FlutterCockpitConfig.production(
        remoteSession: CockpitRemoteSessionConfiguration.resolveFromEnvironment(
          fallback: const CockpitRemoteSessionConfiguration(
            enabled: true,
            host: '127.0.0.1',
            port: 47331,
          ),
        ),
        diagnostics: const CockpitDiagnosticsConfig(
          enableRebuildTracking: true,
        ),
      ),
      child: MeldShowcaseApp(
        navigatorObservers: <NavigatorObserver>[
          FlutterCockpit.navigatorObserver,
        ],
      ),
    ),
  );
}

// Injects the Windows App SDK bits the `msix` package cannot generate.
//
//   dart run tool/patch_msix_manifest.dart --app-id=<Azure AppId> [--runtime=<ver>]
//
// Runs between `msix:build` and `msix:pack` (see windows/fastlane/Fastfile).
// The msix package renders AppxManifest.xml from its own template and exposes no
// hook for extra elements, but it *does* split building from packing — so the
// generated manifest can be patched in place before it is sealed.
//
// Two additions, both required for Windows App SDK push notifications on a
// packaged Win32 app:
//
//   1. A COM activator whose Class Id is the app's Azure AppId. WNS uses that
//      GUID to launch the right COM server when a push arrives while the app is
//      closed — this is what makes background delivery work at all.
//   2. The WindowsAppRuntime framework dependency, unless the app ships the
//      runtime self-contained.
//
// Idempotent: running it twice changes nothing.
import 'dart:io';

const _comNamespace = 'http://schemas.microsoft.com/appx/manifest/com/windows10';

/// CLSID Windows uses to activate this app when a toast is clicked.
///
/// Arbitrary but MUST stay stable: it is how the shell finds the COM server for
/// an already-delivered notification. Changing it silently breaks every
/// notification the user has not clicked yet.
const _toastActivatorClsid = 'C2EC5161-3E44-44EC-97FF-90DC93713ADF';

void main(List<String> args) {
  final appId = _arg(args, 'app-id');
  if (appId == null || !_isGuid(appId)) {
    stderr.writeln('--app-id=<Azure AppId GUID> is required (Entra app registration → Application (client) ID).');
    exit(2);
  }
  final runtime = _arg(args, 'runtime'); // e.g. 1.7 — omit when self-contained
  final path = _arg(args, 'manifest') ??
      'build/windows/x64/runner/Release/AppxManifest.xml';

  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('No manifest at $path — run `dart run msix:build` first.');
    exit(1);
  }

  var xml = file.readAsStringSync();
  var changed = false;

  // 1. Namespace declaration + IgnorableNamespaces entry.
  if (!xml.contains('xmlns:com=')) {
    xml = xml.replaceFirst(
      RegExp(r'(<Package\s)'),
      '\$1xmlns:com="$_comNamespace"\n          ',
    );
    changed = true;
  }
  final ignorable = RegExp(r'IgnorableNamespaces="([^"]*)"').firstMatch(xml);
  if (ignorable != null && !ignorable.group(1)!.split(' ').contains('com')) {
    xml = xml.replaceFirst(
      ignorable.group(0)!,
      'IgnorableNamespaces="${ignorable.group(1)} com"',
    );
    changed = true;
  }

  // 2. COM activator. The Executable/DisplayName must match the <Application>
  //    entry the msix package generated, so read them back instead of guessing.
  if (!xml.contains('windows.comServer')) {
    final app = RegExp(r'<Application\s+Id="([^"]+)"\s+Executable="([^"]+)"')
        .firstMatch(xml);
    if (app == null) {
      stderr.writeln('Could not locate the <Application> element.');
      exit(1);
    }
    final executable = app.group(2)!;
    // Two separate activators, and both are required:
    //   * the push one lets WNS start the app to *deliver* a notification
    //   * the toast one lets the shell start it when the user *clicks* one
    // With only the first, a click launches the app and the payload is
    // dropped — the notification's launch argument never reaches any handler.
    final extension = '''
        <Extensions>
          <com:Extension Category="windows.comServer">
            <com:ComServer>
              <com:ExeServer Executable="$executable" DisplayName="hinata"
                Arguments="----WindowsAppRuntimePushServer:">
                <com:Class Id="$appId" DisplayName="Hinata Push" />
              </com:ExeServer>
            </com:ComServer>
          </com:Extension>
          <desktop:Extension Category="windows.toastNotificationActivation">
            <desktop:ToastNotificationActivation
              ToastActivatorCLSID="$_toastActivatorClsid" />
          </desktop:Extension>
          <com:Extension Category="windows.comServer">
            <com:ComServer>
              <com:ExeServer Executable="$executable" DisplayName="hinata"
                Arguments="----AppNotificationActivated:">
                <com:Class Id="$_toastActivatorClsid"
                  DisplayName="Hinata Notifications" />
              </com:ExeServer>
            </com:ComServer>
          </com:Extension>
        </Extensions>
''';
    xml = xml.replaceFirst('</Application>', '$extension          </Application>');
    changed = true;
  }

  // 3. Framework dependency (skipped for self-contained deployments).
  //
  // Identity read from the framework package the SDK ships
  // (Microsoft.WindowsAppSDK.Runtime → tools/MSIX/win10-x64/…msix):
  //   Name      Microsoft.WindowsAppRuntime.2
  //   Publisher CN=Microsoft Corporation, O=Microsoft Corporation, …
  // MinVersion must be a real version — "0.0.0.0" is rejected by the Store.
  if (runtime != null && !xml.contains('Microsoft.WindowsAppRuntime')) {
    final minVersion = _arg(args, 'runtime-version') ?? '2.3.1.0';
    const publisher =
        'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US';
    // Appended, not prepended: the schema fixes the order inside
    // <Dependencies> as TargetDeviceFamily first, PackageDependency after.
    // Prepending fails packing with 0x80080204 ("package manifest is not
    // valid").
    xml = xml.replaceFirst(
      '</Dependencies>',
      '  <PackageDependency Name="Microsoft.WindowsAppRuntime.$runtime" '
          'MinVersion="$minVersion" Publisher="$publisher" />\n'
          '    </Dependencies>',
    );
    changed = true;
  }

  if (!changed) {
    stdout.writeln('AppxManifest.xml already patched — nothing to do.');
    return;
  }
  file.writeAsStringSync(xml);
  stdout.writeln('AppxManifest.xml patched:');
  stdout.writeln('  push activator class id: $appId');
  stdout.writeln('  toast activator CLSID  : $_toastActivatorClsid');
  if (runtime != null) stdout.writeln('  framework dependency   : Microsoft.WindowsAppRuntime.$runtime');
}

String? _arg(List<String> args, String name) {
  final prefix = '--$name=';
  for (final a in args) {
    if (a.startsWith(prefix)) return a.substring(prefix.length);
  }
  return null;
}

bool _isGuid(String s) => RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(s);

import 'dart:async';

import 'package:puro_sidekick_plugin/puro_sidekick_plugin.dart';
import 'package:sidekick_core/sidekick_core.dart';
import 'package:sidekick_vault/sidekick_vault.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/bootstrap/bootstrap_command.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/build_commands/build_command.dart';
import 'package:vekolo_sidekick/src/commands/clean_command.dart';

final SidekickVault vault = SidekickVault(
  location: SidekickContext.projectRoot.directory('vault'),
  environmentVariableName: 'VEKOLO_VAULT_PASSPHRASE',
);

Future<void> runVekolo(List<String> args) async {
  final runner = initializeSidekick(
    mainProjectPath: '.',
    flutterSdkPath: flutterSdkSymlink(),
  );
  addSdkInitializer(initializePuro);

  runner
    ..addCommand(FlutterCommand())
    ..addCommand(DartCommand())
    ..addCommand(DepsCommand())
    ..addCommand(CleanCommand())
    ..addCommand(DartAnalyzeCommand())
    ..addCommand(FormatCommand())
    ..addCommand(SidekickCommand())
    ..addCommand(PuroCommand())
    ..addCommand(BootstrapCommand())
    ..addCommand(BuildCommand());

  try {
    return await runner.run(args);
  } on UsageException catch (e) {
    print(e);
    exit(64); // usage error
  }
}

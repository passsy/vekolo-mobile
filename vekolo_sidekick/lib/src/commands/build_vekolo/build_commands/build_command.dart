import 'package:sidekick_core/sidekick_core.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/build_commands/build_android_command.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/build_commands/build_ios_command.dart';

/// Parent command for all build commands
class BuildCommand extends Command {
  @override
  final String name = 'build';

  @override
  final String description = 'Build the vekolo app for different platforms and distributions';

  BuildCommand() {
    addSubcommand(BuildAndroidCommand());
    addSubcommand(BuildIosCommand());
  }
}

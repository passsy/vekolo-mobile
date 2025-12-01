import 'package:sidekick_core/sidekick_core.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/bootstrap/bootstrap_android.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/bootstrap/bootstrap_ios.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/bootstrap/camel_case_name_matcher.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/distribute/android_build_spec.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/distribute/distribution.dart';
import 'package:vekolo_sidekick/src/commands/build_vekolo/distribute/ios_build_spec.dart';

class BootstrapCommand extends Command {
  @override
  final name = 'bootstrap';

  @override
  final description = 'Bootstrap the project for development or publishing';

  @override
  String get invocation => super.invocation.replaceFirst(
    '[arguments]',
    "[<${_buildConfigurations().joinToString(separator: '|')}>]",
  );

  BootstrapCommand() {
    argParser.addFlag(
      'list',
      help: 'Lists all available configurations',
      negatable: false,
    );
  }

  @override
  Future<void> run() async {
    final listConfigurations = argResults!['list'] as bool;
    if (listConfigurations == true) {
      _printConfigurations();
      return;
    }

    final input = argResults!.rest.firstOrNull;
    if (input == null || input.isBlank) {
      print(
        red(
          'Error: No configuration specified. You have to specify a distribution:',
        ),
      );
      exitCode = 1;
      _printConfigurations();
      return;
    }

    final configurations = _buildConfigurations();
    final config = CamelCaseNameMatcher.find(input, configurations);

    final parts = config
        .split(RegExp('(?=[A-Z])'))
        .map((it) => it.toLowerCase())
        .toList();
    final os = OperatingSystem.values.firstOrNullWhere(
      (it) => it.name == parts.last,
    );
    bool foundCombination = false;
    if (os == OperatingSystem.android || os == null) {
      final dist = AndroidDistribution.values.firstOrNullWhere(
        (it) => it.name == parts.first,
      );
      if (dist != null) {
        foundCombination = true;
        bootstrap(dist, os: OperatingSystem.android);
      }
    }
    if (os == OperatingSystem.ios || os == null) {
      final dist = IosDistribution.values.firstOrNullWhere(
        (it) => it.name == parts.first,
      );
      if (dist != null) {
        foundCombination = true;
        bootstrap(dist, os: OperatingSystem.ios);
      }
    }
    if (!foundCombination) {
      print(red('Error: Unknown configuration "$input". Try one of:'));
      exitCode = 1;
      _printConfigurations();
      return;
    }

    print(green('Bootstrapping App for distribution $config finished!'));
  }

  void _printConfigurations() {
    print(
      'IosDistributions: ${IosDistribution.values.joinToString(transform: (it) => it.name)}',
    );
    print(
      'AndroidDistributions: ${AndroidDistribution.values.joinToString(transform: (it) => it.name)}',
    );
    print(
      'Platforms (optional): ${OperatingSystem.values.joinToString(transform: (it) => it.name)}',
    );
    print('');
    print('Available configurations:');
    for (final combination in _buildConfigurations()) {
      print('  $combination');
    }
  }

  List<String> _buildConfigurations() {
    final List<String> distributions = [
      ...IosDistribution.values.map((it) => it.name),
      ...AndroidDistribution.values.map((it) => it.name),
    ].sorted();

    final List<String> combinations = [
      ...IosDistribution.values.map(
        (it) => "${it.name}${OperatingSystem.ios.name.capitalize()}",
      ),
      ...AndroidDistribution.values.map(
        (it) => "${it.name}${OperatingSystem.android.name.capitalize()}",
      ),
    ].sorted();

    final all = distributions + combinations;
    return all.distinct().sorted();
  }
}

/// Configures the project for a specific [distribution] for all or a specific [os].
void bootstrap(Enum distribution, {OperatingSystem? os}) {
  final osName = os == null ? ' ' : '(${os.name}) ';
  print('Bootstrapping $osName App for distribution ${distribution.name}...');
  if ((os == null || os == OperatingSystem.ios) &&
      distribution is IosDistribution) {
    if (os == null) print(grey('iOS:'));

    final entries = availableIosDistributionSpecs.map(
      (spec) => MapEntry(spec.distribution, spec),
    );
    final specs = Map.fromEntries(entries);
    final spec = specs.getOrElse(distribution, () {
      throw 'Unknown iOS distribution: $distribution, check ios_build_spec.dart for available distributions';
    });

    bootstrapIos(spec);
    print('');
  }
  if ((os == null || os == OperatingSystem.android) &&
      distribution is AndroidDistribution) {
    if (os == null) print(grey('Android:'));

    final entries = availableAndroidDistributionSpecs.map(
      (spec) => MapEntry(spec.distribution, spec),
    );
    final specs = Map.fromEntries(entries);
    final spec = specs.getOrElse(distribution, () {
      throw 'Unknown Android distribution: $distribution, check android_build_spec.dart for available distributions';
    });

    bootstrapAndroid(spec);
    print('');
  }
}

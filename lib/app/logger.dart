import 'package:chirp/chirp.dart';
import 'package:vekolo/api/pretty_log_interceptor.dart';

void initializeLogger() {
  Chirp.root = ChirpLogger()..addConsoleWriter(formatter: RainbowMessageFormatter());

  PrettyLogInterceptor.logger.addWriter(
    DeveloperLogConsoleWriter(
      formatter: SimpleConsoleMessageFormatter(
        showLoggerName: false,
        showInstance: false,
        showMethod: false,
        showLevel: false,
      ),
    ),
  );

}
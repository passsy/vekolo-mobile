import 'package:chirp/chirp.dart';

void initializeLogger() {
  Chirp.root = ChirpLogger()
    ..addConsoleWriter(formatter: RainbowMessageFormatter(options: RainbowFormatOptions(showLogLevel: false)));
}

import 'package:chirp/chirp.dart';

void initializeLogger() {
  // Chirp.root = ChirpLogger(writers: [ConsoleAppender(formatter: RainbowMessageFormatter(metaWidth: 100))]);
  Chirp.root = ChirpLogger();
}

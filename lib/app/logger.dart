import 'package:chirp/chirp.dart';

void initializeLogger() {
  Chirp.root = ChirpLogger(writers: [ConsoleChirpMessageWriter(formatter: RainbowMessageFormatter())]);
}

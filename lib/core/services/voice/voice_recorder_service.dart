import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

class VoiceRecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  Future<bool> hasPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> start() async {
    final granted = await hasPermission();
    if (!granted) {
      throw Exception("Microphone permission denied");
    }

    final dir = await getTemporaryDirectory();
    final path =
        "${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a";

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );
  }

  Future<String?> stop() async {
    return _recorder.stop();
  }

  Future<void> cancel() async {
    await _recorder.cancel();
  }

  void dispose() {
    _recorder.dispose();
  }
}
import 'package:flutter/services.dart';

class NativeAudioService {
  static const MethodChannel _channel = MethodChannel('audio_splitter/native');

  /// Gets audio duration in seconds via native AVFoundation.
  static Future<double> getAudioDuration(String filePath) async {
    try {
      final double duration = await _channel.invokeMethod('getAudioDuration', {
        'filePath': filePath,
      });
      return duration;
    } on PlatformException catch (e) {
      throw Exception('Failed to get audio duration: ${e.message}');
    }
  }

  /// Splits an audio segment from [startTime] for [duration] seconds.
  static Future<bool> splitAudioSegment({
    required String inputPath,
    required String outputPath,
    required double startTime,
    required double duration,
  }) async {
    try {
      final bool success = await _channel.invokeMethod('splitAudioSegment', {
        'inputPath': inputPath,
        'outputPath': outputPath,
        'startTime': startTime,
        'duration': duration,
      });
      return success;
    } on PlatformException catch (e) {
      throw Exception('Failed to split audio segment: ${e.message}');
    }
  }
}

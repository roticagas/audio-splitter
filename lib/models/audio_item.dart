import 'dart:io';

enum ProcessStatus { idle, processing, completed, error }

class AudioItem {
  final String path;
  final String name;
  final int sizeBytes;
  double durationSeconds;
  ProcessStatus status;
  String? errorMessage;
  int splitCount;

  AudioItem({
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.durationSeconds = 0.0,
    this.status = ProcessStatus.idle,
    this.errorMessage,
    this.splitCount = 0,
  });

  String get formattedDuration {
    if (durationSeconds <= 0) return '--:--';
    final duration = Duration(seconds: durationSeconds.round());
    final minutes = duration.inMinutes;
    final remainingSeconds = duration.inSeconds.remainder(60);
    final hours = duration.inHours;
    if (hours > 0) {
      return '$hours:${minutes.remainder(60).toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory AudioItem.fromFile(File file) {
    final name = file.path.split(Platform.pathSeparator).last;
    final size = file.lengthSync();
    return AudioItem(
      path: file.path,
      name: name,
      sizeBytes: size,
    );
  }
}

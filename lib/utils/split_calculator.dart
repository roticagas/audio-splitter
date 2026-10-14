import 'dart:math';
import '../models/split_config.dart';

class SplitSegment {
  final int index;
  final double originalStart;
  final double originalEnd;
  final double actualStart;
  final double actualEnd;
  final double actualDuration;
  final double effectiveOverlap;

  SplitSegment({
    required this.index,
    required this.originalStart,
    required this.originalEnd,
    required this.actualStart,
    required this.actualEnd,
    required this.actualDuration,
    required this.effectiveOverlap,
  });
}

class SplitCalculator {
  /// Format seconds into a filename-safe timestamp.
  /// Example: 0 -> "00m00s", 65 -> "01m05s", 3661 -> "01h01m01s"
  static String formatTimeForFilename(double seconds) {
    if (seconds < 0) seconds = 0;
    final int totalSec = seconds.round();
    final int h = totalSec ~/ 3600;
    final int m = (totalSec % 3600) ~/ 60;
    final int s = totalSec % 60;

    final String mm = m.toString().padLeft(2, '0');
    final String ss = s.toString().padLeft(2, '0');

    if (h > 0) {
      final String hh = h.toString().padLeft(2, '0');
      return '${hh}h${mm}m${ss}s';
    }
    return '${mm}m${ss}s';
  }

  /// Calculates segments using Option B (Head Overlap).
  ///
  /// Zero-Restructure Approach:
  /// 1. Original calculation divides the audio into standard (start, end) ranges.
  /// 2. Post-Calculation Modifier (Option B):
  ///    - actualStart = (index == 0) ? 0 : max(0, start - effectiveOverlap)
  ///    - actualEnd = end
  ///    - actualDuration = actualEnd - actualStart
  ///    Guardrail: effectiveOverlap = min(overlapSeconds, chunkDuration * 0.5)
  static List<SplitSegment> calculateSegments({
    required double totalDuration,
    required SplitConfig config,
  }) {
    if (totalDuration <= 0) return [];

    final List<({double start, double end})> rawChunks = [];

    if (config.mode == SplitMode.equalParts) {
      final int parts = config.partsCount <= 0 ? 1 : config.partsCount;
      final double segmentLen = totalDuration / parts;

      for (int i = 0; i < parts; i++) {
        final double start = i * segmentLen;
        final double end = (i == parts - 1) ? totalDuration : (start + segmentLen);
        rawChunks.add((start: start, end: end));
      }
    } else {
      // fixedDuration mode
      final double chunkSec = config.durationMinutes * 60.0;
      if (chunkSec <= 0) return [];

      final int totalChunks = (totalDuration / chunkSec).ceil();
      for (int i = 0; i < totalChunks; i++) {
        final double start = i * chunkSec;
        double end = start + chunkSec;
        if (end > totalDuration) {
          end = totalDuration;
        }
        if (start >= totalDuration) break;
        rawChunks.add((start: start, end: end));
      }
    }

    final List<SplitSegment> segments = [];
    final double requestedOverlap = max(0.0, config.overlapSeconds);

    for (int i = 0; i < rawChunks.length; i++) {
      final start = rawChunks[i].start;
      final end = rawChunks[i].end;
      final double chunkDuration = end - start;

      // 3.2 Guardrail: ป้องกันกรณีไฟล์สั้นมากแต่ตั้ง Overlap ยาวเกินความยาวของท่อนเสียง
      final double effectiveOverlap = min(requestedOverlap, chunkDuration * 0.5);

      // Option B: Head Overlap
      // ยึดจุดจบ (end) ไว้ที่เดิม แล้วดึงเวลาเริ่ม (start) ของไฟล์ที่ 2 เป็นต้นไปถอยหลังกลับมาตามค่า overlap
      final double actualStart = (i == 0) ? 0.0 : max(0.0, start - effectiveOverlap);
      final double actualEnd = end;
      final double actualDuration = actualEnd - actualStart;

      segments.add(
        SplitSegment(
          index: i,
          originalStart: start,
          originalEnd: end,
          actualStart: actualStart,
          actualEnd: actualEnd,
          actualDuration: actualDuration,
          effectiveOverlap: (i == 0) ? 0.0 : effectiveOverlap,
        ),
      );
    }

    return segments;
  }

  /// Generates the output filename with timestamp range.
  /// Format:
  /// Equal Parts: {rawName}_part_{index + 1}_of_{totalParts}_{startMMSS}-{endMMSS}.m4a
  /// Fixed Duration: {rawName}_part_{index + 1}_{startMMSS}-{endMMSS}.m4a
  static String generateOutputFilename({
    required String rawName,
    required int index,
    required int totalCount,
    required SplitMode mode,
    required double actualStart,
    required double actualEnd,
  }) {
    final startLabel = formatTimeForFilename(actualStart);
    final endLabel = formatTimeForFilename(actualEnd);
    final timeRange = '${startLabel}-${endLabel}';

    if (mode == SplitMode.equalParts) {
      return '${rawName}_part_${index + 1}_of_${totalCount}_$timeRange.m4a';
    } else {
      return '${rawName}_part_${index + 1}_$timeRange.m4a';
    }
  }
}

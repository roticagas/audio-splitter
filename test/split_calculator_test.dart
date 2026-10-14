import 'package:flutter_test/flutter_test.dart';
import 'package:audio_splitter/models/split_config.dart';
import 'package:audio_splitter/utils/split_calculator.dart';

void main() {
  group('SplitCalculator - Timestamp Formatting', () {
    test('formats seconds to MMmSSs', () {
      expect(SplitCalculator.formatTimeForFilename(0), '00m00s');
      expect(SplitCalculator.formatTimeForFilename(5), '00m05s');
      expect(SplitCalculator.formatTimeForFilename(65), '01m05s');
      expect(SplitCalculator.formatTimeForFilename(599), '09m59s');
      expect(SplitCalculator.formatTimeForFilename(600), '10m00s');
    });

    test('formats hours to HHhMMmSSs', () {
      expect(SplitCalculator.formatTimeForFilename(3600), '01h00m00s');
      expect(SplitCalculator.formatTimeForFilename(3665), '01h01m05s');
      expect(SplitCalculator.formatTimeForFilename(7325), '02h02m05s');
    });
  });

  group('SplitCalculator - Equal Parts Mode (Option B Head Overlap)', () {
    test('overlap = 0 produces exact non-overlapping segments', () {
      final config = SplitConfig(
        mode: SplitMode.equalParts,
        partsCount: 3,
        overlapSeconds: 0,
      );

      final segments = SplitCalculator.calculateSegments(
        totalDuration: 300, // 5 minutes (100s each)
        config: config,
      );

      expect(segments.length, 3);

      // Part 1: 0 - 100
      expect(segments[0].actualStart, 0);
      expect(segments[0].actualEnd, 100);
      expect(segments[0].actualDuration, 100);

      // Part 2: 100 - 200
      expect(segments[1].actualStart, 100);
      expect(segments[1].actualEnd, 200);
      expect(segments[1].actualDuration, 100);

      // Part 3: 200 - 300
      expect(segments[2].actualStart, 200);
      expect(segments[2].actualEnd, 300);
      expect(segments[2].actualDuration, 100);
    });

    test('overlap = 10 pulls back start for index >= 1 and keeps end', () {
      final config = SplitConfig(
        mode: SplitMode.equalParts,
        partsCount: 3,
        overlapSeconds: 10,
      );

      final segments = SplitCalculator.calculateSegments(
        totalDuration: 300, // 100s each
        config: config,
      );

      expect(segments.length, 3);

      // Part 1: 0 - 100 (no overlap for first chunk)
      expect(segments[0].actualStart, 0);
      expect(segments[0].actualEnd, 100);
      expect(segments[0].actualDuration, 100);

      // Part 2: 90 - 200 (starts 10s earlier)
      expect(segments[1].actualStart, 90);
      expect(segments[1].actualEnd, 200);
      expect(segments[1].actualDuration, 110);
      expect(segments[1].effectiveOverlap, 10);

      // Part 3: 190 - 300 (starts 10s earlier)
      expect(segments[2].actualStart, 190);
      expect(segments[2].actualEnd, 300);
      expect(segments[2].actualDuration, 110);
      expect(segments[2].effectiveOverlap, 10);
    });
  });

  group('SplitCalculator - Fixed Duration Mode (Option B Head Overlap)', () {
    test('overlap = 5 with 1-minute chunks', () {
      final config = SplitConfig(
        mode: SplitMode.fixedDuration,
        durationMinutes: 1.0, // 60s
        overlapSeconds: 5,
      );

      final segments = SplitCalculator.calculateSegments(
        totalDuration: 150, // 60s, 60s, 30s
        config: config,
      );

      expect(segments.length, 3);

      // Part 1: 0 - 60
      expect(segments[0].actualStart, 0);
      expect(segments[0].actualEnd, 60);
      expect(segments[0].actualDuration, 60);

      // Part 2: 55 - 120 (starts 5s earlier)
      expect(segments[1].actualStart, 55);
      expect(segments[1].actualEnd, 120);
      expect(segments[1].actualDuration, 65);

      // Part 3: 115 - 150 (starts 5s earlier)
      expect(segments[2].actualStart, 115);
      expect(segments[2].actualEnd, 150);
      expect(segments[2].actualDuration, 35);
    });
  });

  group('SplitCalculator - Guardrail', () {
    test('limits overlap to 50% of chunk duration if chunk is very small', () {
      final config = SplitConfig(
        mode: SplitMode.equalParts,
        partsCount: 2,
        overlapSeconds: 20, // requested 20s
      );

      final segments = SplitCalculator.calculateSegments(
        totalDuration: 20, // 10s per chunk -> max overlap is 10 * 0.5 = 5s
        config: config,
      );

      expect(segments.length, 2);

      // Part 1: 0 - 10
      expect(segments[0].actualStart, 0);
      expect(segments[0].actualEnd, 10);

      // Part 2: start should be 10 - 5 = 5 (effective overlap capped at 5)
      expect(segments[1].actualStart, 5);
      expect(segments[1].actualEnd, 20);
      expect(segments[1].effectiveOverlap, 5);
    });
  });

  group('SplitCalculator - Output Filename Generation', () {
    test('equal parts filename format includes timestamp range', () {
      final filename = SplitCalculator.generateOutputFilename(
        rawName: 'podcast_episode_1',
        index: 0,
        totalCount: 3,
        mode: SplitMode.equalParts,
        actualStart: 0,
        actualEnd: 300,
      );
      expect(filename, 'podcast_episode_1_part_1_of_3_00m00s-05m00s.m4a');
    });

    test('fixed duration filename format includes timestamp range', () {
      final filename = SplitCalculator.generateOutputFilename(
        rawName: 'lecture',
        index: 1,
        totalCount: 4,
        mode: SplitMode.fixedDuration,
        actualStart: 295, // 4m 55s
        actualEnd: 600,   // 10m 00s
      );
      expect(filename, 'lecture_part_2_04m55s-10m00s.m4a');
    });
  });
}

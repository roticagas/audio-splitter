enum SplitMode {
  equalParts,
  fixedDuration,
}

class SplitConfig {
  SplitMode mode;
  int partsCount;
  double durationMinutes;
  double overlapSeconds;
  String? customOutputFolder;

  SplitConfig({
    this.mode = SplitMode.equalParts,
    this.partsCount = 3,
    this.durationMinutes = 5.0,
    this.overlapSeconds = 0.0,
    this.customOutputFolder,
  });
}


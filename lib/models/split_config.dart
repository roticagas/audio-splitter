enum SplitMode {
  equalParts,
  fixedDuration,
}

class SplitConfig {
  SplitMode mode;
  int partsCount;
  double durationMinutes;
  String? customOutputFolder;

  SplitConfig({
    this.mode = SplitMode.equalParts,
    this.partsCount = 3,
    this.durationMinutes = 5.0,
    this.customOutputFolder,
  });
}

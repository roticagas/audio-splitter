import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;

import '../models/audio_item.dart';
import '../models/split_config.dart';
import '../services/native_audio_service.dart';
import '../utils/split_calculator.dart';


class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final List<AudioItem> _audioFiles = [];
  final SplitConfig _config = SplitConfig();
  bool _isDragging = false;
  bool _isProcessing = false;
  String _currentStepMessage = '';
  double _currentProgress = 0.0;

  @override
  void initState() {
    super.initState();
  }

  void _addFiles(List<String> paths) async {
    for (final path in paths) {
      if (path.toLowerCase().endsWith('.m4a')) {
        final file = File(path);
        if (file.existsSync() && !_audioFiles.any((item) => item.path == path)) {
          final item = AudioItem.fromFile(file);
          setState(() {
            _audioFiles.add(item);
          });
          // Load duration asynchronously
          try {
            final duration = await NativeAudioService.getAudioDuration(path);
            setState(() {
              item.durationSeconds = duration;
            });
          } catch (e) {
            debugPrint('Error loading duration for $path: $e');
          }
        }
      }
    }
  }

  void _pickFiles() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m4a'],
      allowMultiple: true,
    );

    if (result != null && result.paths.isNotEmpty) {
      _addFiles(result.paths.whereType<String>().toList());
    }
  }

  void _pickOutputFolder() async {
    final selectedDirectory = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select Output Folder',
    );
    if (selectedDirectory != null) {
      setState(() {
        _config.customOutputFolder = selectedDirectory;
      });
    }
  }

  void _removeFile(int index) {
    if (_isProcessing) return;
    setState(() {
      _audioFiles.removeAt(index);
    });
  }

  void _clearFiles() {
    if (_isProcessing) return;
    setState(() {
      _audioFiles.clear();
    });
  }

  Future<void> _startSplitting() async {
    if (_audioFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one .m4a file'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _currentProgress = 0.0;
      _currentStepMessage = 'Preparing to split files...';
    });

    int totalTasks = 0;
    // Calculate total segments across all files
    for (var item in _audioFiles) {
      if (item.durationSeconds <= 0) {
        try {
          item.durationSeconds = await NativeAudioService.getAudioDuration(item.path);
        } catch (_) {}
      }

      final segments = SplitCalculator.calculateSegments(
        totalDuration: item.durationSeconds,
        config: _config,
      );
      totalTasks += segments.isNotEmpty ? segments.length : 1;
    }

    if (totalTasks == 0) totalTasks = 1;
    int completedTasks = 0;

    for (int fileIdx = 0; fileIdx < _audioFiles.length; fileIdx++) {
      final item = _audioFiles[fileIdx];
      setState(() {
        item.status = ProcessStatus.processing;
        item.errorMessage = null;
      });

      final fileDir = p.dirname(item.path);
      final rawName = p.basenameWithoutExtension(item.path);
      final targetFolder = _config.customOutputFolder ?? fileDir;

      try {
        Directory(targetFolder).createSync(recursive: true);
        final double totalDur = item.durationSeconds;
        final segments = SplitCalculator.calculateSegments(
          totalDuration: totalDur,
          config: _config,
        );

        int producedCount = 0;

        for (final segment in segments) {
          final String outName = SplitCalculator.generateOutputFilename(
            rawName: rawName,
            index: segment.index,
            totalCount: segments.length,
            mode: _config.mode,
            actualStart: segment.actualStart,
            actualEnd: segment.actualEnd,
          );
          final String outPath = p.join(targetFolder, outName);

          setState(() {
            _currentStepMessage = 'Splitting [${item.name}] part ${segment.index + 1}/${segments.length}...';
          });

          await NativeAudioService.splitAudioSegment(
            inputPath: item.path,
            outputPath: outPath,
            startTime: segment.actualStart,
            duration: segment.actualDuration,
          );

          completedTasks++;
          producedCount++;
          setState(() {
            _currentProgress = completedTasks / totalTasks;
          });
        }


        setState(() {
          item.status = ProcessStatus.completed;
          item.splitCount = producedCount;
        });
      } catch (e) {
        setState(() {
          item.status = ProcessStatus.error;
          item.errorMessage = e.toString();
        });
      }
    }

    setState(() {
      _isProcessing = false;
      _currentProgress = 1.0;
      _currentStepMessage = 'All files split successfully!';
    });

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF10B981)),
              SizedBox(width: 10),
              Text('Completed', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Text(
            'Audio files split successfully.\nSaved to: ${_config.customOutputFolder ?? "Original file folder"}',
            style: const TextStyle(color: Color(0xFF94A3B8)),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Row(
        children: [
          // Sidebar Config Panel
          Container(
            width: 360,
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              border: Border(
                right: BorderSide(color: Color(0xFF334155), width: 1),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Brand
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.audiotrack_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AudioSplitter',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'macOS M4A Edition',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Split Settings',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Mode Selector Segmented Toggle
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    if (_isProcessing) return;
                                    setState(() {
                                      _config.mode = SplitMode.equalParts;
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: _config.mode == SplitMode.equalParts
                                          ? const Color(0xFF6366F1)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      'Equal Parts',
                                      style: TextStyle(
                                        color: _config.mode == SplitMode.equalParts
                                            ? Colors.white
                                            : const Color(0xFF94A3B8),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    if (_isProcessing) return;
                                    setState(() {
                                      _config.mode = SplitMode.fixedDuration;
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: _config.mode == SplitMode.fixedDuration
                                          ? const Color(0xFF6366F1)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      'By Duration',
                                      style: TextStyle(
                                        color: _config.mode == SplitMode.fixedDuration
                                            ? Colors.white
                                            : const Color(0xFF94A3B8),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Config Details
                        if (_config.mode == SplitMode.equalParts) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Number of parts:',
                                style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF334155),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${_config.partsCount} parts',
                                  style: const TextStyle(
                                    color: Color(0xFF818CF8),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: const Color(0xFF6366F1),
                              inactiveTrackColor: const Color(0xFF334155),
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              value: _config.partsCount.toDouble(),
                              min: 2,
                              max: 30,
                              divisions: 28,
                              onChanged: _isProcessing
                                  ? null
                                  : (v) {
                                      setState(() {
                                        _config.partsCount = v.round();
                                      });
                                    },
                            ),
                          ),
                          const Text(
                            'Audio will be split into equal duration parts automatically',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                          ),
                        ] else ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Part duration (minutes):',
                                style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF334155),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${_config.durationMinutes.toStringAsFixed(1)} min',
                                  style: const TextStyle(
                                    color: Color(0xFF818CF8),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: const Color(0xFF6366F1),
                              inactiveTrackColor: const Color(0xFF334155),
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              value: _config.durationMinutes,
                              min: 0.5,
                              max: 60.0,
                              divisions: 119,
                              onChanged: _isProcessing
                                  ? null
                                  : (v) {
                                      setState(() {
                                        _config.durationMinutes = (v * 2).round() / 2;
                                      });
                                    },
                            ),
                          ),
                          const Text(
                            'Files will be split by duration; the last part keeps remaining time',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // Overlap (Option B: Head Overlap)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Audio Overlap:',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF334155),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _config.overlapSeconds == 0
                                    ? 'Off (0s)'
                                    : '${_config.overlapSeconds.toInt()}s',
                                style: TextStyle(
                                  color: _config.overlapSeconds > 0
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFF94A3B8),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Overlap Segmented Control (0s, 5s, 10s, 15s)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              for (final sec in [0.0, 5.0, 10.0, 15.0])
                                Expanded(
                                  child: GestureDetector(
                                    onTap: _isProcessing
                                        ? null
                                        : () {
                                            setState(() {
                                              _config.overlapSeconds = sec;
                                            });
                                          },
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: _config.overlapSeconds == sec
                                            ? const Color(0xFF6366F1)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        sec == 0 ? 'Off (0s)' : '${sec.toInt()}s',
                                        style: TextStyle(
                                          color: _config.overlapSeconds == sec
                                              ? Colors.white
                                              : const Color(0xFF94A3B8),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Option B (Head Overlap): Pulls back start time of subsequent parts to avoid audio cutoff',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                        ),

                        const SizedBox(height: 20),

                        const Text(
                          'Export Directory',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),

                        InkWell(
                          onTap: _isProcessing ? null : _pickOutputFolder,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.folder_open_rounded, color: Color(0xFF818CF8), size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _config.customOutputFolder ?? 'Same as input folder',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _config.customOutputFolder != null
                                          ? Colors.white
                                          : const Color(0xFF94A3B8),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Start Action Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _startSplitting,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      disabledBackgroundColor: const Color(0xFF334155),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    child: _isProcessing
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text('Processing...', style: TextStyle(color: Colors.white)),
                            ],
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.content_cut_rounded, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Start Splitting',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),


          // Main File Area
          Expanded(
            child: Container(
              color: const Color(0xFF0F172A),
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Bar Info
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Audio Files (.m4a)',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Import files to split according to settings (${_audioFiles.length} files)',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _isProcessing ? null : _pickFiles,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add Files...'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xFF475569)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                          ),
                          if (_audioFiles.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            IconButton(
                              onPressed: _isProcessing ? null : _clearFiles,
                              icon: const Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444)),
                              tooltip: 'Clear All',
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Drag and Drop Container / File list
                  Expanded(
                    child: DropTarget(
                      onDragEntered: (details) {
                        setState(() => _isDragging = true);
                      },
                      onDragExited: (details) {
                        setState(() => _isDragging = false);
                      },
                      onDragDone: (details) {
                        setState(() => _isDragging = false);
                        final paths = details.files.map((f) => f.path).toList();
                        _addFiles(paths);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: _isDragging
                              ? const Color(0xFF6366F1).withOpacity(0.1)
                              : const Color(0xFF1E293B).withOpacity(0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _isDragging
                                ? const Color(0xFF6366F1)
                                : const Color(0xFF334155),
                            width: _isDragging ? 2 : 1,
                          ),
                        ),
                        child: _audioFiles.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF334155).withOpacity(0.5),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.cloud_upload_rounded,
                                        size: 48,
                                        color: Color(0xFF818CF8),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Drop .m4a files here',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'or click "Add Files..." above to browse',
                                      style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                                    ),
                                    const SizedBox(height: 14),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F172A),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFF334155)),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.label_outline_rounded, size: 14, color: Color(0xFF818CF8)),
                                          SizedBox(width: 8),
                                          Text(
                                            'Filename Preview will be shown directly inside each audio card',
                                            style: TextStyle(
                                              color: Color(0xFF94A3B8),
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: _audioFiles.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final item = _audioFiles[index];
                                  return Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F172A),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFF334155)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF334155),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: const Icon(
                                                Icons.audio_file_rounded,
                                                color: Color(0xFF818CF8),
                                                size: 24,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    item.name,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.w600,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Wrap(
                                                    spacing: 12,
                                                    runSpacing: 4,
                                                    crossAxisAlignment: WrapCrossAlignment.center,
                                                    children: [
                                                      Text(
                                                        'Size: ${item.formattedSize}',
                                                        style: const TextStyle(
                                                          color: Color(0xFF64748B),
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      Text(
                                                        'Duration: ${item.formattedDuration}',
                                                        style: const TextStyle(
                                                          color: Color(0xFF64748B),
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      if (item.durationSeconds > 0) ...[
                                                        Builder(
                                                          builder: (context) {
                                                            final segs = SplitCalculator.calculateSegments(
                                                              totalDuration: item.durationSeconds,
                                                              config: _config,
                                                            );
                                                            return Text(
                                                              'Est: ${segs.length} parts${_config.overlapSeconds > 0 ? " (overlap ${_config.overlapSeconds.toInt()}s)" : ""}',
                                                              style: const TextStyle(
                                                                color: Color(0xFF818CF8),
                                                                fontSize: 12,
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            // Status badge
                                            _buildStatusBadge(item),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              onPressed: _isProcessing ? null : () => _removeFile(index),
                                              icon: const Icon(
                                                Icons.close_rounded,
                                                color: Color(0xFF64748B),
                                                size: 18,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (item.durationSeconds > 0) ...[
                                          const SizedBox(height: 12),
                                          _buildCardFilenamePreview(item),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ),

                  // Bottom Progress Overlay / Status bar
                  if (_isProcessing || _currentProgress > 0) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _currentStepMessage,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                              ),
                              Text(
                                '${(_currentProgress * 100).toInt()}%',
                                style: const TextStyle(
                                  color: Color(0xFF818CF8),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _currentProgress,
                              backgroundColor: const Color(0xFF334155),
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(AudioItem item) {
    switch (item.status) {
      case ProcessStatus.idle:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF334155).withOpacity(0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'Ready',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
          ),
        );
      case ProcessStatus.processing:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF818CF8)),
              ),
              SizedBox(width: 6),
              Text(
                'Splitting...',
                style: TextStyle(color: Color(0xFF818CF8), fontSize: 11),
              ),
            ],
          ),
        );
      case ProcessStatus.completed:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Done (${item.splitCount} files)',
            style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w600),
          ),
        );
      case ProcessStatus.error:
        return Tooltip(
          message: item.errorMessage ?? 'Error splitting audio file',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Error',
              style: TextStyle(color: Color(0xFFEF4444), fontSize: 11),
            ),
          ),
        );
    }
  }

  Widget _buildCardFilenamePreview(AudioItem item) {
    final rawName = p.basenameWithoutExtension(item.path);
    final segments = SplitCalculator.calculateSegments(
      totalDuration: item.durationSeconds,
      config: _config,
    );

    if (segments.isEmpty) return const SizedBox.shrink();

    final previewSegments = segments.take(2).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155).withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.label_outline_rounded, size: 13, color: Color(0xFF818CF8)),
              const SizedBox(width: 6),
              const Text(
                'Filename Preview',
                style: TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'Total ${segments.length} parts',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final seg in previewSegments) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '#${seg.index + 1}',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      SplitCalculator.generateOutputFilename(
                        rawName: rawName,
                        index: seg.index,
                        totalCount: segments.length,
                        mode: _config.mode,
                        actualStart: seg.actualStart,
                        actualEnd: seg.actualEnd,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF818CF8),
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Range: ${SplitCalculator.formatTimeForFilename(seg.actualStart)} - ${SplitCalculator.formatTimeForFilename(seg.actualEnd)} (${seg.actualDuration.toStringAsFixed(1)}s)',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                  ),
                  if (seg.effectiveOverlap > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        'Overlap ${seg.effectiveOverlap.toInt()}s',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (segments.length > 2)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 2),
              child: Text(
                '... and ${segments.length - 2} more parts',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

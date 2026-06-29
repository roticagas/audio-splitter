import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;

import '../models/audio_item.dart';
import '../models/split_config.dart';
import '../services/native_audio_service.dart';

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
      dialogTitle: 'เลือกโฟลเดอร์สำหรับเซฟไฟล์ที่แบ่งแล้ว',
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
          content: Text('กรุณาเลือกไฟล์ .m4a อย่างน้อย 1 ไฟล์'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _currentProgress = 0.0;
      _currentStepMessage = 'กำลังเตรียมระบบเริ่มแบ่งไฟล์...';
    });

    int totalTasks = 0;
    // Calculate total segments across all files
    for (var item in _audioFiles) {
      if (item.durationSeconds <= 0) {
        try {
          item.durationSeconds = await NativeAudioService.getAudioDuration(item.path);
        } catch (_) {}
      }

      if (_config.mode == SplitMode.equalParts) {
        totalTasks += _config.partsCount;
      } else {
        final chunkSec = _config.durationMinutes * 60.0;
        if (chunkSec > 0 && item.durationSeconds > 0) {
          totalTasks += (item.durationSeconds / chunkSec).ceil();
        } else {
          totalTasks += 1;
        }
      }
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
        int producedCount = 0;

        if (_config.mode == SplitMode.equalParts) {
          final int parts = _config.partsCount;
          final double segmentLen = totalDur / parts;

          for (int i = 0; i < parts; i++) {
            final double start = i * segmentLen;
            final double dur = (i == parts - 1) ? (totalDur - start) : segmentLen;
            final String outName = '${rawName}_part_${i + 1}_of_$parts.m4a';
            final String outPath = p.join(targetFolder, outName);

            setState(() {
              _currentStepMessage = 'กำลังแบ่ง [${item.name}] ส่วนที่ ${i + 1}/$parts...';
            });

            await NativeAudioService.splitAudioSegment(
              inputPath: item.path,
              outputPath: outPath,
              startTime: start,
              duration: dur,
            );

            completedTasks++;
            producedCount++;
            setState(() {
              _currentProgress = completedTasks / totalTasks;
            });
          }
        } else {
          // Fixed duration mode
          final double chunkSec = _config.durationMinutes * 60.0;
          final int totalChunks = (totalDur / chunkSec).ceil();

          for (int i = 0; i < totalChunks; i++) {
            final double start = i * chunkSec;
            double dur = chunkSec;
            if (start + dur > totalDur) {
              dur = totalDur - start;
            }
            if (dur <= 0) break;

            final String outName = '${rawName}_part_${i + 1}.m4a';
            final String outPath = p.join(targetFolder, outName);

            setState(() {
              _currentStepMessage = 'กำลังแบ่ง [${item.name}] ส่วนที่ ${i + 1}/$totalChunks...';
            });

            await NativeAudioService.splitAudioSegment(
              inputPath: item.path,
              outputPath: outPath,
              startTime: start,
              duration: dur,
            );

            completedTasks++;
            producedCount++;
            setState(() {
              _currentProgress = completedTasks / totalTasks;
            });
          }
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
      _currentStepMessage = 'เสร็จสิ้นการแบ่งไฟล์ทั้งหมดแล้ว!';
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
              Text('ดำเนินการเรียบร้อย', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Text(
            'ทำการแบ่งไฟล์เสียงเรียบร้อยแล้ว\nบันทึกไว้ที่: ${_config.customOutputFolder ?? "โฟลเดอร์ดั้งเดิมของไฟล์"}',
            style: const TextStyle(color: Color(0xFF94A3B8)),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('ตกลง'),
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
            padding: const EdgeInsets.all(24),
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

                const SizedBox(height: 32),
                const Text(
                  'ตั้งค่าการแบ่งไฟล์ (Config)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),

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
                              'แบ่งกี่ส่วน',
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
                              'แบ่งตามเวลา',
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

                const SizedBox(height: 24),

                // Config Details
                if (_config.mode == SplitMode.equalParts) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'จำนวนส่วนที่ต้องการแบ่ง:',
                        style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF334155),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${_config.partsCount} ส่วน',
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
                    'ระบบจะแบ่งไฟล์ออกเป็นจำนวนส่วนเท่าๆ กันโดยอัตโนมัติ',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  ),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ความยาวส่วนละ (นาที):',
                        style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF334155),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${_config.durationMinutes.toStringAsFixed(1)} นาที',
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
                    'ไฟล์จะถูกแบ่งตามความยาวที่กำหนด และส่วนสุดท้ายจะเก็บเวลาที่เหลือทั้งหมด',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  ),
                ],

                const SizedBox(height: 32),
                const Text(
                  'สถานที่จัดเก็บ (Export Directory)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),

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
                            _config.customOutputFolder ?? 'ตามโฟลเดอร์เดิมของไฟล์ (Same as input)',
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

                const Spacer(),

                // Start Action Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
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
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text('กำลังประมวลผล...', style: TextStyle(color: Colors.white)),
                            ],
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.content_cut_rounded, color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'เริ่มแยกไฟล์เสียง',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'รายการไฟล์เสียง (.m4a)',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'นำเข้าไฟล์เพื่อเริ่มทำการแบ่งตามการตั้งค่า (${_audioFiles.length} ไฟล์)',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _isProcessing ? null : _pickFiles,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('เพิ่มไฟล์...'),
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
                              tooltip: 'ล้างรายการทั้งหมด',
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
                                      'ลากไฟล์ .m4a มาวางที่นี่',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'หรือคลิกปุ่ม "เพิ่มไฟล์..." ด้านบนเพื่อเลือกไฟล์',
                                      style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
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
                                    child: Row(
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
                                              Row(
                                                children: [
                                                  Text(
                                                    'ขนาด: ${item.formattedSize}',
                                                    style: const TextStyle(
                                                      color: Color(0xFF64748B),
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Text(
                                                    'ความยาว: ${item.formattedDuration}',
                                                    style: const TextStyle(
                                                      color: Color(0xFF64748B),
                                                      fontSize: 12,
                                                    ),
                                                  ),
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
            'พร้อมใช้งาน',
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
                'กำลังตัดไฟล์...',
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
            'เสร็จแล้ว (${item.splitCount} ไฟล์)',
            style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w600),
          ),
        );
      case ProcessStatus.error:
        return Tooltip(
          message: item.errorMessage ?? 'เกิดข้อผิดพลาดในการตัดแบ่งไฟล์',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'เกิดข้อผิดพลาด',
              style: TextStyle(color: Color(0xFFEF4444), fontSize: 11),
            ),
          ),
        );
    }
  }
}

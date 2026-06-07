import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LivoCutApp());
}

class LivoCutApp extends StatelessWidget {
  const LivoCutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LivoCut',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff0f766e),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff7f9fb),
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: Color(0xffdbe3ea)),
          ),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          },
        ),
      ),
      home: const RootGate(),
    );
  }
}

class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  final SettingsService _settingsService = SettingsService();
  AppSettings? _settings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _settingsService.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
      _loading = false;
    });
  }

  Future<void> _saveSettings(String importFolder, String exportFolder) async {
    await _settingsService.save(importFolder, exportFolder);
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = AppSettings(
        importFolder: importFolder,
        exportFolder: exportFolder,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final settings = _settings;
    final needsSetup = settings == null ||
        !Directory(settings.importFolder).existsSync() ||
        !Directory(settings.exportFolder).existsSync();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: needsSetup
          ? SetupScreen(
              key: const ValueKey<String>('setup'),
              initialSettings: settings,
              onSaved: _saveSettings,
            )
          : LibraryScreen(
              key: const ValueKey<String>('library'),
              settings: settings,
              onChangeFolders: () async {
                await Navigator.of(context).push<void>(
                  slideRoute(
                    SetupScreen(
                      initialSettings: settings,
                      onSaved: _saveSettings,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

PageRoute<T> slideRoute<T>(Widget child) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, _, _) => child,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.08, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

class AppSettings {
  const AppSettings({
    required this.importFolder,
    required this.exportFolder,
  });

  final String importFolder;
  final String exportFolder;
}

class SettingsService {
  static const String _importKey = 'import_folder';
  static const String _exportKey = 'export_folder';

  Future<AppSettings?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final importFolder = prefs.getString(_importKey);
    final exportFolder = prefs.getString(_exportKey);
    if (importFolder == null || exportFolder == null) {
      return null;
    }
    return AppSettings(importFolder: importFolder, exportFolder: exportFolder);
  }

  Future<void> save(String importFolder, String exportFolder) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_importKey, importFolder);
    await prefs.setString(_exportKey, exportFolder);
  }
}

class StoragePermissionService {
  Future<void> requestFolderAccess() async {
    if (!Platform.isAndroid) {
      return;
    }

    await _requestIfNeeded(Permission.videos);
    await _requestIfNeeded(Permission.storage);

    final manageStatus = await Permission.manageExternalStorage.status;
    if (!manageStatus.isGranted) {
      await Permission.manageExternalStorage.request();
    }
  }

  Future<void> _requestIfNeeded(Permission permission) async {
    final status = await permission.status;
    if (status.isDenied || status.isRestricted || status.isLimited) {
      await permission.request();
    }
  }
}

class SetupScreen extends StatefulWidget {
  const SetupScreen({
    required this.onSaved,
    this.initialSettings,
    super.key,
  });

  final AppSettings? initialSettings;
  final Future<void> Function(String importFolder, String exportFolder) onSaved;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final StoragePermissionService _permissionService = StoragePermissionService();
  String? _importFolder;
  String? _exportFolder;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _importFolder = widget.initialSettings?.importFolder;
    _exportFolder = widget.initialSettings?.exportFolder;
  }

  Future<void> _pickImport() async {
    final selected = await FilePicker.getDirectoryPath(dialogTitle: '选择导入文件夹');
    if (selected == null) {
      return;
    }
    setState(() => _importFolder = selected);
  }

  Future<void> _pickExport() async {
    final selected = await FilePicker.getDirectoryPath(dialogTitle: '选择导出文件夹');
    if (selected == null) {
      return;
    }
    setState(() => _exportFolder = selected);
  }

  Future<void> _save() async {
    final importFolder = _importFolder;
    final exportFolder = _exportFolder;
    if (importFolder == null || exportFolder == null) {
      showSnack(context, '首次运行需要选择导入文件夹和导出文件夹');
      return;
    }
    if (!Directory(importFolder).existsSync()) {
      showSnack(context, '导入文件夹不存在');
      return;
    }
    if (!Directory(exportFolder).existsSync()) {
      showSnack(context, '导出文件夹不存在');
      return;
    }

    setState(() => _saving = true);
    await _permissionService.requestFolderAccess();
    await widget.onSaved(importFolder, exportFolder);
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('文件夹设置'),
        leading: Navigator.of(context).canPop()
            ? IconButton(
                tooltip: '返回',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FolderPickTile(
                title: '导入文件夹',
                path: _importFolder,
                icon: Icons.drive_folder_upload,
                onTap: _pickImport,
              ),
              const SizedBox(height: 12),
              FolderPickTile(
                title: '导出文件夹',
                path: _exportFolder,
                icon: Icons.folder_special,
                onTap: _pickExport,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('保存并进入'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FolderPickTile extends StatelessWidget {
  const FolderPickTile({
    required this.title,
    required this.path,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final String title;
  final String? path;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      path ?? '未选择',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class LibraryEntry {
  const LibraryEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
  });

  final String path;
  final String name;
  final bool isDirectory;
}

class FileLibraryService {
  Future<List<LibraryEntry>> listEntries(String directoryPath) async {
    final dir = Directory(directoryPath);
    final entities = await dir.list().toList();
    final entries = <LibraryEntry>[];
    for (final entity in entities) {
      final stat = await entity.stat();
      final name = p.basename(entity.path);
      if (stat.type == FileSystemEntityType.directory) {
        entries.add(
          LibraryEntry(path: entity.path, name: name, isDirectory: true),
        );
      } else if (stat.type == FileSystemEntityType.file &&
          name.toLowerCase().endsWith('.mp4')) {
        entries.add(
          LibraryEntry(path: entity.path, name: name, isDirectory: false),
        );
      }
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    required this.settings,
    required this.onChangeFolders,
    super.key,
  });

  final AppSettings settings;
  final VoidCallback onChangeFolders;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final FileLibraryService _service = FileLibraryService();
  late String _currentPath;
  late Future<List<LibraryEntry>> _entries;

  bool get _isAtRoot => p.normalize(_currentPath) == p.normalize(widget.settings.importFolder);

  @override
  void initState() {
    super.initState();
    _currentPath = widget.settings.importFolder;
    _entries = _service.listEntries(_currentPath);
  }

  void _reload() {
    setState(() {
      _entries = _service.listEntries(_currentPath);
    });
  }

  void _openDirectory(String path) {
    setState(() {
      _currentPath = path;
      _entries = _service.listEntries(_currentPath);
    });
  }

  void _goUp() {
    if (_isAtRoot) {
      return;
    }
    final parent = p.dirname(_currentPath);
    if (!p.isWithin(widget.settings.importFolder, parent) &&
        p.normalize(parent) != p.normalize(widget.settings.importFolder)) {
      return;
    }
    setState(() {
      _currentPath = parent;
      _entries = _service.listEntries(_currentPath);
    });
  }

  Future<void> _openVideo(String path) async {
    await Navigator.of(context).push<void>(
      slideRoute(
        EditorScreen(
          videoPath: path,
          outputFolder: widget.settings.exportFolder,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _isAtRoot,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_isAtRoot) {
          _goUp();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('LivoCut'),
          actions: <Widget>[
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              onPressed: _reload,
            ),
            IconButton(
              tooltip: '文件夹设置',
              icon: const Icon(Icons.tune),
              onPressed: widget.onChangeFolders,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              PathBar(root: widget.settings.importFolder, current: _currentPath),
              if (!_isAtRoot)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: OutlinedButton.icon(
                    onPressed: _goUp,
                    icon: const Icon(Icons.arrow_upward),
                    label: const Text('返回上一级'),
                  ),
                ),
              Expanded(
                child: FutureBuilder<List<LibraryEntry>>(
                  future: _entries,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return PermissionErrorView(
                        error: snapshot.error.toString(),
                        onRetry: () async {
                          await StoragePermissionService().requestFolderAccess();
                          _reload();
                        },
                      );
                    }
                    final entries = snapshot.data ?? <LibraryEntry>[];
                    if (entries.isEmpty) {
                      return const EmptyLibraryView();
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return LibraryEntryTile(
                          entry: entry,
                          onTap: () => entry.isDirectory
                              ? _openDirectory(entry.path)
                              : _openVideo(entry.path),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PathBar extends StatelessWidget {
  const PathBar({required this.root, required this.current, super.key});

  final String root;
  final String current;

  @override
  Widget build(BuildContext context) {
    final relative = p.normalize(current) == p.normalize(root)
        ? '/'
        : p.relative(current, from: root);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xffdbe3ea)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              const Icon(Icons.route, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  relative,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LibraryEntryTile extends StatelessWidget {
  const LibraryEntryTile({
    required this.entry,
    required this.onTap,
    super.key,
  });

  final LibraryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(
                entry.isDirectory ? Icons.folder : Icons.movie_creation_outlined,
                color: entry.isDirectory ? const Color(0xffb7791f) : const Color(0xff0f766e),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyLibraryView extends StatelessWidget {
  const EmptyLibraryView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '当前目录没有文件夹或 MP4 文件',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

class PermissionErrorView extends StatelessWidget {
  const PermissionErrorView({
    required this.error,
    required this.onRetry,
    super.key,
  });

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.lock_outline, size: 36),
            const SizedBox(height: 12),
            Text(
              '无法读取当前目录',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.admin_panel_settings),
              label: const Text('申请权限后重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class ClipRange {
  ClipRange({
    this.start = Duration.zero,
    this.end = Duration.zero,
  });

  Duration start;
  Duration end;
}

enum StepScale {
  frame('帧', null),
  oneSecond('1s', Duration(seconds: 1)),
  twoSeconds('2s', Duration(seconds: 2)),
  threeSeconds('3s', Duration(seconds: 3)),
  fiveSeconds('5s', Duration(seconds: 5)),
  tenSeconds('10s', Duration(seconds: 10));

  const StepScale(this.label, this.duration);

  final String label;
  final Duration? duration;
}

class VideoProbeService {
  Future<Duration> frameDuration(String path) async {
    try {
      final session = await FFprobeKit.executeWithArguments(<String>[
        '-v',
        'error',
        '-select_streams',
        'v:0',
        '-show_entries',
        'stream=avg_frame_rate,r_frame_rate',
        '-of',
        'json',
        path,
      ]);
      final output = await session.getOutput();
      if (output == null || output.isEmpty) {
        return const Duration(milliseconds: 33);
      }
      final data = jsonDecode(output) as Map<String, dynamic>;
      final streams = data['streams'] as List<dynamic>?;
      if (streams == null || streams.isEmpty) {
        return const Duration(milliseconds: 33);
      }
      final stream = streams.first as Map<String, dynamic>;
      final frameRate = _parseRate(stream['avg_frame_rate'] as String?) ??
          _parseRate(stream['r_frame_rate'] as String?);
      if (frameRate == null || frameRate <= 0) {
        return const Duration(milliseconds: 33);
      }
      return Duration(microseconds: (1000000 / frameRate).round());
    } catch (_) {
      return const Duration(milliseconds: 33);
    }
  }

  double? _parseRate(String? value) {
    if (value == null || value == '0/0') {
      return null;
    }
    final parts = value.split('/');
    if (parts.length == 2) {
      final numerator = double.tryParse(parts[0]);
      final denominator = double.tryParse(parts[1]);
      if (numerator == null || denominator == null || denominator == 0) {
        return null;
      }
      return numerator / denominator;
    }
    return double.tryParse(value);
  }
}

class ExportService {
  Future<List<String>> exportClips({
    required String inputPath,
    required String outputFolder,
    required List<ClipRange> clips,
  }) async {
    final outputDir = Directory(outputFolder);
    if (!outputDir.existsSync()) {
      await outputDir.create(recursive: true);
    }
    final baseName = p.basenameWithoutExtension(inputPath);
    final outputs = <String>[];
    for (var i = 0; i < clips.length; i++) {
      final clip = clips[i];
      final outputPath = p.join(outputFolder, '${baseName}_${i + 1}.mp4');
      final args = <String>[
        '-hide_banner',
        '-y',
        '-ss',
        ffmpegTimestamp(clip.start),
        '-t',
        ffmpegTimestamp(clip.end - clip.start),
        '-i',
        inputPath,
        '-map',
        '0:v:0',
        '-map',
        '0:a?',
        '-sn',
        '-c',
        'copy',
        '-avoid_negative_ts',
        'make_zero',
        outputPath,
      ];
      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        final output = await session.getOutput();
        throw ExportException(
          '第 ${i + 1} 个片段导出失败${output == null || output.isEmpty ? '' : ': $output'}',
        );
      }
      outputs.add(outputPath);
    }
    return outputs;
  }
}

class ExportException implements Exception {
  ExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class EditorPalette {
  static const Color shell = Color(0xff07090d);
  static const Color videoChrome = Color(0xff0b0f14);
  static const Color panel = Color(0xfff4f7f8);
  static const Color panelRaised = Color(0xffffffff);
  static const Color panelMuted = Color(0xffe7edf1);
  static const Color line = Color(0xffd6e0e5);
  static const Color text = Color(0xff172026);
  static const Color mutedText = Color(0xff65737d);
  static const Color teal = Color(0xff0f766e);
  static const Color tealSoft = Color(0xffd8f3ee);
  static const Color danger = Color(0xffb42318);
}

class NativeVideoController extends ChangeNotifier {
  NativeVideoController(this.path);

  static const String viewType = 'livocut/native_video_player';

  final String path;
  MethodChannel? _channel;
  Timer? _pollTimer;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  bool _isReady = false;
  bool _disposed = false;
  bool _scrubDispatching = false;
  int _scrubGeneration = 0;
  int _lastScrubSentUs = 0;
  Duration? _pendingScrubTarget;

  Duration get duration => _duration;
  Duration get position => _position;
  bool get isPlaying => _isPlaying;
  bool get isReady => _isReady;

  Future<void> attach(int viewId) async {
    if (_disposed) {
      return;
    }
    _channel = MethodChannel('livocut/native_video_player_$viewId');
    await refresh();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      unawaited(refresh());
    });
  }

  Future<void> refresh() async {
    final state = await _invoke<Map<dynamic, dynamic>>('getState');
    if (state == null || _disposed) {
      return;
    }
    _applyState(state);
  }

  Future<void> play() async {
    final state = await _invoke<Map<dynamic, dynamic>>('play');
    if (state != null) {
      _applyState(state);
      return;
    }
    _isPlaying = true;
    notifyListeners();
  }

  Future<void> pause() async {
    final state = await _invoke<Map<dynamic, dynamic>>('pause');
    if (state != null) {
      _applyState(state);
      return;
    }
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> seekTo(Duration target) async {
    final clamped = _clampToDuration(target);
    _position = clamped;
    notifyListeners();
    final state = await _invoke<Map<dynamic, dynamic>>(
      'seekTo',
      <String, Object>{'position': clamped.inMilliseconds},
    );
    if (state != null) {
      _applyState(state);
    }
  }

  Future<void> beginScrub() async {
    _scrubGeneration++;
    _pendingScrubTarget = null;
    final state = await _invoke<Map<dynamic, dynamic>>('beginScrub');
    if (state != null) {
      _applyState(state);
      return;
    }
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> scrubTo(Duration target) {
    final clamped = _clampToDuration(target);
    _position = clamped;
    _pendingScrubTarget = clamped;
    notifyListeners();
    if (!_scrubDispatching) {
      unawaited(_dispatchScrub(_scrubGeneration));
    }
    return Future<void>.value();
  }

  Future<void> endScrub(Duration target, bool shouldPlay) async {
    _scrubGeneration++;
    _pendingScrubTarget = null;
    final clamped = _clampToDuration(target);
    _position = clamped;
    notifyListeners();
    final state = await _invoke<Map<dynamic, dynamic>>(
      'endScrub',
      <String, Object>{
        'position': clamped.inMilliseconds,
        'play': shouldPlay,
      },
    );
    if (state != null) {
      _applyState(state);
      return;
    }
    _isPlaying = shouldPlay;
    notifyListeners();
  }

  Future<void> _dispatchScrub(int generation) async {
    _scrubDispatching = true;
    try {
      while (!_disposed &&
          generation == _scrubGeneration &&
          _pendingScrubTarget != null) {
        final target = _pendingScrubTarget!;
        _pendingScrubTarget = null;
        final nowUs = DateTime.now().microsecondsSinceEpoch;
        final waitUs = 16000 - (nowUs - _lastScrubSentUs);
        if (waitUs > 0) {
          await Future<void>.delayed(Duration(microseconds: waitUs));
        }
        if (_disposed || generation != _scrubGeneration) {
          break;
        }
        await _invoke<Map<dynamic, dynamic>>(
          'scrubTo',
          <String, Object>{'position': target.inMilliseconds},
        );
        _lastScrubSentUs = DateTime.now().microsecondsSinceEpoch;
      }
    } finally {
      _scrubDispatching = false;
      if (!_disposed &&
          generation == _scrubGeneration &&
          _pendingScrubTarget != null) {
        unawaited(_dispatchScrub(generation));
      }
    }
  }

  Duration _clampToDuration(Duration target) {
    return clampDuration(target, Duration.zero, _duration);
  }

  void _applyState(Map<dynamic, dynamic> state) {
    _duration = Duration(milliseconds: (state['duration'] as num? ?? 0).round());
    _position = Duration(milliseconds: (state['position'] as num? ?? 0).round());
    _isPlaying = state['isPlaying'] as bool? ?? false;
    _isReady = state['isReady'] as bool? ?? false;
    notifyListeners();
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    final channel = _channel;
    if (channel == null || _disposed) {
      return null;
    }
    try {
      return channel.invokeMethod<T>(method, arguments);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    final channel = _channel;
    _disposed = true;
    _pollTimer?.cancel();
    _pendingScrubTarget = null;
    if (channel != null) {
      unawaited(channel.invokeMethod<void>('release'));
    }
    super.dispose();
  }
}

class NativeVideoPlayer extends StatelessWidget {
  const NativeVideoPlayer({
    required this.controller,
    super.key,
  });

  final NativeVideoController controller;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            '当前播放器仅支持 Android',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return AndroidView(
      viewType: NativeVideoController.viewType,
      creationParams: <String, Object>{'path': controller.path},
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (viewId) {
        unawaited(controller.attach(viewId));
      },
    );
  }
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    required this.videoPath,
    required this.outputFolder,
    super.key,
  });

  final String videoPath;
  final String outputFolder;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final ExportService _exportService = ExportService();
  final VideoProbeService _probeService = VideoProbeService();
  late final NativeVideoController _controller;
  final List<ClipRange> _clips = <ClipRange>[ClipRange()];
  StepScale _stepScale = StepScale.frame;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Duration _frameStep = const Duration(milliseconds: 33);
  bool _initializing = true;
  bool _isPlaying = false;
  bool _scrubbing = false;
  bool _wasPlayingBeforeScrub = false;
  bool _exporting = false;
  bool _previewing = false;
  Duration? _pendingSeek;
  Completer<void>? _seekCompleter;
  Timer? _previewTimer;
  Duration? _restorePosition;
  bool _restoreWasPlaying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _controller = NativeVideoController(widget.videoPath);
    _controller.addListener(_syncFromPlayer);
    try {
      _frameStep = await _probeService.frameDuration(widget.videoPath);
      if (!mounted) {
        return;
      }
      setState(() {
        _position = Duration.zero;
        _initializing = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _initializing = false;
      });
    }
  }

  void _syncFromPlayer() {
    if (!mounted) {
      return;
    }
    setState(() {
      _duration = _controller.duration;
      if (!_scrubbing) {
        _position = _controller.position;
      }
      _isPlaying = _controller.isPlaying;
    });
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _controller.removeListener(_syncFromPlayer);
    _controller.dispose();
    super.dispose();
  }

  Duration get _displayPosition => clampDuration(_position, Duration.zero, _duration);

  Duration get _activeStep => _stepScale.duration ?? _frameStep;

  Future<void> _queueSeek(Duration target) async {
    _pendingSeek = clampDuration(target, Duration.zero, _duration);
    if (_seekCompleter != null) {
      return _seekCompleter!.future;
    }

    _seekCompleter = Completer<void>();
    try {
      while (_pendingSeek != null) {
        final next = _pendingSeek!;
        _pendingSeek = null;
        await _controller.seekTo(next);
        if (mounted) {
          setState(() => _position = next);
        }
      }
      _seekCompleter?.complete();
    } catch (_) {
      _seekCompleter?.complete();
    } finally {
      _seekCompleter = null;
    }
  }

  Future<void> _startScrub(double _) async {
    _wasPlayingBeforeScrub = _controller.isPlaying;
    _scrubbing = true;
    await _controller.beginScrub();
  }

  void _changeScrub(double value) {
    final target = Duration(milliseconds: value.round());
    setState(() => _position = target);
    unawaited(_controller.scrubTo(target));
  }

  Future<void> _endScrub(double value) async {
    final target = Duration(milliseconds: value.round());
    await _controller.endScrub(target, _wasPlayingBeforeScrub);
    _scrubbing = false;
    if (mounted) {
      setState(() {
        _position = target;
        _isPlaying = _controller.isPlaying;
      });
    }
  }

  Future<void> _togglePlayback() async {
    if (_controller.isPlaying) {
      await _controller.pause();
    } else {
      await _controller.play();
    }
    if (mounted) {
      setState(() => _isPlaying = _controller.isPlaying);
    }
  }

  Future<void> _nudge(int direction) async {
    final target = _displayPosition + (_activeStep * direction);
    await _queueSeek(target);
  }

  void _setClipStart(int index) {
    setState(() => _clips[index].start = _displayPosition);
  }

  void _setClipEnd(int index) {
    setState(() => _clips[index].end = _displayPosition);
  }

  void _addClip() {
    setState(() => _clips.add(ClipRange()));
  }

  void _deleteClip(int index) {
    setState(() => _clips.removeAt(index));
  }

  Future<void> _startClipPreview(ClipRange clip) async {
    if (_previewing) {
      return;
    }
    _previewing = true;
    _restorePosition = _displayPosition;
    _restoreWasPlaying = _controller.isPlaying;
    await _controller.pause();
    await _queueSeek(clip.start);
    await _controller.play();
    _previewTimer = Timer.periodic(const Duration(milliseconds: 40), (_) async {
      if (!_previewing) {
        return;
      }
      final end = clip.end > clip.start ? clip.end : clip.start + const Duration(seconds: 1);
      if (_controller.position >= end) {
        await _controller.seekTo(clip.start);
        await _controller.play();
      }
    });
  }

  Future<void> _stopClipPreview() async {
    if (!_previewing) {
      return;
    }
    _previewing = false;
    _previewTimer?.cancel();
    _previewTimer = null;
    final restorePosition = _restorePosition ?? Duration.zero;
    final restoreWasPlaying = _restoreWasPlaying;
    await _controller.pause();
    await _queueSeek(restorePosition);
    if (restoreWasPlaying) {
      await _controller.play();
    }
    if (mounted) {
      setState(() => _isPlaying = _controller.isPlaying);
    }
  }

  Future<void> _export() async {
    if (_clips.isEmpty) {
      showSnack(context, '请先添加至少一个片段');
      return;
    }
    for (var i = 0; i < _clips.length; i++) {
      final clip = _clips[i];
      if (clip.start > clip.end) {
        showSnack(context, '第 ${i + 1} 个片段的开始时间晚于结束时间');
        return;
      }
      if (clip.start == clip.end) {
        showSnack(context, '第 ${i + 1} 个片段的开始和结束相同');
        return;
      }
    }

    setState(() => _exporting = true);
    try {
      final outputs = await _exportService.exportClips(
        inputPath: widget.videoPath,
        outputFolder: widget.outputFolder,
        clips: _clips,
      );
      if (!mounted) {
        return;
      }
      showSnack(context, '已导出 ${outputs.length} 个片段');
    } catch (error) {
      if (!mounted) {
        return;
      }
      showSnack(context, error.toString());
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EditorPalette.shell,
      body: SafeArea(
        child: _initializing
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? EditorErrorView(error: _error!)
                : Column(
                    children: <Widget>[
                      Expanded(
                        flex: 5,
                        child: VideoPane(
                          controller: _controller,
                          title: p.basename(widget.videoPath),
                          onBack: () => Navigator.of(context).pop(),
                        ),
                      ),
                      Expanded(
                        flex: 6,
                        child: EditorControlsPane(
                          duration: _duration,
                          position: _displayPosition,
                          isPlaying: _isPlaying,
                          stepScale: _stepScale,
                          clips: _clips,
                          exporting: _exporting,
                          onScrubStart: _startScrub,
                          onScrubChanged: _changeScrub,
                          onScrubEnd: _endScrub,
                          onTogglePlayback: _togglePlayback,
                          onStepScaleChanged: (scale) => setState(() => _stepScale = scale),
                          onNudgeBack: () => _nudge(-1),
                          onNudgeForward: () => _nudge(1),
                          onSetClipStart: _setClipStart,
                          onSetClipEnd: _setClipEnd,
                          onAddClip: _addClip,
                          onDeleteClip: _deleteClip,
                          onPreviewStart: _startClipPreview,
                          onPreviewEnd: _stopClipPreview,
                          onExport: _export,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class VideoPane extends StatelessWidget {
  const VideoPane({
    required this.controller,
    required this.title,
    required this.onBack,
    super.key,
  });

  final NativeVideoController controller;
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(color: EditorPalette.videoChrome),
            child: NativeVideoPlayer(controller: controller),
          ),
        ),
        Positioned.fill(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            opacity: controller.isReady ? 0 : 1,
            child: IgnorePointer(
              ignoring: controller.isReady,
              child: VideoLoadingOverlay(title: title),
            ),
          ),
        ),
        Positioned(
          left: 10,
          right: 10,
          top: 10,
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: '返回',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                color: Colors.white,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xcc111820),
                  fixedSize: const Size(44, 44),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xcc111820),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x22ffffff)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class VideoLoadingOverlay extends StatelessWidget {
  const VideoLoadingOverlay({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: EditorPalette.videoChrome),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.movie_filter_outlined,
                color: Color(0xff9fb3bd),
                size: 34,
              ),
              const SizedBox(height: 14),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              const SizedBox(
                width: 132,
                child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Color(0xff1d2831),
                  color: EditorPalette.teal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EditorControlsPane extends StatelessWidget {
  const EditorControlsPane({
    required this.duration,
    required this.position,
    required this.isPlaying,
    required this.stepScale,
    required this.clips,
    required this.exporting,
    required this.onScrubStart,
    required this.onScrubChanged,
    required this.onScrubEnd,
    required this.onTogglePlayback,
    required this.onStepScaleChanged,
    required this.onNudgeBack,
    required this.onNudgeForward,
    required this.onSetClipStart,
    required this.onSetClipEnd,
    required this.onAddClip,
    required this.onDeleteClip,
    required this.onPreviewStart,
    required this.onPreviewEnd,
    required this.onExport,
    super.key,
  });

  final Duration duration;
  final Duration position;
  final bool isPlaying;
  final StepScale stepScale;
  final List<ClipRange> clips;
  final bool exporting;
  final ValueChanged<double> onScrubStart;
  final ValueChanged<double> onScrubChanged;
  final ValueChanged<double> onScrubEnd;
  final VoidCallback onTogglePlayback;
  final ValueChanged<StepScale> onStepScaleChanged;
  final Future<void> Function() onNudgeBack;
  final Future<void> Function() onNudgeForward;
  final void Function(int index) onSetClipStart;
  final void Function(int index) onSetClipEnd;
  final VoidCallback onAddClip;
  final void Function(int index) onDeleteClip;
  final Future<void> Function(ClipRange clip) onPreviewStart;
  final Future<void> Function() onPreviewEnd;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: EditorPalette.panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      child: Column(
        children: <Widget>[
          PlaybackControlBlock(
            duration: duration,
            position: position,
            isPlaying: isPlaying,
            stepScale: stepScale,
            onScrubStart: onScrubStart,
            onScrubChanged: onScrubChanged,
            onScrubEnd: onScrubEnd,
            onTogglePlayback: onTogglePlayback,
            onStepScaleChanged: onStepScaleChanged,
            onNudgeBack: onNudgeBack,
            onNudgeForward: onNudgeForward,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
            child: Row(
              children: <Widget>[
                const Text(
                  '片段',
                  style: TextStyle(
                    color: EditorPalette.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                SegmentCountPill(count: clips.length),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
              itemCount: clips.length + 1,
              itemBuilder: (context, index) {
                if (index == clips.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: AddSegmentButton(
                      onPressed: onAddClip,
                    ),
                  );
                }
                final clip = clips[index];
                return ClipCard(
                  index: index,
                  clip: clip,
                  onSetStart: () => onSetClipStart(index),
                  onSetEnd: () => onSetClipEnd(index),
                  onDelete: () => onDeleteClip(index),
                  onPreviewStart: () => onPreviewStart(clip),
                  onPreviewEnd: onPreviewEnd,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: FilledButton.icon(
              onPressed: exporting ? null : onExport,
              icon: exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share),
              label: Text('导出 ${clips.length} 段'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: EditorPalette.teal,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xffb7c8c5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SegmentCountPill extends StatelessWidget {
  const SegmentCountPill({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: EditorPalette.tealSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          '$count',
          style: const TextStyle(
            color: EditorPalette.teal,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class AddSegmentButton extends StatelessWidget {
  const AddSegmentButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add),
      label: const Text('增加片段'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        foregroundColor: EditorPalette.teal,
        side: const BorderSide(color: EditorPalette.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class PlaybackControlBlock extends StatelessWidget {
  const PlaybackControlBlock({
    required this.duration,
    required this.position,
    required this.isPlaying,
    required this.stepScale,
    required this.onScrubStart,
    required this.onScrubChanged,
    required this.onScrubEnd,
    required this.onTogglePlayback,
    required this.onStepScaleChanged,
    required this.onNudgeBack,
    required this.onNudgeForward,
    super.key,
  });

  final Duration duration;
  final Duration position;
  final bool isPlaying;
  final StepScale stepScale;
  final ValueChanged<double> onScrubStart;
  final ValueChanged<double> onScrubChanged;
  final ValueChanged<double> onScrubEnd;
  final VoidCallback onTogglePlayback;
  final ValueChanged<StepScale> onStepScaleChanged;
  final Future<void> Function() onNudgeBack;
  final Future<void> Function() onNudgeForward;

  @override
  Widget build(BuildContext context) {
    final maxMs = math.max(duration.inMilliseconds, 1);
    final value = position.inMilliseconds.clamp(0, maxMs).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: EditorPalette.panelRaised,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: EditorPalette.line),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      TimeReadout(
                        value: shortTimestamp(position),
                        active: true,
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 6,
                            activeTrackColor: EditorPalette.teal,
                            inactiveTrackColor: EditorPalette.panelMuted,
                            thumbColor: EditorPalette.text,
                            overlayColor: const Color(0x220f766e),
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 18,
                            ),
                          ),
                          child: Slider(
                            min: 0,
                            max: maxMs.toDouble(),
                            value: value,
                            onChangeStart: onScrubStart,
                            onChanged: onScrubChanged,
                            onChangeEnd: onScrubEnd,
                          ),
                        ),
                      ),
                      TimeReadout(value: shortTimestamp(duration)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      HoldStepButton(
                        tooltip: '后退',
                        icon: Icons.skip_previous,
                        onStep: onNudgeBack,
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        tooltip: isPlaying ? '暂停' : '播放',
                        onPressed: onTogglePlayback,
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          child: Icon(
                            isPlaying ? Icons.pause : Icons.play_arrow,
                            key: ValueKey<bool>(isPlaying),
                          ),
                        ),
                        color: Colors.white,
                        style: IconButton.styleFrom(
                          backgroundColor: EditorPalette.text,
                          fixedSize: const Size(52, 52),
                        ),
                      ),
                      const SizedBox(width: 10),
                      HoldStepButton(
                        tooltip: '前进',
                        icon: Icons.skip_next,
                        onStep: onNudgeForward,
                      ),
                      const Spacer(),
                      StepScalePicker(
                        value: stepScale,
                        onChanged: onStepScaleChanged,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TimeReadout extends StatelessWidget {
  const TimeReadout({
    required this.value,
    this.active = false,
    super.key,
  });

  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: Text(
        value,
        textAlign: active ? TextAlign.left : TextAlign.right,
        style: tabularText(context).copyWith(
          color: active ? EditorPalette.text : EditorPalette.mutedText,
          fontSize: 13,
          fontWeight: active ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }
}

class StepScalePicker extends StatelessWidget {
  const StepScalePicker({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final StepScale value;
  final ValueChanged<StepScale> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: EditorPalette.panelMuted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 6),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<StepScale>(
            value: value,
            borderRadius: BorderRadius.circular(8),
            icon: const Icon(Icons.expand_more, size: 20),
            style: const TextStyle(
              color: EditorPalette.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            items: StepScale.values
                .map(
                  (scale) => DropdownMenuItem<StepScale>(
                    value: scale,
                    child: Text(scale.label),
                  ),
                )
                .toList(),
            onChanged: (scale) {
              if (scale != null) {
                onChanged(scale);
              }
            },
          ),
        ),
      ),
    );
  }
}

class HoldStepButton extends StatefulWidget {
  const HoldStepButton({
    required this.tooltip,
    required this.icon,
    required this.onStep,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onStep;

  @override
  State<HoldStepButton> createState() => _HoldStepButtonState();
}

class _HoldStepButtonState extends State<HoldStepButton> {
  Timer? _timer;
  bool _busy = false;

  Future<void> _step() async {
    if (_busy) {
      return;
    }
    _busy = true;
    try {
      await widget.onStep();
    } finally {
      _busy = false;
    }
  }

  void _startHold() {
    unawaited(_step());
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 130), (_) {
      unawaited(_step());
    });
  }

  void _stopHold() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTap: () => unawaited(_step()),
        onLongPressStart: (_) => _startHold(),
        onLongPressEnd: (_) => _stopHold(),
        onLongPressCancel: _stopHold,
        child: Material(
          color: EditorPalette.panelMuted,
          shape: const CircleBorder(),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(widget.icon, color: EditorPalette.text),
          ),
        ),
      ),
    );
  }
}

class ClipCard extends StatelessWidget {
  const ClipCard({
    required this.index,
    required this.clip,
    required this.onSetStart,
    required this.onSetEnd,
    required this.onDelete,
    required this.onPreviewStart,
    required this.onPreviewEnd,
    super.key,
  });

  final int index;
  final ClipRange clip;
  final VoidCallback onSetStart;
  final VoidCallback onSetEnd;
  final VoidCallback onDelete;
  final Future<void> Function() onPreviewStart;
  final Future<void> Function() onPreviewEnd;

  @override
  Widget build(BuildContext context) {
    final invalid = clip.start > clip.end;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: EditorPalette.panelRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: invalid ? EditorPalette.danger : EditorPalette.line,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 30,
                height: 46,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: invalid
                        ? const Color(0xffffe4e0)
                        : EditorPalette.tealSoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: invalid
                            ? EditorPalette.danger
                            : EditorPalette.teal,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TimeSetButton(
                title: '开始',
                label: shortTimestamp(clip.start),
                onPressed: onSetStart,
              ),
              const SizedBox(width: 7),
              TimeSetButton(
                title: '结束',
                label: shortTimestamp(clip.end),
                onPressed: onSetEnd,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onLongPressStart: (_) => unawaited(onPreviewStart()),
                  onLongPressEnd: (_) => unawaited(onPreviewEnd()),
                  onLongPressCancel: () => unawaited(onPreviewEnd()),
                  child: SizedBox(
                    height: 46,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: EditorPalette.panelMuted,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.play_circle_outline,
                          color: EditorPalette.mutedText,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: '删除',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                color: EditorPalette.danger,
                style: IconButton.styleFrom(
                  fixedSize: const Size(42, 42),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TimeSetButton extends StatelessWidget {
  const TimeSetButton({
    required this.title,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String title;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(68, 46),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        foregroundColor: EditorPalette.text,
        side: const BorderSide(color: EditorPalette.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: EditorPalette.mutedText,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: tabularText(context).copyWith(
              color: EditorPalette.text,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class EditorErrorView extends StatelessWidget {
  const EditorErrorView({required this.error, super.key});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, color: Colors.white, size: 40),
            const SizedBox(height: 12),
            Text(
              '视频打开失败',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }
}

TextStyle tabularText(BuildContext context) {
  return Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );
}

String shortTimestamp(Duration duration) {
  final totalSeconds = math.max(duration.inSeconds, 0);
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String ffmpegTimestamp(Duration duration) {
  final micros = math.max(duration.inMicroseconds, 0);
  final hours = micros ~/ Duration.microsecondsPerHour;
  final minutes = (micros ~/ Duration.microsecondsPerMinute) % 60;
  final seconds = (micros ~/ Duration.microsecondsPerSecond) % 60;
  final milliseconds = (micros ~/ Duration.microsecondsPerMillisecond) % 1000;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}.'
      '${milliseconds.toString().padLeft(3, '0')}';
}

Duration clampDuration(Duration value, Duration min, Duration max) {
  if (value < min) {
    return min;
  }
  if (max > min && value > max) {
    return max;
  }
  return value;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

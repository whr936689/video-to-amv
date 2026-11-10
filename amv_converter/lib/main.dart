import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const AmvApp());
}

class AmvApp extends StatelessWidget {
  const AmvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '视频转 AMV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D5AFE)),
      ),
      home: const ConverterPage(),
    );
  }
}

class ConverterPage extends StatefulWidget {
  const ConverterPage({super.key});

  @override
  State<ConverterPage> createState() => _ConverterPageState();
}

class _ConverterPageState extends State<ConverterPage> with WidgetsBindingObserver {
  // ---------- 输入视频 ----------
  String? _inputPath;
  String _inputName = '';
  double? _durationSec;
  int? _srcWidth;
  int? _srcHeight;
  bool _hasAudio = true;
  bool _probing = false;

  // ---------- 输出参数 ----------
  _OutFormat _format = _OutFormat.amv;
  int _sizeIndex = 0;
  int _fps = 15;
  int _qualityIndex = 1; // 0 high · 1 middle · 2 low
  int _transformIndex = 0; // 0 正常 · 1 上下交换 · 2 左右交换 · 3 上下-左右交换 · 4 顺时针 90° · 5 逆时针 90°
  int _audioBitrate = 88; // AVI(mp3) 音频比特率，单位 kbps

  // ---------- 高级选项 ----------
  bool _cutEnabled = false;
  final TextEditingController _cutStartCtrl =
      TextEditingController(text: '00:00:00');
  final TextEditingController _cutEndCtrl =
      TextEditingController(text: '00:00:00');
  String? _replaceAudioPath;
  String _replaceAudioName = '';
  bool _videoSync = true;
  bool _audioSync = true;
  bool _autoPlay = false;

  // ---------- 转换状态 ----------
  bool _running = false;
  double _progress = 0;
  String _status = '';
  String? _outputPath;
  int _outputSize = 0;
  final List<String> _logs = <String>[];
  DateTime _lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  // ---------- 批量转换 ----------
  final List<_BatchItem> _batchItems = <_BatchItem>[];
  bool _batchRunning = false;
  double _batchProgress = 0;
  String _batchStatus = '';

  // ---------- 输出目录 ----------
  static const MethodChannel _storageChannel = MethodChannel('amv/storage');
  String? _outputDir;
  bool _storageGranted = true;

  static const List<List<int>> _amvSizes = <List<int>>[
    <int>[160, 128],
    <int>[176, 128],
    <int>[176, 144],
    <int>[192, 160],
    <int>[208, 120],
    <int>[208, 160],
    <int>[208, 176],
    <int>[320, 240],
  ];

  static const List<List<int>> _aviSizes = <List<int>>[
    <int>[160, 128],
    <int>[176, 128],
    <int>[176, 144],
    <int>[192, 160],
    <int>[208, 120],
    <int>[208, 160],
    <int>[208, 176],
    <int>[320, 240],
  ];

  static const List<int> _fpsOptions = <int>[10, 15, 25];

  static const List<String> _qualityLabels = <String>[
    'high',
    'middle',
    'low',
  ];

  static const List<int> _qualityValues = <int>[3, 6, 10];

  static const List<String> _transformLabels = <String>[
    '正常',
    '上下交换',
    '左右交换',
    '上下-左右交换',
    '顺时针旋转90度',
    '逆时针旋转90度',
  ];

  static const List<String> _transformFilters = <String>[
    '',
    'vflip',
    'hflip',
    'vflip,hflip',
    'transpose=1',
    'transpose=2',
  ];

  static const List<int> _bitrateOptions = <int>[64, 88, 128, 192];

  List<List<int>> get _sizes =>
      _format == _OutFormat.amv ? _amvSizes : _aviSizes;

  bool get _canConvert => _inputPath != null && !_probing && !_running;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cutStartCtrl.dispose();
    _cutEndCtrl.dispose();
    super.dispose();
  }

  static double? _parseTime(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    var total = 0.0;
    for (final part in text.split(':')) {
      final value = double.tryParse(part.trim());
      if (value == null) return null;
      total = total * 60 + value;
    }
    return total;
  }

  static String _formatSeconds(double seconds) {
    final total = seconds.floor();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initOutputDir());
    Future<void>.microtask(_logFfmpegVersion);
  }

  Future<File> _outputDirPrefsFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/output_dir.txt');
  }

  Future<void> _initOutputDir() async {
    try {
      final file = await _outputDirPrefsFile();
      if (await file.exists()) {
        final path = (await file.readAsString()).trim();
        if (path.isNotEmpty && mounted) {
          setState(() => _outputDir = path);
        }
      }
    } catch (_) {}
    await _checkStorageOnStart();
  }

  Future<void> _saveOutputDir(String? path) async {
    try {
      final file = await _outputDirPrefsFile();
      if (path == null) {
        if (await file.exists()) await file.delete();
      } else {
        await file.writeAsString(path);
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStorageAccess();
    }
  }

  Future<bool> _canWriteAll() async {
    try {
      return await _storageChannel.invokeMethod<bool>('canWriteAll') ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> _checkStorageOnStart() async {
    final granted = await _canWriteAll();
    if (!mounted) return;
    setState(() => _storageGranted = granted);
    if (!granted) _showPermissionDialog();
  }

  Future<void> _refreshStorageAccess() async {
    final granted = await _canWriteAll();
    if (mounted && granted != _storageGranted) {
      setState(() => _storageGranted = granted);
    }
  }

  void _showPermissionDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要存储权限'),
        content: const Text('视频转 AMV 需要“所有文件访问权限”，才能把转换结果保存到你选择的目录。\n'
            '不授权时会保存到应用专属目录。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _requestStorageAccess();
            },
            child: const Text('去授权'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestStorageAccess() async {
    try {
      await _storageChannel.invokeMethod<dynamic>('requestAccess');
    } catch (_) {}
  }

  Future<void> _pickOutputDir() async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: '选择输出目录');
    if (path == null) return;
    if (!await _isDirWritable(path)) {
      if (!mounted) return;
      _showDirNotWritable(path);
      return;
    }
    if (!mounted) return;
    setState(() => _outputDir = path);
    await _saveOutputDir(path);
    _toast('输出目录：$path');
  }

  /// 真实写入探测：创建目录并写入/删除一个临时文件，确认当前进程有写权限。
  Future<bool> _isDirWritable(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) await dir.create(recursive: true);
      final probe = File('${dir.path}/.amv_write_probe');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 转换前校验输出目录；不可写时弹窗引导授权或改用默认目录。
  Future<bool> _ensureOutputWritable() async {
    final dir = _outputDir;
    if (dir == null) return true;
    if (await _isDirWritable(dir)) return true;
    if (!mounted) return false;
    _showDirNotWritable(dir);
    return false;
  }

  void _showDirNotWritable(String path) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('所选目录不可写'),
        content: Text('无法写入：\n$path\n\n'
            '如果这是手机存储中的目录，请授予“所有文件访问权限”；'
            '若系统不允许，也可以改用默认目录。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _outputDir = null);
              _saveOutputDir(null);
            },
            child: const Text('改用默认目录'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _requestStorageAccess();
            },
            child: const Text('去授权'),
          ),
        ],
      ),
    );
  }

  Future<void> _logFfmpegVersion() async {
    final session = await FFmpegKit.execute('-hide_banner -version');
    final logs = await session.getLogsAsString();
    final first = logs.split('\n').where((l) => l.trim().isNotEmpty).take(2).join('\n');
    if (!mounted || first.isEmpty) return;
    setState(() => _logs.add('[ffmpeg] $first'));
  }

  Future<void> _pickVideo() async {
    final picked = await FilePicker.pickFile(type: FileType.video);
    final path = picked?.path;
    if (path == null) return;

    setState(() {
      _inputPath = path;
      _inputName = picked!.name;
      _durationSec = null;
      _srcWidth = null;
      _srcHeight = null;
      _hasAudio = true;
      _probing = true;
      _outputPath = null;
      _outputSize = 0;
      _progress = 0;
      _status = '正在读取视频信息…';
      _logs.clear();
    });

    try {
      final probeSession = await FFprobeKit.getMediaInformation(path);
      final info = probeSession.getMediaInformation();
      if (info == null) {
        throw const FormatException('无法识别该视频文件');
      }
      final streams = info.getStreams();
      final videos = streams.where((s) => s.getType() == 'video').toList();
      if (videos.isEmpty) {
        throw const FormatException('这个文件里没有视频轨道');
      }
      final video = videos.first;
      final duration = double.tryParse(info.getDuration() ?? '');
      final hasAudio = streams.any((s) => s.getType() == 'audio');

      if (!mounted) return;
      setState(() {
        _durationSec = duration;
        _srcWidth = video.getWidth();
        _srcHeight = video.getHeight();
        _hasAudio = hasAudio;
        _probing = false;
        _status = '';
      });
      if (duration != null && duration > 0) {
        _cutEndCtrl.text = _formatSeconds(duration);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _probing = false;
        _status = '读取视频信息失败';
        _logs.add('$e');
      });
      _toast('读取失败：$e');
    }
  }

  Future<File> _resolveOutputFile(String baseName) async {
    final sizes = _sizes;
    final size = sizes[_sizeIndex.clamp(0, sizes.length - 1)];
    final width = size[0];
    final height = size[1];
    Directory outDir;
    final picked = _outputDir;
    if (picked != null) {
      outDir = Directory(picked);
    } else {
      final docsDir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      outDir = Directory('${docsDir.path}/AMV');
    }
    await outDir.create(recursive: true);
    final name = baseName
        .replaceAll(RegExp(r'\.[^.]+$'), '')
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    final ext = _format == _OutFormat.amv ? 'amv' : 'avi';
    return File('${outDir.path}/${name}_${width}x$height.$ext');
  }

  List<String> _buildArgs(String inputPath, String? audioPath,
      bool hasAudio, String outputPath) {
    final sizes = _sizes;
    final size = sizes[_sizeIndex.clamp(0, sizes.length - 1)];
    final width = size[0];
    final height = size[1];

    final startSec = _cutEnabled ? _parseTime(_cutStartCtrl.text) : null;
    final endSec = _cutEnabled ? _parseTime(_cutEndCtrl.text) : null;
    final hasCut = startSec != null && startSec > 0;

    final vf = <String>[
      if (_transformFilters[_transformIndex].isNotEmpty)
        _transformFilters[_transformIndex],
      'scale=$width:$height:force_original_aspect_ratio=decrease',
      'pad=$width:$height:(ow-iw)/2:(oh-ih)/2:color=black',
      'setsar=1',
    ];

    return <String>[
      '-hide_banner',
      '-y',
      if (hasCut) ...<String>['-ss', _formatSeconds(startSec)],
      '-i', inputPath,
      if (hasCut && endSec != null && endSec > 0)
        ...<String>['-to', _formatSeconds(endSec)],
      if (audioPath != null) ...<String>['-i', audioPath],
      if (audioPath == null && !hasAudio) ...<String>[
        '-f', 'lavfi',
        '-i', 'anullsrc=channel_layout=mono:sample_rate=22050',
      ],
      '-map', '0:v:0',
      '-map', audioPath != null
          ? '1:a:0'
          : (hasAudio ? '0:a:0' : '1:a:0'),
      '-vf', vf.join(','),
      '-r', '$_fps',
      if (_videoSync) ...<String>['-fps_mode', 'cfr'],
      if (_format == _OutFormat.amv) ...<String>['-strict', '-1'],
      '-c:v', _format == _OutFormat.amv ? 'amv' : 'mpeg4',
      '-q:v', '${_qualityValues[_qualityIndex]}',
      if (_format == _OutFormat.amv) ...<String>['-pix_fmt', 'yuvj420p'],
      if (_format == _OutFormat.amv)
        ...<String>[
          '-c:a', 'adpcm_ima_amv',
          '-block_size', '${22050 ~/ _fps}',
          '-ar', '22050',
          '-ac', '1',
        ]
      else
        ...<String>[
          '-c:a', 'libmp3lame',
          '-b:a', '${_audioBitrate}k',
          '-ar', '44100',
          '-ac', '2',
          '-vtag', 'XVID',
        ],
      if (_audioSync) ...<String>['-af', 'aresample=async=1:first_pts=0'],
      '-shortest',
      outputPath,
    ];
  }

  Future<Map<String, dynamic>> _probeMedia(String path) async {
    final probeSession = await FFprobeKit.getMediaInformation(path);
    final info = probeSession.getMediaInformation();
    double? duration;
    bool hasAudio = true;
    if (info != null) {
      final streams = info.getStreams();
      duration = double.tryParse(info.getDuration() ?? '');
      hasAudio = streams.any((s) => s.getType() == 'audio');
    }
    return <String, dynamic>{'duration': duration, 'hasAudio': hasAudio};
  }

  Future<void> _convert() async {
    final input = _inputPath;
    if (input == null || _running) return;
    if (!await _ensureOutputWritable()) return;

    final startSec = _cutEnabled ? _parseTime(_cutStartCtrl.text) : null;
    final endSec = _cutEnabled ? _parseTime(_cutEndCtrl.text) : null;
    final hasCut = startSec != null && startSec > 0;
    final totalSec = hasCut && endSec != null && endSec > startSec
        ? endSec - startSec
        : (hasCut && _durationSec != null
            ? _durationSec! - startSec
            : _durationSec);

    final outputFile = await _resolveOutputFile(_inputName);
    if (await outputFile.exists()) {
      await outputFile.delete();
    }

    final args =
        _buildArgs(input, _replaceAudioPath, _hasAudio, outputFile.path);

    setState(() {
      _running = true;
      _progress = 0;
      _status = '正在转换…';
      _outputPath = null;
      _outputSize = 0;
      _logs
        ..clear()
        ..add('命令: ffmpeg ${args.join(' ')}');
    });

    await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) => _onSessionComplete(session, outputFile),
      (log) {
        final message = log.getMessage();
        if (message.isEmpty) return;
        _logs.add(message.trimRight());
        if (_logs.length > 200) _logs.removeAt(0);
        _throttledRebuild();
      },
      (statistics) {
        final ms = statistics.getTime();
        final next = totalSec != null && totalSec > 0
            ? (ms / 1000 / totalSec).clamp(0.0, 1.0).toDouble()
            : 0.0;
        if (totalSec != null && next > _progress) {
          _progress = next;
          _throttledRebuild();
        }
      },
    );
  }

  void _throttledRebuild() {
    final now = DateTime.now();
    if (now.difference(_lastUiUpdate).inMilliseconds < 400) return;
    _lastUiUpdate = now;
    if (mounted) setState(() {});
  }

  Future<void> _onSessionComplete(FFmpegSession session, File outputFile) async {
    final returnCode = await session.getReturnCode();
    final success = ReturnCode.isSuccess(returnCode);
    final cancelled = ReturnCode.isCancel(returnCode);
    final exists = await outputFile.exists();
    final size = exists ? await outputFile.length() : 0;

    if (!mounted) return;
    setState(() {
      _running = false;
      _progress = success && exists ? 1.0 : _progress;
      _status = success && exists
          ? '转换完成'
          : cancelled
          ? '已取消'
          : '转换失败';
      _outputPath = success && exists ? outputFile.path : null;
      _outputSize = size;
    });

    if (success && exists) {
      _toast('转换完成，可以分享或拷出了');
      if (_autoPlay) {
        await OpenFilex.open(outputFile.path);
      }
    } else if (!cancelled) {
      _toast('转换失败，请展开日志查看原因');
    }
  }

  Future<void> _pickAudio() async {
    final picked = await FilePicker.pickFile(type: FileType.audio);
    final path = picked?.path;
    if (path == null) return;
    setState(() {
      _replaceAudioPath = path;
      _replaceAudioName = picked!.name;
    });
  }

  // ---------- 批量转换 ----------
  Future<void> _addBatchVideos() async {
    if (_running || _batchRunning) return;
    final files = await FilePicker.pickFiles(type: FileType.video);
    if (files.isEmpty) return;
    setState(() {
      _batchStatus = '正在读取 ${files.length} 个视频信息…';
    });
    for (final f in files) {
      if (f.path == null) continue;
      final meta = await _probeMedia(f.path!);
      if (!mounted) return;
      setState(() {
        _batchItems.add(_BatchItem(
          path: f.path!,
          name: f.name,
          duration: meta['duration'] as double?,
          hasAudio: meta['hasAudio'] as bool,
        ));
      });
    }
    _updateBatchStatus();
  }

  void _removeSelectedBatch() {
    if (_batchRunning) return;
    setState(() {
      _batchItems.removeWhere((it) => it.checked);
    });
    _updateBatchStatus();
  }

  void _clearBatch() {
    if (_batchRunning) return;
    setState(() {
      _batchItems.clear();
      _batchProgress = 0;
      _batchStatus = '';
    });
  }

  Future<void> _pickBatchAudio(int index) async {
    if (_batchRunning) return;
    final picked = await FilePicker.pickFile(type: FileType.audio);
    final path = picked?.path;
    if (path == null) return;
    if (!mounted) return;
    setState(() {
      _batchItems[index].audioPath = path;
      _batchItems[index].audioName = picked!.name;
    });
  }

  void _updateBatchStatus() {
    final checked = _batchItems.where((it) => it.checked).length;
    final done = _batchItems.where((it) => it.checked && it.status == '已完成').length;
    _batchStatus = '共 ${_batchItems.length} 个，已选 $checked 个，已完成 $done 个';
    _batchProgress = checked > 0 ? done / checked : 0;
    if (mounted) setState(() {});
  }

  Future<void> _startBatchConvert() async {
    if (_running || _batchRunning) return;
    final pending = _batchItems.where((it) => it.checked && it.status != '已完成').toList();
    if (pending.isEmpty) {
      _toast('没有待转换的勾选项');
      return;
    }
    if (!await _ensureOutputWritable()) return;
    setState(() {
      _batchRunning = true;
      _logs
        ..clear()
        ..add('批量转换开始，共 ${pending.length} 个');
    });
    await _runBatchNext(0);
    // 后续文件的链式推进在 ffmpeg 完成回调里进行，完成时由 _runBatchNext 收尾
  }

  Future<void> _runBatchNext(int from) async {
    _BatchItem? item;
    for (int i = from; i < _batchItems.length; i++) {
      final it = _batchItems[i];
      if (it.checked && it.status != '已完成') {
        item = it;
        break;
      }
    }
    if (item == null) {
      if (!mounted) return;
      setState(() {
        _batchRunning = false;
      });
      _toast('批量转换完成');
      return;
    }
    final current = item;

    final startSec = _cutEnabled ? _parseTime(_cutStartCtrl.text) : null;
    final endSec = _cutEnabled ? _parseTime(_cutEndCtrl.text) : null;
    final hasCut = startSec != null && startSec > 0;
    final totalSec = hasCut && endSec != null && endSec > startSec
        ? endSec - startSec
        : (hasCut && current.duration != null ? current.duration! - startSec : current.duration);

    final outputFile = await _resolveOutputFile(current.name);
    if (await outputFile.exists()) await outputFile.delete();

    final args = _buildArgs(current.path, current.audioPath, current.hasAudio, outputFile.path);

    if (!mounted) return;
    setState(() {
      current.status = '转换中';
      current.progress = 0;
      _batchStatus = '正在转换：${current.name}';
      _logs.add('命令: ffmpeg ${args.join(' ')}');
    });

    await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) async {
        final returnCode = await session.getReturnCode();
        final exists = await outputFile.exists();
        final size = exists ? await outputFile.length() : 0;
        // 用输出文件是否生成且非空作为主要判据（部分版本 returnCode 取不到）
        final ok = exists && size > 0;
        if (!mounted) return;
        setState(() {
          current.status = ok ? '已完成' : '失败';
          current.progress = ok ? 1.0 : current.progress;
          if (!ok) {
            _logs.add('【${current.name}】转换失败（returnCode=$returnCode, 文件存在=$exists, 大小=$size）');
          }
        });
        _updateBatchStatus();
        await _runBatchNext(_batchItems.indexOf(current) + 1);
      },
      (log) {
        final message = log.getMessage();
        if (message.isEmpty) return;
        _logs.add(message.trimRight());
        if (_logs.length > 400) _logs.removeAt(0);
        _throttledRebuild();
      },
      (statistics) {
        final ms = statistics.getTime();
        if (totalSec != null && totalSec > 0) {
          final next = (ms / 1000 / totalSec).clamp(0.0, 1.0).toDouble();
          if (next > current.progress) {
            current.progress = next;
            _throttledRebuild();
          }
        }
      },
    );
  }

  Future<void> _cancel() async {
    await FFmpegKit.cancel();
    if (!mounted) return;
    setState(() => _status = '正在取消…');
  }

  Future<void> _share() async {
    final path = _outputPath;
    if (path == null) return;
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(path)],
        text: '视频已转换为 AMV',
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatDuration(double seconds) {
    final total = seconds.round();
    final m = total ~/ 60;
    final s = total % 60;
    return m > 0 ? '$m 分 $s 秒' : '$s 秒';
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频转 AMV'),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            tooltip: '关于软件',
            icon: const Icon(Icons.person_outline),
            onPressed: _showAboutApp,
          ),
          IconButton(
            tooltip: '关于 AMV',
            icon: const Icon(Icons.info_outline),
            onPressed: _showAbout,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: <Widget>[
            _inputCard(theme),
            const SizedBox(height: 12),
            _settingsCard(theme),
            const SizedBox(height: 12),
            _advancedCard(theme),
            const SizedBox(height: 12),
            _outputCard(theme),
            const SizedBox(height: 16),
            _actionArea(theme),
            const SizedBox(height: 12),
            _batchCard(theme),
            if (_outputPath != null) ...<Widget>[
              const SizedBox(height: 12),
              _resultCard(theme),
            ],
            const SizedBox(height: 12),
            _logCard(theme),
          ],
        ),
      ),
    );
  }

  Widget _card(
    ThemeData theme,
    String title,
    IconData icon,
    Widget Function() childBuilder,
  ) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            childBuilder(),
          ],
        ),
      ),
    );
  }

  Widget _inputCard(ThemeData theme) {
    return _card(theme, '源视频', Icons.movie_outlined, () {
      if (_inputPath == null) {
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _pickVideo,
            icon: const Icon(Icons.video_library_outlined),
            label: const Text('选择视频文件'),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _inputName,
            style: theme.textTheme.bodyLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          if (_probing)
            const Row(
              children: <Widget>[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('读取中…'),
              ],
            )
          else
            Text(
              '${_srcWidth ?? '?'}×${_srcHeight ?? '?'}'
              '${_durationSec == null ? '' : ' · ${_formatDuration(_durationSec!)}'}'
              '${_hasAudio ? ' · 有音轨' : ' · 无音轨（自动补静音）'}',
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _running ? null : _pickVideo,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('更换视频'),
          ),
        ],
      );
    });
  }

  Widget _optionLabel(ThemeData theme, String text) =>
      Text(text, style: theme.textTheme.labelLarge);

  Widget _dropdownBox<T>(
    T value,
    List<T> values,
    String Function(T) label,
    ValueChanged<T>? onChanged,
  ) {
    return InputDecorator(
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          items: <DropdownMenuItem<T>>[
            for (final v in values)
              DropdownMenuItem<T>(value: v, child: Text(label(v))),
          ],
          onChanged: onChanged == null
              ? null
              : (v) {
                  if (v != null) onChanged(v);
                },
        ),
      ),
    );
  }

  Widget _switchRow(
    ThemeData theme,
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    String? subtitle,
  }) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: theme.textTheme.bodyMedium),
              if (subtitle != null)
                Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        Switch(value: value, onChanged: _running ? null : onChanged),
      ],
    );
  }

  Widget _timeField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      enabled: !_running,
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(
        labelText: label,
        hintText: '00:00:00',
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
    );
  }

  Widget _settingsCard(ThemeData theme) {
    final sizes = _sizes;
    final sizeIndex = _sizeIndex.clamp(0, sizes.length - 1);
    return _card(theme, '输出参数', Icons.tune, () {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _optionLabel(theme, '视频类型'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (final format in _OutFormat.values)
                ChoiceChip(
                  label: Text(format == _OutFormat.amv ? 'AMV' : 'AVI'),
                  selected: _format == format,
                  onSelected: _running
                      ? null
                      : (_) => setState(() {
                            _format = format;
                            _sizeIndex = 0;
                          }),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _optionLabel(theme, '视频长宽'),
          const SizedBox(height: 6),
          _dropdownBox<int>(
            sizeIndex,
            <int>[for (var i = 0; i < sizes.length; i++) i],
            (i) => '${sizes[i][0]}×${sizes[i][1]}',
            _running ? null : (i) => setState(() => _sizeIndex = i),
          ),
          const SizedBox(height: 14),
          _optionLabel(theme, '帧率'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (final fps in _fpsOptions)
                ChoiceChip(
                  label: Text('$fps fps'),
                  selected: _fps == fps,
                  onSelected: _running
                      ? null
                      : (_) => setState(() => _fps = fps),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _optionLabel(theme, '视频变换'),
          const SizedBox(height: 6),
          _dropdownBox<int>(
            _transformIndex,
            <int>[for (var i = 0; i < _transformLabels.length; i++) i],
            (i) => _transformLabels[i],
            _running ? null : (i) => setState(() => _transformIndex = i),
          ),
          const SizedBox(height: 14),
          _optionLabel(theme, '图像品质'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (var i = 0; i < _qualityLabels.length; i++)
                ChoiceChip(
                  label: Text(_qualityLabels[i]),
                  selected: _qualityIndex == i,
                  onSelected: _running
                      ? null
                      : (_) => setState(() => _qualityIndex = i),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _optionLabel(theme, '音频比特率'),
          const SizedBox(height: 6),
          _dropdownBox<int>(
            _format == _OutFormat.amv ? 88 : _audioBitrate,
            _format == _OutFormat.amv ? <int>[88] : _bitrateOptions,
            (kbps) => '${kbps}K',
            _format == _OutFormat.amv || _running
                ? null
                : (kbps) => setState(() => _audioBitrate = kbps),
          ),
          if (_format == _OutFormat.amv)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('AMV 音频固定为 88K（22050Hz 单声道）',
                  style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: <Widget>[
              FilterChip(
                label: const Text('视频同步'),
                selected: _videoSync,
                onSelected: _running
                    ? null
                    : (v) => setState(() => _videoSync = v),
              ),
              FilterChip(
                label: const Text('音频同步'),
                selected: _audioSync,
                onSelected: _running
                    ? null
                    : (v) => setState(() => _audioSync = v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'AMV：22050Hz 单声道，分辨率建议不超过 208×160；'
            'AVI：MPEG-4 + MP3，兼容更多老设备，也支持更大尺寸。',
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    });
  }

  Widget _advancedCard(ThemeData theme) {
    return _card(theme, '高级选项', Icons.build_outlined, () {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _switchRow(
            theme,
            '截取源视频片断',
            _cutEnabled,
            (v) => setState(() => _cutEnabled = v),
            subtitle: '关闭时转换整段视频',
          ),
          if (_cutEnabled) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(child: _timeField(_cutStartCtrl, '开始时间')),
                const SizedBox(width: 10),
                Expanded(child: _timeField(_cutEndCtrl, '结束时间')),
              ],
            ),
            const SizedBox(height: 4),
            Text('格式：时:分:秒 或 分:秒', style: theme.textTheme.bodySmall),
          ],
          const Divider(height: 24),
          _switchRow(
            theme,
            '用新的音频文件替换原音轨',
            _replaceAudioPath != null,
            (v) {
              if (v) {
                _pickAudio();
              } else {
                setState(() {
                  _replaceAudioPath = null;
                  _replaceAudioName = '';
                });
              }
            },
          ),
          if (_replaceAudioPath != null)
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _replaceAudioName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: _running ? null : _pickAudio,
                  child: const Text('更换'),
                ),
              ],
            ),
          const Divider(height: 24),
          _switchRow(
            theme,
            '转换完自动播放',
            _autoPlay,
            (v) => setState(() => _autoPlay = v),
            subtitle: '用系统默认播放器打开输出文件',
          ),
        ],
      );
    });
  }

  Widget _outputCard(ThemeData theme) {
    return _card(theme, '输出目录', Icons.folder_outlined, () {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _outputDir ??
                      '默认：应用专属目录（Android/data/com.example.amv_converter/files/AMV）',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: _running ? null : _pickOutputDir,
                child: const Text('更改'),
              ),
              if (_outputDir != null)
                TextButton(
                  onPressed: _running
                      ? null
                      : () {
                          setState(() => _outputDir = null);
                          _saveOutputDir(null);
                        },
                  child: const Text('恢复默认'),
                ),
            ],
          ),
          if (!_storageGranted)
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '未获得“所有文件访问权限”，所选目录可能无法写入',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
                TextButton(
                  onPressed: _requestStorageAccess,
                  child: const Text('去授权'),
                ),
              ],
            ),
        ],
      );
    });
  }

  Widget _batchCard(ThemeData theme) {
    Color statusColor(String s) {
      switch (s) {
        case '转换中':
          return Colors.orange;
        case '已完成':
          return Colors.green;
        case '失败':
          return Colors.red;
        default:
          return Colors.grey;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.playlist_play, size: 20),
                const SizedBox(width: 6),
                Text('批量转换', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _running || _batchRunning ? null : _addBatchVideos,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加视频'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _batchRunning ? null : _removeSelectedBatch,
                    icon: const Icon(Icons.remove, size: 18),
                    label: const Text('移除选中'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _batchRunning ? null : _clearBatch,
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    label: const Text('清空'),
                  ),
                ),
              ],
            ),
            if (_batchItems.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('点击「添加视频」选择多个视频',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
              )
            else
              SizedBox(
                height: 200,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _batchItems.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext ctx, int i) {
                    final it = _batchItems[i];
                    return InkWell(
                      onTap: _batchRunning ? null : () => _pickBatchAudio(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        child: Row(
                          children: <Widget>[
                            Checkbox(
                              value: it.checked,
                              onChanged: _batchRunning
                                  ? null
                                  : (v) => setState(() => it.checked = v ?? false),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(it.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium),
                                  Text(
                                    it.audioName != null
                                        ? '音频：${it.audioName}'
                                        : '（点击替换音频）',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant),
                                  ),
                                  if (it.status == '转换中') ...<Widget>[
                                    const SizedBox(height: 3),
                                    LinearProgressIndicator(
                                        value: it.progress, minHeight: 4),
                                  ],
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 56,
                              child: Text(
                                  it.status == '转换中'
                                      ? '${(it.progress * 100).toStringAsFixed(0)}%'
                                      : it.status,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: statusColor(it.status),
                                      fontWeight: FontWeight.bold)),
                            ),
                            SizedBox(
                              width: 48,
                              child: Text(
                                it.duration == null
                                    ? '--:--'
                                    : _formatDuration(it.duration!),
                                textAlign: TextAlign.right,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _batchRunning
                    ? null
                    : (_running ? null : _startBatchConvert),
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade600),
                icon: const Icon(Icons.playlist_play),
                label: Text(_batchRunning ? '批量转换中…' : '批量转换'),
              ),
            ),
            if (_batchStatus.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _batchProgress),
              const SizedBox(height: 4),
              Text(_batchStatus, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionArea(ThemeData theme) {
    return Column(
      children: <Widget>[
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: _canConvert ? _convert : null,
            icon: const Icon(Icons.play_arrow),
            label: Text(_running ? '转换中…' : '开始转换'),
          ),
        ),
        if (_running) ...<Widget>[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _durationSec == null ? null : _progress),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _durationSec == null
                      ? '处理中…'
                      : '${(_progress * 100).toStringAsFixed(0)}% · '
                          '${_formatDuration(_progress * _durationSec!)} / '
                          '${_formatDuration(_durationSec!)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(onPressed: _cancel, child: const Text('取消')),
            ],
          ),
        ] else if (_status.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(_status, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }

  Widget _resultCard(ThemeData theme) {
    return _card(theme, '转换结果', Icons.check_circle_outline, () {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            File(_outputPath!).uri.pathSegments.last,
            style: theme.textTheme.bodyLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text('文件大小：${_formatSize(_outputSize)}',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          SelectableText(
            _outputPath!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _share,
              icon: const Icon(Icons.ios_share),
              label: const Text('分享 / 拷出到其他应用'),
            ),
          ),
        ],
      );
    });
  }

  Widget _logCard(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: ExpansionTile(
        title: Text('转换日志', style: theme.textTheme.titleSmall),
        children: <Widget>[
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: Text(
                _logs.isEmpty ? '暂无日志' : _logs.join('\n'),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactTile(IconData icon, String label, String value) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20),
      title: Text('$label：$value'),
      trailing: const Icon(Icons.copy, size: 16),
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        _toast('已复制 $label：$value');
      },
    );
  }

  void _showAboutApp() {
    showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ClipOval(
                child: Image.asset(
                  'assets/avatar.jpg',
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '擅长捉弄人的王同学',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text('视频转 AMV 作者', style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              _contactTile(Icons.chat_bubble_outline, 'QQ', '3418696565'),
              _contactTile(Icons.alternate_email, 'X', 'hoshino_mion'),
              const SizedBox(height: 4),
              Text('点击可复制', style: theme.textTheme.bodySmall),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关于 AMV'),
        content: const Text(
          'AMV（Actions Media Video）是给老式 MP4/MP5、插卡音箱等设备使用的视频格式，'
          '本质是改造过的 AVI：视频为 AMV(类 MJPEG)，音频为 IMA ADPCM。\n\n'
          '本工具支持 AMV / AVI 两种输出、截取片段、画面翻转与旋转、'
          '替换音轨、音视频同步等选项。若设备仍无法播放，'
          '可尝试更低分辨率和 10fps。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

enum _OutFormat { amv, avi }

class _BatchItem {
  String path;
  String name;
  String? audioPath;
  String? audioName;
  double? duration;
  bool hasAudio;
  bool checked;
  String status; // 未处理 / 转换中 / 已完成 / 失败
  double progress; // 0.0 ~ 1.0

  _BatchItem({
    required this.path,
    required this.name,
    this.audioPath,
    this.audioName,
    this.duration,
    this.hasAudio = true,
    this.checked = true,
    this.status = '未处理',
    this.progress = 0,
  });
}

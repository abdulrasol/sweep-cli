import 'dart:io';
import 'dart:async';
import 'dart:convert';

class Framework {
  final String name;
  final List<String> markers;
  final String cleanupLabel;
  final String? command;
  final String? auditCommand;
  final String? upgradeCommand;
  final List<String> foldersToNuke;
  final List<CleanupItem> globalCaches;
  bool detected = false;
  final bool isCustom;

  Framework({
    required this.name,
    required this.markers,
    required this.cleanupLabel,
    this.command,
    this.auditCommand,
    this.upgradeCommand,
    required this.foldersToNuke,
    this.globalCaches = const [],
    this.isCustom = false,
  });
}

class CleanupItem {
  final String label;
  final String category;
  final String? path;
  final List<String>? batchPaths;
  final String? command;
  final String? upgradeCommand;
  final String? warning;
  final String? note;
  bool selected = false;
  bool maintainSelected = false;
  bool archiveSelected = false;
  final bool isBatch;
  String? estimatedSize;
  DateTime? lastModified;
  List<CleanupItem>? subItems;
  bool isDirty = false;
  String? healthStatus;

  CleanupItem({
    required this.label,
    required this.category,
    this.path,
    this.command,
    this.upgradeCommand,
    this.warning,
    this.note,
    this.isBatch = false,
    this.estimatedSize,
    this.lastModified,
    this.subItems,
    this.batchPaths,
    this.healthStatus,
  });

  bool get isStale => lastModified != null && DateTime.now().difference(lastModified!).inDays > 30;

  String get displayPath => isBatch 
      ? '${batchPaths?.length ?? 0} locations' 
      : (path ?? command ?? '');
}

class SystemStats {
  final String osName;
  final String storageLeft;
  final String ramUsage;
  final String cpuUsage;

  SystemStats({
    required this.osName,
    required this.storageLeft,
    required this.ramUsage,
    required this.cpuUsage,
  });

  factory SystemStats.empty() => SystemStats(osName: 'Loading...', storageLeft: '-', ramUsage: '-', cpuUsage: '-');
}

class Stats {
  Map<String, double> history = {};
  static Future<Stats> load() async {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final file = File('$home/.sweep_stats.json');
    if (!file.existsSync()) return Stats();
    try {
      final Map<String, dynamic> json = jsonDecode(file.readAsStringSync());
      final stats = Stats();
      json.forEach((k, v) => stats.history[k] = (v as num).toDouble());
      return stats;
    } catch (_) { return Stats(); }
  }
  void save() {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final file = File('$home/.sweep_stats.json');
    file.writeAsStringSync(jsonEncode(history));
  }
  void addRecord(double mb) {
    if (mb <= 0) return;
    final date = DateTime.now().toIso8601String().split('T')[0];
    history[date] = (history[date] ?? 0) + mb;
  }
}

class Config {
  String lastPath = '.';
  List<String> ignoredPaths = [];
  static Future<Config> load() async {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final file = File('$home/.sweep_cli_rc');
    if (!file.existsSync()) return Config();
    try {
      final lines = file.readAsLinesSync();
      final config = Config();
      if (lines.isNotEmpty) config.lastPath = lines[0];
      if (lines.length > 1) config.ignoredPaths = lines.sublist(1);
      return config;
    } catch (_) { return Config(); }
  }
  void save() {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final file = File('$home/.sweep_cli_rc');
    final buffer = StringBuffer()..writeln(lastPath);
    for (var p in ignoredPaths) buffer.writeln(p);
    file.writeAsStringSync(buffer.toString());
  }
}

class SweepEngine {
  static Future<String?> getDirSize(String path) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          '([long](Get-ChildItem -Path "$path" -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB)'
        ]);
        if (result.exitCode == 0) {
          final val = double.tryParse(result.stdout.toString().trim());
          if (val != null) return val < 1024 ? '${val.toStringAsFixed(1)}M' : '${(val/1024).toStringAsFixed(1)}G';
        }
      } else {
        final result = await Process.run('du', ['-sh', path]);
        if (result.exitCode == 0) return result.stdout.toString().split('\t').first.trim();
      }
    } catch (_) {}
    return '0M';
  }

  static double parseSizeToMb(String? sizeStr) {
    if (sizeStr == null) return 0;
    final regex = RegExp(r'^([\d\.]+)\s*([KMG])B?$');
    final match = regex.firstMatch(sizeStr.trim().toUpperCase());
    if (match == null) return 0;
    double value = double.tryParse(match.group(1)!) ?? 0;
    String unit = match.group(2)!;
    switch (unit) {
      case 'G': return value * 1024;
      case 'M': return value;
      case 'K': return value / 1024;
      default: return value;
    }
  }

  static String formatMb(double mb) {
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
    return '${mb.toStringAsFixed(2)} MB';
  }

  static Future<SystemStats> getSystemStats() async {
    String os = Platform.operatingSystem;
    String version = Platform.operatingSystemVersion;
    String storage = '-';
    String ram = '-';
    String cpu = '-';

    try {
      if (Platform.isMacOS) {
        // Disk
        final diskRes = await Process.run('df', ['-h', '/']);
        if (diskRes.exitCode == 0) {
          final lines = diskRes.stdout.toString().split('\n');
          if (lines.length > 1) {
            final parts = lines[1].split(RegExp(r'\s+'));
            if (parts.length > 3) storage = parts[3];
          }
        }
        
        // RAM (Using vm_stat for accurate used memory calculation)
        final vmStatRes = await Process.run('vm_stat', []);
        if (vmStatRes.exitCode == 0) {
          final output = vmStatRes.stdout.toString();
          final lines = output.split('\n');
          int pageSize = 4096;
          int active = 0, wired = 0, compressed = 0;
          
          final pageSizeMatch = RegExp(r'page size of (\d+) bytes').firstMatch(output);
          if (pageSizeMatch != null) pageSize = int.parse(pageSizeMatch.group(1)!);

          for (var line in lines) {
            final parts = line.split(':');
            if (parts.length < 2) continue;
            final key = parts[0].trim();
            final val = int.tryParse(parts[1].trim().replaceAll('.', '')) ?? 0;

            if (key == 'Pages active') active = val;
            if (key == 'Pages wired down') wired = val;
            if (key == 'Pages occupied by compressor') compressed = val;
          }
          final usedBytes = (active + wired + compressed) * pageSize;
          ram = '${(usedBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB used';
        }

        // CPU (Using top command)
        final cpuRes = await Process.run('top', ['-l', '1', '-n', '0']);
        if (cpuRes.exitCode == 0) {
          final output = cpuRes.stdout.toString();
          final match = RegExp(r'CPU usage:\s*([\d\.]+)%\s*user').firstMatch(output);
          if (match != null) cpu = '${match.group(1)}%';
        }
      } else if (Platform.isWindows) {
        final diskRes = await Process.run('powershell', ['-Command', '[math]::round(((Get-PSDrive C).Free / 1GB), 1)']);
        if (diskRes.exitCode == 0) storage = '${diskRes.stdout.toString().trim()} GB';
        final memRes = await Process.run('powershell', ['-Command', "[math]::round(((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize - (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory) / 1024 / 1024, 1)"]);
        if (memRes.exitCode == 0) ram = '${memRes.stdout.toString().trim()}G';
        final cpuRes = await Process.run('powershell', ['-Command', "(Get-CimInstance Win32_Processor).LoadPercentage"]);
        if (cpuRes.exitCode == 0) cpu = '${cpuRes.stdout.toString().trim()}%';
      }
    } catch (_) {}

    return SystemStats(
      osName: '${os[0].toUpperCase()}${os.substring(1)} ($version)',
      storageLeft: storage,
      ramUsage: ram,
      cpuUsage: cpu,
    );
  }

  static Future<double> getDiskSpaceGb() async {
    try {
      if (Platform.isMacOS) {
        final diskRes = await Process.run('df', ['-g', '/']); // -g for GB
        if (diskRes.exitCode == 0) {
          final lines = diskRes.stdout.toString().split('\n');
          if (lines.length > 1) {
            final parts = lines[1].split(RegExp(r'\s+'));
            if (parts.length > 3) return double.tryParse(parts[3]) ?? 0;
          }
        }
      } else if (Platform.isWindows) {
        final diskRes = await Process.run('powershell', ['-Command', '(Get-PSDrive C).Free / 1GB']);
        if (diskRes.exitCode == 0) return double.tryParse(diskRes.stdout.toString().trim()) ?? 0;
      } else if (Platform.isLinux) {
        final diskRes = await Process.run('df', ['-BG', '/']);
        if (diskRes.exitCode == 0) {
          final lines = diskRes.stdout.toString().split('\n');
          if (lines.length > 1) {
            final parts = lines[1].split(RegExp(r'\s+'));
            if (parts.length > 3) return double.tryParse(parts[3].replaceAll('G', '')) ?? 0;
          }
        }
      }
    } catch (_) {}
    return 0;
  }

  static Future<List<CleanupItem>> scan(String pathString, List<String> ignoredPaths) async {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final scanDir = Directory(pathString);
    if (!scanDir.existsSync()) return [];

    final frameworks = [
      Framework(name: 'Android Native', markers: ['build.gradle', 'build.gradle.kts'], cleanupLabel: 'Android Build', foldersToNuke: ['build', 'app/build', '.gradle'],
        globalCaches: [CleanupItem(label: 'Gradle Cache', category: 'ANDROID CACHES', path: '$home/.gradle/caches')]),
      Framework(name: 'Flutter', markers: ['pubspec.yaml'], cleanupLabel: 'flutter clean', command: 'flutter clean', auditCommand: 'flutter pub outdated', upgradeCommand: 'flutter pub upgrade', foldersToNuke: ['android/.gradle', '.dart_tool', 'ios/Pods', 'macos/Pods'],
        globalCaches: [CleanupItem(label: 'Dart Pub Cache', category: 'FLUTTER CACHES', path: '$home/.pub-cache'), CleanupItem(label: 'CocoaPods Cache', category: 'FLUTTER CACHES', path: '$home/Library/Caches/CocoaPods')]),
      Framework(name: 'Node / React / Vue', markers: ['package.json'], cleanupLabel: 'node_modules & build', auditCommand: 'npm audit', upgradeCommand: 'npm update', foldersToNuke: ['node_modules', 'dist', 'build', '.next', '.nuxt', 'coverage'],
        globalCaches: [CleanupItem(label: 'NPM Cache', category: 'NODE CACHES', path: Platform.isWindows ? '$home/AppData/Roaming/npm-cache' : '$home/.npm/_cacache'), CleanupItem(label: 'Bun Cache', category: 'NODE CACHES', path: '$home/.bun/install/cache')]),
      Framework(name: 'Python', markers: ['requirements.txt', 'pyproject.toml'], cleanupLabel: 'venv & pycache', foldersToNuke: ['venv', '.venv', '__pycache__', 'build', 'dist', '.pytest_cache'],
        globalCaches: [CleanupItem(label: 'pip Cache', category: 'PYTHON CACHES', path: Platform.isWindows ? '$home/AppData/Local/pip/Cache' : '$home/Library/Caches/pip')]),
      Framework(name: 'Rust', markers: ['Cargo.toml'], cleanupLabel: 'cargo clean', command: 'cargo clean', foldersToNuke: ['target'],
        globalCaches: [CleanupItem(label: 'Cargo Registry', category: 'RUST CACHES', path: '$home/.cargo/registry')]),
      Framework(name: 'C# / .NET', markers: ['.csproj', '.sln'], cleanupLabel: 'dotnet clean', command: 'dotnet clean', foldersToNuke: ['bin', 'obj'],
        globalCaches: [CleanupItem(label: 'NuGet Cache', category: 'DOTNET CACHES', path: '$home/.nuget/packages')]),
      Framework(name: 'Java (Maven)', markers: ['pom.xml'], cleanupLabel: 'mvn clean', command: 'mvn clean', foldersToNuke: ['target'],
        globalCaches: [CleanupItem(label: 'Maven Repo', category: 'JAVA CACHES', path: '$home/.m2/repository')]),
      Framework(name: 'Go', markers: ['go.mod'], cleanupLabel: 'go clean', command: 'go clean -cache', foldersToNuke: ['bin'],
        globalCaches: [CleanupItem(label: 'Go Mod Cache', category: 'GO CACHES', path: '$home/go/pkg/mod')]),
    ];

    try {
      final file = File('$home/.sweep_rules.json');
      if (file.existsSync()) {
        final List<dynamic> json = jsonDecode(file.readAsStringSync());
        for (var f in json) {
          frameworks.add(Framework(
            name: f['name'] ?? 'Custom',
            markers: List<String>.from(f['markers'] ?? []),
            cleanupLabel: f['cleanupLabel'] ?? 'Clean',
            command: f['command'],
            auditCommand: f['auditCommand'],
            upgradeCommand: f['upgradeCommand'],
            foldersToNuke: List<String>.from(f['foldersToNuke'] ?? []),
            isCustom: true,
          ));
        }
      }
    } catch (_) {}

    final allItems = <CleanupItem>[];
    allItems.add(CleanupItem(label: 'Homebrew Cache', category: 'GLOBAL OS CACHES', path: '$home/Library/Caches/Homebrew', note: 'Downloaded source/bottles. Re-downloaded when needed.'));
    allItems.add(CleanupItem(label: 'Docker System Prune', category: 'GLOBAL OS CACHES', command: 'docker system prune -f', note: 'Deletes all stopped containers, unused networks, and dangling images.'));
    if (Platform.isMacOS) {
      allItems.add(CleanupItem(label: 'Xcode DerivedData', category: 'GLOBAL CACHES', path: '$home/Library/Developer/Xcode/DerivedData'));
      allItems.add(CleanupItem(label: 'Xcode Tool Caches', category: 'GLOBAL CACHES', path: '$home/Library/Caches/com.apple.dt.Xcode'));
      allItems.add(CleanupItem(label: 'iOS Simulators', category: 'GLOBAL CACHES', command: 'xcrun simctl delete unavailable'));
    }

    final Map<Framework, List<CleanupItem>> frameworkProjects = {};
    final List<CleanupItem> bigFileItems = [];

    final stream = scanDir.list(recursive: true, followLinks: false).handleError((_) {});
    await for (var entity in stream) {
      if (ignoredPaths.any((p) => entity.path.startsWith(p))) continue;
      if (entity is File) {
        final fileName = entity.path.split(Platform.pathSeparator).last;
        try {
          if (entity.lengthSync() > 100 * 1024 * 1024) {
            bigFileItems.add(CleanupItem(label: 'File: $fileName', category: 'BIG FILES (>100MB)', path: entity.path, estimatedSize: formatMb(entity.lengthSync() / (1024 * 1024)), note: 'Path: ${entity.path}'));
          }
        } catch (_) {}

        for (var fw in frameworks) {
          bool matches = fw.markers.any((m) => fileName == m || fileName.endsWith(m));
          if (matches && !entity.path.contains('${Platform.pathSeparator}.')) {
            fw.detected = true;
            final pPath = entity.parent.path;
            if (frameworkProjects[fw]?.any((i) => i.path == pPath) ?? false) continue;
            
            bool dirty = false;
            final gitDir = Directory('$pPath/.git');
            if (gitDir.existsSync()) {
              try {
                final gitRes = await Process.run('git', ['status', '--porcelain'], workingDirectory: pPath);
                if (gitRes.stdout.toString().trim().isNotEmpty) dirty = true;
              } catch (_) {}
            }

            final lastMod = entity.lastModifiedSync();
            final pItem = CleanupItem(label: pPath.split(Platform.pathSeparator).last, category: '${fw.name.toUpperCase()} PROJECTS', path: pPath, command: fw.command, upgradeCommand: fw.upgradeCommand, lastModified: lastMod, note: 'Last touched: ${lastMod.day}/${lastMod.month}/${lastMod.year}');
            pItem.isDirty = dirty;

            // Audit Check
            if (fw.auditCommand != null) {
              try {
                final auditRes = await Process.run(fw.auditCommand!.split(' ')[0], fw.auditCommand!.split(' ').sublist(1), workingDirectory: pPath);
                if (auditRes.exitCode != 0) {
                  pItem.healthStatus = fw.name == 'Flutter' ? 'OUTDATED DEPS' : 'VULNERABILITIES FOUND';
                } else {
                  pItem.healthStatus = 'HEALTHY';
                }
              } catch (_) {}
            }

            frameworkProjects.putIfAbsent(fw, () => []).add(pItem);
          }
        }
      }
    }

    for (var fw in frameworks.where((f) => f.detected)) {
      allItems.addAll(fw.globalCaches.where((c) => c.path == null || Directory(c.path!).existsSync()));
      final projects = frameworkProjects[fw]!;
      allItems.add(CleanupItem(label: 'Batch: ${fw.cleanupLabel} (${projects.length} projects)', category: '${fw.name.toUpperCase()} PROJECTS', isBatch: true, command: fw.command, upgradeCommand: fw.upgradeCommand, subItems: projects, note: 'Safe clean for ${fw.name} projects.')..selected = true);
    }
    allItems.addAll(bigFileItems);
    return allItems;
  }
}

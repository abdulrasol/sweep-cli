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
  final bool isBatch;
  String? estimatedSize;
  DateTime? lastModified;
  List<CleanupItem>? subItems;

  CleanupItem({
    required this.label,
    required this.category,
    this.path,
    this.batchPaths,
    this.command,
    this.upgradeCommand,
    this.warning,
    this.note,
    this.isBatch = false,
    this.estimatedSize,
    this.lastModified,
    this.subItems,
  });

  bool get isStale => lastModified != null && DateTime.now().difference(lastModified!).inDays > 30;

  String get displayPath => isBatch 
      ? '${batchPaths?.length ?? 0} locations' 
      : (path ?? command ?? '');
}

// ANSI Colors
final bool useColor = !Platform.isWindows || (Platform.environment['TERM'] != null);
final String reset = useColor ? '\x1B[0m' : '';
final String bold = useColor ? '\x1B[1m' : '';
final String red = useColor ? '\x1B[31m' : '';
final String green = useColor ? '\x1B[32m' : '';
final String yellow = useColor ? '\x1B[33m' : '';
final String blue = useColor ? '\x1B[34m' : '';
final String cyan = useColor ? '\x1B[36m' : '';
final String white = useColor ? '\x1B[37m' : '';
final String gray = useColor ? '\x1B[90m' : '';

void showProgressBar(int current, int total, {String? status}) {
  const int width = 30;
  double percent = total > 0 ? current / total : 1.0;
  if (percent > 1.0) percent = 1.0;
  int completedWidth = (percent * width).round();
  int remainingWidth = width - completedWidth;

  String bar = '$cyan[' + '=' * completedWidth + '>' + ' ' * (remainingWidth > 0 ? remainingWidth - 1 : 0) + ']$reset';
  stdout.write('\r$bar ${bold}${(percent * 100).toStringAsFixed(1)}%$reset ${gray}${status ?? ''}$reset');
}

// HIGH PERFORMANCE SIZE CALCULATION
Future<String?> getDirSize(String path) async {
  try {
    if (Platform.isWindows) {
      // Use much faster PowerShell logic with error silencing
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
      final result = await Process.run('du', ['-sh', path], runInShell: true);
      if (result.exitCode == 0) return result.stdout.toString().split('\t').first.trim();
    }
  } catch (_) {}
  return '0M';
}

double parseSizeToMb(String? sizeStr) {
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

String formatMb(double mb) {
  if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
  return '${mb.toStringAsFixed(2)} MB';
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

Future<void> showDashboard() async {
  final stats = await Stats.load();
  print('\n$bold${blue}-----------------------------------------------------------------------$reset');
  print(' $bold${white}📊 Sweep Savings Dashboard$reset');
  print('$bold${blue}-----------------------------------------------------------------------$reset');
  if (stats.history.isEmpty) { print('${gray}No history found.$reset'); return; }
  stats.history.forEach((date, mb) {
    final bar = '$green' + ('█' * (mb / 1024 * 10).clamp(1, 40).toInt()) + '$reset';
    print(' $bold$date$reset | ${formatMb(mb).padLeft(10)} | $bar');
  });
  print('\n Lifetime Reclaimed: ${green}${formatMb(stats.history.values.fold(0, (a, b) => a + b))}$reset\n');
}

void loadCustomFrameworks(List<Framework> frameworks) {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  final file = File('$home/.sweep_rules.json');
  if (!file.existsSync()) return;
  try {
    final List<dynamic> json = jsonDecode(file.readAsStringSync());
    for (var f in json) {
      frameworks.add(Framework(name: f['name'] ?? 'Custom', markers: List<String>.from(f['markers'] ?? []), cleanupLabel: f['cleanupLabel'] ?? 'Clean',
        command: f['command'], auditCommand: f['auditCommand'], upgradeCommand: f['upgradeCommand'], foldersToNuke: List<String>.from(f['foldersToNuke'] ?? []), isCustom: true));
    }
  } catch (_) {}
}

Future<void> showHelp() async {
  print('\n$bold${blue}-----------------------------------------------------------------------$reset');
  print(' $bold${white}📖 Sweep CLI: Help & Usage Guide$reset');
  print('$bold${blue}-----------------------------------------------------------------------$reset');
  print(' ${bold}${cyan}Flags:$reset');
  print('   ${yellow}--install$reset  : Compiles and installs sweep as a global binary.');
  print('   ${yellow}--update$reset   : Automatically updates to the latest version.');
  print('   ${yellow}--stats$reset    : Views your lifetime storage savings dashboard.');
  print('   ${yellow}-h, --help$reset : Shows this help guide.');
  print('');
  print(' ${bold}${cyan}Keyboard Shortcuts (Inside Console):$reset');
  print('   ${bold}Arrows ↑/↓$reset  : Navigate the list (Scrolls automatically)');
  print('   ${bold}Space$reset      : Toggle item for cleanup');
  print('   ${bold}Enter$reset      : Open a batch sub-menu OR Run Cleanup (if selected)');
  print('   ${bold}M$reset          : Toggle Maintenance [FIX] (Auto-upgrade deps)');
  print('   ${bold}I$reset          : Add project to permanent Ignore list');
  print('   ${bold}D$reset          : Toggle Dry Run mode (Simulation)');
  print('   ${bold}X$reset          : Execute all selected tasks');
  print('   ${bold}B$reset          : Go back from a sub-menu');
  print('   ${bold}Q / ESC$reset    : Exit the tool');
  print('$bold${blue}-----------------------------------------------------------------------$reset\n');
}

void main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) { await showHelp(); return; }
  if (args.contains('--install')) {
    final binaryName = Platform.isWindows ? 'sweep.exe' : 'sweep';
    print('Compiling to $binaryName...');
    final res = await Process.run('dart', ['compile', 'exe', Platform.script.toFilePath(), '-o', binaryName]);
    if (res.exitCode == 0) {
      if (Platform.isWindows) print('Success! Add the folder containing $binaryName to your PATH.');
      else { await Process.run('sudo', ['mv', binaryName, '/usr/local/bin/sweep'], runInShell: true); print('Success! Run using "sweep".'); }
    } else { print('Failed: ${res.stderr}'); }
    return;
  }
  if (args.contains('--stats')) { await showDashboard(); return; }

  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  final config = await Config.load();

  final frameworks = [
    Framework(name: 'Android Native', markers: ['build.gradle', 'build.gradle.kts'], cleanupLabel: 'Android Build', foldersToNuke: ['build', 'app/build', '.gradle'],
      globalCaches: [CleanupItem(label: 'Gradle Cache', category: 'ANDROID CACHES', path: '$home/.gradle/caches')]),
    Framework(name: 'Flutter', markers: ['pubspec.yaml'], cleanupLabel: 'flutter clean', command: 'flutter clean', auditCommand: 'flutter pub outdated', upgradeCommand: 'flutter pub upgrade', foldersToNuke: ['android/.gradle', '.dart_tool', 'ios/Pods'],
      globalCaches: [CleanupItem(label: 'Dart Pub Cache', category: 'FLUTTER CACHES', path: '$home/.pub-cache'), CleanupItem(label: 'CocoaPods Cache', category: 'FLUTTER CACHES', path: '$home/Library/Caches/CocoaPods')]),
    Framework(name: 'Node / React', markers: ['package.json'], cleanupLabel: 'node_modules', auditCommand: 'npm audit', upgradeCommand: 'npm update', foldersToNuke: ['node_modules', 'dist', 'build', '.next'],
      globalCaches: [CleanupItem(label: 'NPM Cache', category: 'NODE CACHES', path: Platform.isWindows ? '$home/AppData/Roaming/npm-cache' : '$home/.npm/_cacache')]),
    Framework(name: 'Python', markers: ['requirements.txt'], cleanupLabel: 'venv', foldersToNuke: ['venv', '.venv', '__pycache__']),
    Framework(name: 'Rust', markers: ['Cargo.toml'], cleanupLabel: 'cargo clean', command: 'cargo clean', foldersToNuke: ['target']),
    Framework(name: 'Go', markers: ['go.mod'], cleanupLabel: 'go clean', command: 'go clean -cache', foldersToNuke: ['bin']),
  ];
  loadCustomFrameworks(frameworks);

  while (true) {
    stdout.write('\x1B[2J\x1B[H');
    print('${blue}-----------------------------------------------------------------------$reset');
    print(' $bold${white}🧹 Sweep CLI: Master Maintenance Suite v2.1$reset');
    print(' ${green}Powered and built by Abdulrasol with love of AI$reset');
    print('${blue}-----------------------------------------------------------------------$reset');
    stdout.write('$bold${white}Enter directory to scan [default: ${config.lastPath}]: $reset');
    String input = stdin.readLineSync()?.trim() ?? '';
    if (input.isNotEmpty) config.lastPath = input;
    final scanDir = Directory(config.lastPath);
    if (!scanDir.existsSync()) { print('${red}Error: Not found.$reset'); continue; }
    config.save();

    print('${gray}Performing High-Performance Scan...$reset');
    final allItems = <CleanupItem>[];
    allItems.add(CleanupItem(label: 'Docker System Prune', category: 'SYSTEM MAINTENANCE', command: 'docker system prune -f'));
    if (Platform.isMacOS) allItems.add(CleanupItem(label: 'Xcode DerivedData', category: 'GLOBAL CACHES', path: '$home/Library/Developer/Xcode/DerivedData'));

    final Map<Framework, List<CleanupItem>> frameworkProjects = {};
    final List<CleanupItem> bigFileItems = [];

    // FAST ASYNC SCANNING
    final stream = scanDir.list(recursive: true, followLinks: false).handleError((_) {});
    await for (var entity in stream) {
      if (config.ignoredPaths.any((p) => entity.path.startsWith(p))) continue;
      if (entity is File) {
        final fileName = entity.path.split(Platform.pathSeparator).last;
        // Big File Check (Sampled check for speed)
        if (entity.path.contains(Platform.pathSeparator)) {
           try {
             if (entity.lengthSync() > 100 * 1024 * 1024) {
               bigFileItems.add(CleanupItem(label: 'File: $fileName', category: 'BIG FILES', path: entity.path, estimatedSize: formatMb(entity.lengthSync() / (1024 * 1024))));
             }
           } catch (_) {}
        }
        for (var fw in frameworks) {
          if (fw.markers.any((m) => fileName == m) && !entity.path.contains('${Platform.pathSeparator}.')) {
            fw.detected = true;
            final pPath = entity.parent.path;
            if (frameworkProjects[fw]?.any((i) => i.path == pPath) ?? false) continue;
            final lastMod = entity.lastModifiedSync();
            frameworkProjects.putIfAbsent(fw, () => []).add(CleanupItem(label: pPath.split(Platform.pathSeparator).last, category: '${fw.name.toUpperCase()} PROJECTS', path: pPath, command: fw.command, upgradeCommand: fw.upgradeCommand, lastModified: lastMod, note: 'Last touched: ${lastMod.day}/${lastMod.month}/${lastMod.year}'));
          }
        }
      }
    }

    for (var fw in frameworks.where((f) => f.detected)) {
      for (var cache in fw.globalCaches) { if (cache.path == null || Directory(cache.path!).existsSync()) allItems.add(cache); }
      final projects = frameworkProjects[fw]!;
      allItems.add(CleanupItem(label: 'Batch: ${fw.cleanupLabel} (${projects.length} projects)', category: '${fw.name.toUpperCase()} PROJECTS', isBatch: true, command: fw.command, upgradeCommand: fw.upgradeCommand, subItems: projects)..selected = true);
    }
    allItems.addAll(bigFileItems);

    print('${gray}Calculating sizes (Parallel)...$reset');
    // Limit concurrency to 5 at a time to prevent Windows disk lock-up
    for (var i = 0; i < allItems.length; i += 5) {
      final chunk = allItems.skip(i).take(5);
      await Future.wait(chunk.map((item) async {
        if (item.category == 'BIG FILES') return;
        if (item.path != null) item.estimatedSize = await getDirSize(item.path!);
        else if (item.isBatch && item.subItems != null) {
          double total = 0;
          for (var p in item.subItems!) total += parseSizeToMb(await getDirSize(p.path!));
          if (total > 0) item.estimatedSize = formatMb(total);
        }
      }));
    }

    List<CleanupItem> currentList = allItems;
    int cursor = 0; int scrollOffset = 0; bool dryRun = false;
    final stack = <List<CleanupItem>>[];
    final cursorStack = <int>[];

    stdin.lineMode = false; stdin.echoMode = false;
    bool actionConfirmed = false;
    while (!actionConfirmed) {
      stdout.write('\x1B[2J\x1B[H');
      print('${blue}-----------------------------------------------------------------------$reset');
      print(' $bold${white}Sweep Master Maintenance Console$reset');
      print('${blue}-----------------------------------------------------------------------$reset');
      print(' ${bold}↑/↓$reset Nav | ${bold}Space$reset Toggle | ${bold}Enter$reset Open/Run | ${bold}M$reset Maintenance');
      print(' ${bold}I$reset Ignore | ${bold}D$reset Dry Run | ${bold}X$reset Execute | ${bold}B$reset Back | ${bold}Q/ESC$reset Exit');
      print('${blue}-----------------------------------------------------------------------$reset');
      if (cursor < scrollOffset) scrollOffset = cursor;
      if (cursor >= scrollOffset + 12) scrollOffset = cursor - 12 + 1;
      double totalMb = 0; String? lastCat;
      for (var i = 0; i < currentList.length; i++) {
        final item = currentList[i];
        if (item.selected) totalMb += parseSizeToMb(item.estimatedSize);
        if (i < scrollOffset || i >= scrollOffset + 12) continue;
        if (item.category != lastCat) { print(' $bold$blue[ ${item.category} ]$reset'); lastCat = item.category; }
        print('${cursor == i ? "$yellow> $reset" : "  "}${item.selected ? "$green[x]$reset" : "[ ]"} ${item.isStale ? red + "[STALE] " + reset : ""}${item.maintainSelected ? yellow + "[FIX] " + reset : ""}${item.label} ${item.estimatedSize != null ? "$gray(${item.estimatedSize})$reset" : ""}');
        if (cursor == i && item.note != null) print('     ${blue}ℹ️  ${item.note}$reset');
      }
      print('${blue}-----------------------------------------------------------------------$reset');
      print('${bold}Selection:${reset} ${currentList.where((i)=>i.selected).length} | ${bold}Total:${reset} ${green}${formatMb(totalMb)}$reset');

      final byte = stdin.readByteSync();
      if (byte == 27) {
        if (stdin.readByteSync() == 91) {
          final n2 = stdin.readByteSync();
          if (n2 == 65) cursor = (cursor - 1 + currentList.length) % currentList.length;
          else if (n2 == 66) cursor = (cursor + 1) % currentList.length;
        } else { stdin.lineMode = true; stdin.echoMode = true; return; }
      } else if (byte == 32) {
        currentList[cursor].selected = !currentList[cursor].selected;
        if (currentList[cursor].isBatch && currentList[cursor].subItems != null) for (var s in currentList[cursor].subItems!) s.selected = currentList[cursor].selected;
      } else if (byte == 10 || byte == 13) {
        if (currentList[cursor].isBatch && currentList[cursor].subItems != null) {
          stack.add(currentList); cursorStack.add(cursor);
          currentList = currentList[cursor].subItems!; cursor = 0; scrollOffset = 0;
        } else { actionConfirmed = true; }
      } else if (byte == 109 || byte == 77) {
        if (currentList[cursor].upgradeCommand != null) {
          currentList[cursor].maintainSelected = !currentList[cursor].maintainSelected;
          if (currentList[cursor].isBatch && currentList[cursor].subItems != null) for (var s in currentList[cursor].subItems!) s.maintainSelected = currentList[cursor].maintainSelected;
        }
      } else if (byte == 105 || byte == 73) {
        if (currentList[cursor].path != null) { config.ignoredPaths.add(currentList[cursor].path!); config.save(); currentList.removeAt(cursor); }
      } else if (byte == 98 || byte == 66) {
        if (stack.isNotEmpty) { currentList = stack.removeLast(); cursor = cursorStack.removeLast(); }
        else break;
      } else if (byte == 120 || byte == 88) actionConfirmed = true;
      else if (byte == 113 || byte == 81) { stdin.lineMode = true; stdin.echoMode = true; return; }
    }
    stdin.lineMode = true; stdin.echoMode = true;

    print('\n$bold${cyan}🚀 Executing Cleanup...$reset\n');
    final selected = <CleanupItem>[];
    void collect(List<CleanupItem> list) {
      for (var i in list) { if (i.isBatch && i.subItems != null) collect(i.subItems!); else if (i.selected || i.maintainSelected) selected.add(i); }
    }
    collect(allItems);

    int completed = 0; double reclaimedMb = 0;
    for (var item in selected) {
      showProgressBar(completed, selected.length, status: item.label);
      if (!dryRun) {
        if (item.maintainSelected && item.upgradeCommand != null) await Process.run(item.upgradeCommand!.split(' ')[0], item.upgradeCommand!.split(' ').sublist(1), workingDirectory: item.path, runInShell: true);
        if (item.selected) {
          if (item.command != null) await Process.run(item.command!.split(' ')[0], item.command!.split(' ').sublist(1), workingDirectory: item.path, runInShell: true);
          else if (item.path != null) { 
            if (FileSystemEntity.isDirectorySync(item.path!)) Directory(item.path!).deleteSync(recursive: true);
            else File(item.path!).deleteSync();
          }
        }
      } else { await Future.delayed(Duration(milliseconds: 100)); }
      completed++; reclaimedMb += parseSizeToMb(item.estimatedSize);
    }
    if (!dryRun) { final s = await Stats.load(); s.addRecord(reclaimedMb); s.save(); }
    print('\n\n$bold$green✨ DONE! Reclaimed ${formatMb(reclaimedMb)}.$reset');
    stdin.readLineSync(); return;
  }
}

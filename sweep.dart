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

Future<String?> getDirSize(String path) async {
  try {
    if (Platform.isWindows) {
      final result = await Process.run('powershell', ['-Command', '(Get-ChildItem -Path "$path" -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB']);
      if (result.exitCode == 0) {
        final val = double.tryParse(result.stdout.toString().trim());
        if (val != null) return '${val.toStringAsFixed(1)}M';
      }
    } else {
      final result = await Process.run('du', ['-sh', path], runInShell: true);
      if (result.exitCode == 0) return result.stdout.toString().split('\t').first.trim();
    }
  } catch (_) {}
  return null;
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
  if (stats.history.isEmpty) {
    print('${gray}No cleanup history found yet. Run a cleanup to see stats!$reset');
    return;
  }
  
  double totalSaved = 0;
  stats.history.forEach((date, mb) {
    totalSaved += mb;
    final barLength = (mb / 1024 * 10).clamp(1, 40).toInt(); // ~10 chars per GB, max 40
    final bar = '$green' + ('█' * barLength) + '$reset';
    print(' $bold$date$reset | ${formatMb(mb).padLeft(10)} | $bar');
  });
  print('${blue}-----------------------------------------------------------------------$reset');
  print(' $bold${white}Lifetime Space Reclaimed: ${green}${formatMb(totalSaved)}$reset\n');
}

Future<void> updateSweep() async {
  print('\n$bold${blue}-----------------------------------------------------------------------$reset');
  print(' $bold${white}🔄 Updating Sweep CLI to latest version...$reset');
  print('$bold${blue}-----------------------------------------------------------------------$reset');
  try {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse('https://raw.githubusercontent.com/abdulrasol/sweep-cli/main/sweep.dart'));
    final response = await request.close();
    if (response.statusCode != 200) throw Exception('Failed to download update. Status: ${response.statusCode}');
    final contents = await response.transform(utf8.decoder).join();
    
    final tempScript = File('${Directory.systemTemp.path}/sweep_update.dart');
    tempScript.writeAsStringSync(contents);

    print('${gray}Compiling new version...$reset');
    final binaryName = Platform.isWindows ? 'sweep.exe' : 'sweep';
    final compileRes = await Process.run('dart', ['compile', 'exe', tempScript.path, '-o', binaryName]);
    if (compileRes.exitCode != 0) { print('${red}❌ Compilation failed:$reset ${compileRes.stderr}'); return; }
    
    if (Platform.isMacOS || Platform.isLinux) {
      print('${yellow}Please enter your Mac/Linux password if prompted for sudo.$reset');
      final moveRes = await Process.run('sudo', ['mv', binaryName, '/usr/local/bin/sweep'], runInShell: true);
      if (moveRes.exitCode == 0) print('\n$bold$green✅ Update Successful! Run `sweep` to enjoy the new features.$reset');
      else print('${red}❌ Failed to move binary to /usr/local/bin. Do it manually.$reset');
    } else {
      print('\n$bold$green✅ Update Compiled!$reset');
      print('Replace your existing $binaryName with the new one in the current directory.');
    }
  } catch (e) {
    print('${red}❌ Update failed: $e$reset');
  }
}

void loadCustomFrameworks(List<Framework> frameworks) {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  final file = File('$home/.sweep_rules.json');
  if (!file.existsSync()) {
    try {
      file.writeAsStringSync('[\n  {\n    "name": "Example Framework",\n    "markers": ["example.marker"],\n    "cleanupLabel": "example clean",\n    "command": "echo cleaning",\n    "foldersToNuke": ["temp_cache"]\n  }\n]\n');
    } catch (_) {}
    return;
  }
  try {
    final List<dynamic> json = jsonDecode(file.readAsStringSync());
    int count = 0;
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
      count++;
    }
    if (count > 0) print('${green}Loaded $count custom framework rules from ~/.sweep_rules.json$reset');
  } catch (e) {
    print('${red}Warning: Failed to parse custom rules from ~/.sweep_rules.json: $e$reset');
  }
}

Future<void> runInstallation() async {
  final binaryName = Platform.isWindows ? 'sweep.exe' : 'sweep';
  print('\n$bold${blue}-----------------------------------------------------------------------$reset');
  print(' $bold${white}🚀 Installing "sweep" as a Global CLI Tool$reset');
  print('$bold${blue}-----------------------------------------------------------------------$reset');
  final compileRes = await Process.run('dart', ['compile', 'exe', Platform.script.toFilePath(), '-o', binaryName]);
  if (compileRes.exitCode != 0) { print('${red}❌ Compilation failed:$reset ${compileRes.stderr}'); return; }
  
  if (Platform.isMacOS || Platform.isLinux) {
    final moveRes = await Process.run('sudo', ['mv', binaryName, '/usr/local/bin/sweep'], runInShell: true);
    if (moveRes.exitCode == 0) print('\n$bold$green✅ Installation Successful!$reset');
    else print('${red}❌ Failed to move binary to /usr/local/bin. Try manually.$reset');
  } else if (Platform.isWindows) {
    print('\n$bold$green✅ Compilation Successful!$reset');
    print('Move $binaryName to a folder in your PATH (e.g., C:\\Windows\\system32).');
  }
}

void main(List<String> args) async {
  if (args.contains('--install')) { await runInstallation(); return; }
  if (args.contains('--update')) { await updateSweep(); return; }
  if (args.contains('--stats')) { await showDashboard(); return; }

  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  final config = await Config.load();

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

  loadCustomFrameworks(frameworks);

  while (true) {
    stdout.write('\x1B[2J\x1B[H');
    print('${blue}-----------------------------------------------------------------------$reset');
    print(' $bold${white}🧹 Sweep CLI: Master Maintenance Suite v2.0$reset');
    print(' ${green}Powered and built by Abdulrasol with love of AI$reset');
    print('${blue}-----------------------------------------------------------------------$reset');
    print(' ${gray}Flags: --install (Global), --update (Upgrade), --stats (Dashboard)$reset');
    print('${blue}-----------------------------------------------------------------------$reset');
    stdout.write('$bold${white}Enter directory to scan [default: ${config.lastPath}]: $reset');
    String input = stdin.readLineSync()?.trim() ?? '';
    if (input.isNotEmpty) config.lastPath = input;
    final scanDir = Directory(config.lastPath);
    if (!scanDir.existsSync()) { print('${red}Error: Directory "${config.lastPath}" does not exist.$reset'); stdin.readLineSync(); continue; }
    config.save();

    print('${gray}Performing Smart Deep Scan...$reset');
    final allItems = <CleanupItem>[];
    
    final sysMaintenance = [
      CleanupItem(label: 'Homebrew Upgrade', category: 'SYSTEM MAINTENANCE', command: 'brew update && brew upgrade'),
      CleanupItem(label: 'Docker System Prune', category: 'SYSTEM MAINTENANCE', command: 'docker system prune -f'),
      CleanupItem(label: 'NPM Global Update', category: 'SYSTEM MAINTENANCE', command: 'npm install -g npm@latest'),
    ];
    for (var item in sysMaintenance) { allItems.add(item); }

    if (Platform.isMacOS) {
      allItems.add(CleanupItem(label: 'Xcode DerivedData', category: 'GLOBAL CACHES', path: '$home/Library/Developer/Xcode/DerivedData'));
      allItems.add(CleanupItem(label: 'Xcode Tool Caches', category: 'GLOBAL CACHES', path: '$home/Library/Caches/com.apple.dt.Xcode'));
      allItems.add(CleanupItem(label: 'iOS Simulators', category: 'GLOBAL CACHES', command: 'xcrun simctl delete unavailable'));
    }

    final Map<Framework, List<CleanupItem>> frameworkProjects = {};
    final List<CleanupItem> bigFileItems = [];

    try {
      final list = scanDir.listSync(recursive: true, followLinks: false);
      for (var entity in list) {
        if (config.ignoredPaths.any((p) => entity.path.startsWith(p))) continue;
        if (entity is File) {
          try {
            if (entity.lengthSync() > 100 * 1024 * 1024) {
              bigFileItems.add(CleanupItem(label: 'File: ${entity.path.split(Platform.pathSeparator).last}', category: 'BIG FILES', path: entity.path, estimatedSize: formatMb(entity.lengthSync() / (1024 * 1024))));
            }
          } catch (_) {}

          final fileName = entity.path.split(Platform.pathSeparator).last;
          for (var fw in frameworks) {
            bool matches = fw.markers.any((m) => fileName == m || fileName.endsWith(m));
            if (matches && !entity.path.contains('/.')) {
              fw.detected = true;
              final pPath = entity.parent.path;
              if (frameworkProjects[fw]?.any((i) => i.path == pPath) ?? false) continue;
              final lastMod = entity.lastModifiedSync();
              frameworkProjects.putIfAbsent(fw, () => []).add(CleanupItem(label: pPath.split(Platform.pathSeparator).last, category: '${fw.name.toUpperCase()} PROJECTS', path: pPath, command: fw.command, upgradeCommand: fw.upgradeCommand, lastModified: lastMod, note: 'Last touched: ${lastMod.day}/${lastMod.month}/${lastMod.year}'));
            }
          }
        }
      }
    } catch (_) {}

    for (var fw in frameworks.where((f) => f.detected)) {
      for (var cache in fw.globalCaches) { if (cache.path == null || Directory(cache.path!).existsSync()) allItems.add(cache); }
      final projects = frameworkProjects[fw]!;
      allItems.add(CleanupItem(label: 'Batch: ${fw.cleanupLabel} (${projects.length} projects)', category: '${fw.name.toUpperCase()} PROJECTS', isBatch: true, command: fw.command, upgradeCommand: fw.upgradeCommand, subItems: projects, note: 'Press [Enter] to drill-down.')..selected = true);
    }
    allItems.addAll(bigFileItems);

    print('${gray}Estimating space & Performing Health Audit...$reset');
    await Future.wait(allItems.map((item) async {
      if (item.category == 'BIG FILES') return;
      if (item.path != null) item.estimatedSize = await getDirSize(item.path!);
      else if (item.isBatch && item.subItems != null) {
        double total = 0;
        final res = await Future.wait(item.subItems!.map((p) => getDirSize(p.path!)));
        for (var s in res) total += parseSizeToMb(s);
        if (total > 0) item.estimatedSize = formatMb(total);
      }
    }));

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
      print(' ${bold}I$reset Ignore | ${bold}D$reset Dry Run | ${bold}X/Enter$reset Execute | ${bold}B$reset Back | ${bold}Q/ESC$reset Exit');
      print('${blue}-----------------------------------------------------------------------$reset');
      if (cursor < scrollOffset) scrollOffset = cursor;
      if (cursor >= scrollOffset + 12) scrollOffset = cursor - 12 + 1;
      double totalMb = 0; String? lastCat;
      for (var i = 0; i < currentList.length; i++) {
        final item = currentList[i];
        if (item.selected) totalMb += parseSizeToMb(item.estimatedSize);
        if (i < scrollOffset || i >= scrollOffset + 12) continue;
        if (item.category != lastCat) { print(' $bold$blue[ ${item.category} ]$reset'); lastCat = item.category; }
        final isCursor = cursor == i;
        print('${isCursor ? "$yellow> $reset" : "  "}${item.selected ? "$green[x]$reset" : "[ ]"} ${item.isStale ? red + "[STALE] " + reset : ""}${item.maintainSelected ? yellow + "[FIX] " + reset : ""}${item.label} ${item.estimatedSize != null ? "$gray(${item.estimatedSize})$reset" : ""}');
        if (isCursor && item.note != null) print('     ${blue}ℹ️  ${item.note}$reset');
      }
      print('${blue}-----------------------------------------------------------------------$reset');
      print('${bold}Selection:${reset} ${currentList.where((i)=>i.selected).length} items | ${bold}Total:${reset} ${green}${formatMb(totalMb)}$reset');

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
        } else {
          final anySelected = allItems.any((i) => i.selected || i.maintainSelected || (i.subItems?.any((s) => s.selected || s.maintainSelected) ?? false));
          if (anySelected) actionConfirmed = true;
          else currentList[cursor].selected = !currentList[cursor].selected;
        }
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
      } else if (byte == 120 || byte == 88) {
        actionConfirmed = true;
      } else if (byte == 113 || byte == 81) { stdin.lineMode = true; stdin.echoMode = true; return; }
    }
    stdin.lineMode = true; stdin.echoMode = true;

    if (!actionConfirmed) continue;

    print('\n$bold${cyan}🚀 Executing Cleanup...$reset\n');
    final selected = <CleanupItem>[];
    void collect(List<CleanupItem> list) {
      for (var i in list) {
        if (i.isBatch && i.subItems != null) collect(i.subItems!);
        else if (i.selected || i.maintainSelected) selected.add(i);
      }
    }
    collect(allItems);

    int completed = 0; double reclaimedMb = 0;
    for (var item in selected) {
      showProgressBar(completed, selected.length, status: item.label);
      if (!dryRun) {
        if (item.maintainSelected && item.upgradeCommand != null) await Process.run(item.upgradeCommand!.split(' ')[0], item.upgradeCommand!.split(' ').sublist(1), workingDirectory: item.path, runInShell: true);
        if (item.selected) {
          if (item.command != null) {
            final cmd = item.category == 'GIT HYGIENE' ? 'bash' : item.command!;
            final args = item.category == 'GIT HYGIENE' ? ['-c', item.command!] : <String>[];
            await Process.run(cmd, args, workingDirectory: item.category.startsWith('BIG FILES') ? null : item.path, runInShell: true);
            if (item.category.startsWith('BIG FILES')) { try { File(item.path!).deleteSync(); } catch (_) {} }
          } else if (item.path != null) { 
            if (FileSystemEntity.isDirectorySync(item.path!)) Directory(item.path!).deleteSync(recursive: true);
            else File(item.path!).deleteSync();
          }
        }
      } else { await Future.delayed(Duration(milliseconds: 100)); }
      completed++; reclaimedMb += parseSizeToMb(item.estimatedSize);
    }
    
    // Save Stats
    if (!dryRun) {
      final stats = await Stats.load();
      stats.addRecord(reclaimedMb);
      stats.save();
    }

    print('\n\n$bold$green✨ DONE! Total reclaimed ${formatMb(reclaimedMb)}.$reset');
    print('${gray}Run "sweep --stats" to view your lifetime savings dashboard.$reset');
    stdin.readLineSync(); return;
  }
}

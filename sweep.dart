import 'dart:io';
import 'dart:async';

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

  Framework({
    required this.name,
    required this.markers,
    required this.cleanupLabel,
    this.command,
    this.auditCommand,
    this.upgradeCommand,
    required this.foldersToNuke,
    this.globalCaches = const [],
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
const String reset = '\x1B[0m';
const String bold = '\x1B[1m';
const String red = '\x1B[31m';
const String green = '\x1B[32m';
const String yellow = '\x1B[33m';
const String blue = '\x1B[34m';
const String cyan = '\x1B[36m';
const String white = '\x1B[37m';
const String gray = '\x1B[90m';

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
    final result = await Process.run('du', ['-sh', path], runInShell: true);
    if (result.exitCode == 0) {
      return result.stdout.toString().split('\t').first.trim();
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
    final file = File('${Platform.environment['HOME']}/.flutter_cleaner_rc');
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
    final file = File('${Platform.environment['HOME']}/.flutter_cleaner_rc');
    final buffer = StringBuffer()..writeln(lastPath);
    for (var p in ignoredPaths) buffer.writeln(p);
    file.writeAsStringSync(buffer.toString());
  }
}

Future<void> runInstallation() async {
  print('\n$bold${blue}-----------------------------------------------------------------------$reset');
  print(' $bold${white}🚀 Installing "dev-clean" as a Global CLI Tool$reset');
  print('$bold${blue}-----------------------------------------------------------------------$reset');
  final compileRes = await Process.run('dart', ['compile', 'exe', Platform.script.toFilePath(), '-o', 'dev-clean']);
  if (compileRes.exitCode != 0) { print('${red}❌ Compilation failed:$reset ${compileRes.stderr}'); return; }
  final moveRes = await Process.run('sudo', ['mv', 'dev-clean', '/usr/local/bin/dev-clean'], runInShell: true);
  if (moveRes.exitCode == 0) print('\n$bold$green✅ Installation Successful!$reset');
  else print('${red}❌ Failed to install binary.$reset');
}

void main(List<String> args) async {
  if (args.contains('--install')) { await runInstallation(); return; }

  final home = Platform.environment['HOME'] ?? '';
  final config = await Config.load();

  final frameworks = [
    Framework(name: 'Android Native', markers: ['build.gradle', 'build.gradle.kts'], cleanupLabel: 'Android Build', foldersToNuke: ['build', 'app/build', '.gradle'],
      globalCaches: [CleanupItem(label: 'Gradle Cache', category: 'ANDROID CACHES', path: '$home/.gradle/caches')]),
    Framework(name: 'Flutter', markers: ['pubspec.yaml'], cleanupLabel: 'flutter clean', command: 'flutter clean', auditCommand: 'flutter pub outdated', upgradeCommand: 'flutter pub upgrade', foldersToNuke: ['android/.gradle', '.dart_tool', 'ios/Pods'],
      globalCaches: [CleanupItem(label: 'Dart Pub Cache', category: 'FLUTTER CACHES', path: '$home/.pub-cache'), CleanupItem(label: 'CocoaPods Cache', category: 'FLUTTER CACHES', path: '$home/Library/Caches/CocoaPods')]),
    Framework(name: 'Node / React', markers: ['package.json'], cleanupLabel: 'node_modules', auditCommand: 'npm audit', upgradeCommand: 'npm update', foldersToNuke: ['node_modules', 'dist', '.next'],
      globalCaches: [CleanupItem(label: 'NPM Cache', category: 'NODE CACHES', path: '$home/.npm/_cacache')]),
    Framework(name: 'Python', markers: ['requirements.txt'], cleanupLabel: 'venv', foldersToNuke: ['venv', '.venv', '__pycache__']),
    Framework(name: 'Rust', markers: ['Cargo.toml'], cleanupLabel: 'cargo clean', command: 'cargo clean', foldersToNuke: ['target']),
  ];

  while (true) {
    stdout.write('\x1B[2J\x1B[H');
    print('${blue}-----------------------------------------------------------------------$reset');
    print(' $bold${white}🧹 Mac Developer Smart Health & Cleanup Suite$reset');
    print(' ${green}Powered and built by Abdulrasol with love of AI$reset');
    print('${blue}-----------------------------------------------------------------------$reset');
    stdout.write('$bold${white}Enter directory to scan [default: ${config.lastPath}]: $reset');
    String input = stdin.readLineSync()?.trim() ?? '';
    if (input.isNotEmpty) config.lastPath = input;
    final scanDir = Directory(config.lastPath);
    if (!scanDir.existsSync()) { print('${red}Error: Directory "${config.lastPath}" does not exist.$reset'); stdin.readLineSync(); continue; }
    config.save();

    print('${gray}Performing Smart Deep Scan...$reset');
    final allItems = <CleanupItem>[];
    
    // System Maintenance items
    final maintenanceItems = [
      CleanupItem(label: 'Homebrew Upgrade', category: 'SYSTEM MAINTENANCE', command: 'brew update && brew upgrade', note: 'Updates all installed Homebrew formulae.'),
      CleanupItem(label: 'NPM Global Update', category: 'SYSTEM MAINTENANCE', command: 'npm install -g npm@latest', note: 'Updates NPM to the latest global version.'),
      CleanupItem(label: 'System Docker Prune', category: 'SYSTEM MAINTENANCE', command: 'docker system prune -af', note: 'Deep prune of all unused Docker objects.'),
    ];
    allItems.addAll(maintenanceItems);
    allItems.add(CleanupItem(label: 'Xcode DerivedData', category: 'GLOBAL CACHES', path: '$home/Library/Developer/Xcode/DerivedData'));

    final Map<Framework, List<CleanupItem>> frameworkProjects = {};
    final List<Map<String, String>> auditReports = [];
    final List<CleanupItem> bigFileItems = [];

    try {
      final list = scanDir.listSync(recursive: true, followLinks: false);
      for (var entity in list) {
        if (config.ignoredPaths.any((p) => entity.path.startsWith(p))) continue;
        if (entity is File) {
          try {
            if (entity.lengthSync() > 100 * 1024 * 1024) {
              bigFileItems.add(CleanupItem(label: 'File: ${entity.path.split("/").last}', category: 'BIG FILES', path: entity.path, estimatedSize: formatMb(entity.lengthSync() / (1024 * 1024))));
            }
          } catch (_) {}

          final fileName = entity.path.split(Platform.pathSeparator).last;
          for (var fw in frameworks) {
            if (fw.markers.any((m) => fileName == m || fileName.endsWith(m)) && !entity.path.contains('/.')) {
              fw.detected = true;
              final pPath = entity.parent.path;
              if (frameworkProjects[fw]?.any((i) => i.path == pPath) ?? false) continue;
              
              final lastMod = entity.lastModifiedSync();
              final pItem = CleanupItem(
                label: pPath.split("/").last,
                category: '${fw.name.toUpperCase()} PROJECTS',
                path: pPath,
                command: fw.command,
                upgradeCommand: fw.upgradeCommand,
                lastModified: lastMod,
                note: 'Last touched: ${lastMod.day}/${lastMod.month}/${lastMod.year}',
              );
              frameworkProjects.putIfAbsent(fw, () => []).add(pItem);
            }
          }
        }
      }
    } catch (_) {}

    for (var fw in frameworks.where((f) => f.detected)) {
      allItems.addAll(fw.globalCaches);
      final projects = frameworkProjects[fw]!;
      allItems.add(CleanupItem(
        label: 'Batch: ${fw.cleanupLabel} (${projects.length} projects)',
        category: '${fw.name.toUpperCase()} PROJECTS',
        isBatch: true,
        command: fw.command,
        upgradeCommand: fw.upgradeCommand,
        subItems: projects,
        note: 'Press [Enter] to drill-down into individual projects.',
      )..selected = true);
    }
    allItems.addAll(bigFileItems);

    print('${gray}Estimating space & Health Audit...$reset');
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
    while (true) {
      stdout.write('\x1B[2J\x1B[H');
      print('${blue}-----------------------------------------------------------------------$reset');
      print(' $bold${white}Mac Developer Master Maintenance Console$reset');
      print('${blue}-----------------------------------------------------------------------$reset');
      print(' ${bold}↑/↓$reset Nav | ${bold}Space$reset Toggle | ${bold}Enter$reset Open/Drill | ${bold}M$reset Maintenance');
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
        final isCursor = cursor == i;
        final stale = item.isStale ? '$red[STALE]$reset ' : '';
        final mMarker = item.maintainSelected ? '$yellow[FIX]$reset ' : '';
        print('${isCursor ? "$yellow> $reset" : "  "}${item.selected ? "$green[x]$reset" : "[ ]"} $stale$mMarker${item.label} ${item.estimatedSize != null ? "$gray(${item.estimatedSize})$reset" : ""}');
        if (isCursor && item.note != null) print('     ${blue}ℹ️  ${item.note}$reset');
      }
      print('${blue}-----------------------------------------------------------------------$reset');
      print('${bold}Selection:${reset} ${currentList.where((i)=>i.selected).length} items | ${bold}Total:${reset} ${green}${formatMb(totalMb)}$reset');

      final byte = stdin.readByteSync();
      if (byte == 27) { // ESC or Arrow Sequence
        // Arrow keys are usually 3-byte sequences: 27 91 65/66
        // Standalone ESC is just 27.
        // We use a small non-blocking check to see if more bytes are waiting.
        if (stdin.readByteSync() == 91) { // '['
          final n2 = stdin.readByteSync();
          if (n2 == 65) cursor = (cursor - 1 + currentList.length) % currentList.length;
          else if (n2 == 66) cursor = (cursor + 1) % currentList.length;
        } else {
          // If 27 was pressed but no '[' followed immediately, treat as ESC.
          stdin.lineMode = true; stdin.echoMode = true;
          print('${yellow}Exited via ESC.$reset'); return;
        }
      } else if (byte == 113 || byte == 81) { // Q or q
        stdin.lineMode = true; stdin.echoMode = true;
        print('${yellow}Exited via Q.$reset'); return;
      } else if (byte == 32) {
        currentList[cursor].selected = !currentList[cursor].selected;
        if (currentList[cursor].isBatch && currentList[cursor].subItems != null) {
          for (var s in currentList[cursor].subItems!) s.selected = currentList[cursor].selected;
        }
      } else if (byte == 10 || byte == 13) {
        if (currentList[cursor].isBatch && currentList[cursor].subItems != null) {
          stack.add(currentList); cursorStack.add(cursor);
          currentList = currentList[cursor].subItems!; cursor = 0; scrollOffset = 0;
        }
      } else if (byte == 109 || byte == 77) {
        if (currentList[cursor].upgradeCommand != null) {
          currentList[cursor].maintainSelected = !currentList[cursor].maintainSelected;
          if (currentList[cursor].isBatch && currentList[cursor].subItems != null) {
            for (var s in currentList[cursor].subItems!) s.maintainSelected = currentList[cursor].maintainSelected;
          }
        }
      } else if (byte == 105 || byte == 73) {
        if (currentList[cursor].path != null) { config.ignoredPaths.add(currentList[cursor].path!); config.save(); currentList.removeAt(cursor); }
      } else if (byte == 98 || byte == 66) {
        if (stack.isNotEmpty) { currentList = stack.removeLast(); cursor = cursorStack.removeLast(); }
        else break;
      } else if (byte == 120 || byte == 88) { // X to Execute
        final allSelected = <CleanupItem>[];
        void collect(List<CleanupItem> list) {
          for (var i in list) {
            if (i.isBatch && i.subItems != null) collect(i.subItems!);
            else if (i.selected || i.maintainSelected) allSelected.add(i);
          }
        }
        collect(allItems);
        if (allSelected.isEmpty) continue;

        print('\n$bold${cyan}🚀 Ultimate Maintenance Start...$reset\n');
        int completed = 0; double reclaimedMb = 0;
        for (var item in allSelected) {
          showProgressBar(completed, allSelected.length, status: item.label);
          if (!dryRun) {
            if (item.maintainSelected && item.upgradeCommand != null) await Process.run(item.upgradeCommand!.split(' ')[0], item.upgradeCommand!.split(' ').sublist(1), workingDirectory: item.path, runInShell: true);
            if (item.selected) {
              if (item.command != null) await Process.run(item.command!.split(' ')[0], item.command!.split(' ').sublist(1), workingDirectory: item.path, runInShell: true);
              else if (item.path != null) { final d = Directory(item.path!); if (d.existsSync()) d.deleteSync(recursive: true); }
            }
          } else { await Future.delayed(Duration(milliseconds: 100)); }
          completed++; reclaimedMb += parseSizeToMb(item.estimatedSize);
        }
        print('\n\n$bold$green✨ DONE! Reclaimed ${formatMb(reclaimedMb)}.$reset');
        stdin.readLineSync(); return;
      } else if (byte == 113 || byte == 81) return;
    }
  }
}

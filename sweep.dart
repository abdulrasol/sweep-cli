import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:dart_console/dart_console.dart';
import 'sweep_desktop/lib/sweep_core.dart';

final console = Console();

void showProgressBar(int current, int total, {String? status}) {
  const int width = 30;
  double percent = total > 0 ? current / total : 1.0;
  if (percent > 1.0) percent = 1.0;
  int completedWidth = (percent * width).round();
  int remainingWidth = width - completedWidth;

  String bar = '\x1b[36m[\x1b[0m' + '=' * completedWidth + '>' + ' ' * (remainingWidth > 0 ? remainingWidth - 1 : 0) + '\x1b[36m]\x1b[0m';
  stdout.write('\r$bar ${(percent * 100).toStringAsFixed(1)}% ${status ?? ''}');
}

// Helper to wrap strings in ANSI colors
String color(String text, ConsoleColor c, {bool isBold = false}) {
  String result = c.ansiSetForegroundColorSequence;
  if (isBold) result += '\x1B[1m';
  result += text + '\x1B[0m';
  return result;
}

Future<void> showDashboard() async {
  final stats = await Stats.load();
  console.writeLine('\n' + color('-----------------------------------------------------------------------', ConsoleColor.blue, isBold: true));
  console.writeLine(' ' + color('📊 Sweep Savings Dashboard', ConsoleColor.white, isBold: true));
  console.writeLine(color('-----------------------------------------------------------------------', ConsoleColor.blue, isBold: true));
  
  if (stats.history.isEmpty) {
    console.writeLine(color(' No history found.', ConsoleColor.white));
    return;
  }

  stats.history.forEach((date, mb) {
    final barCount = (mb / 1024 * 10).clamp(1, 40).toInt();
    final bar = color('█' * barCount, ConsoleColor.green);
    console.writeLine(' ${color(date, ConsoleColor.white, isBold: true)} | ${SweepEngine.formatMb(mb).padLeft(10)} | $bar');
  });

  final total = stats.history.values.fold(0.0, (a, b) => a + b);
  console.writeLine('\n Lifetime Reclaimed: ${color(SweepEngine.formatMb(total), ConsoleColor.green)}\n');
}

Future<void> showHelp() async {
  console.writeLine('\n' + color('-----------------------------------------------------------------------', ConsoleColor.blue, isBold: true));
  console.writeLine(' ' + color('📖 Sweep CLI: Help & Usage Guide', ConsoleColor.white, isBold: true));
  console.writeLine(color('-----------------------------------------------------------------------', ConsoleColor.blue, isBold: true));
  console.writeLine(' ${color('Flags:', ConsoleColor.cyan, isBold: true)}');
  console.writeLine('   ${color('--install', ConsoleColor.yellow)}         : Installs sweep as a global binary.');
  console.writeLine('   ${color('--uninstall', ConsoleColor.yellow)}       : Removes the global sweep binary.');
  console.writeLine('   ${color('--build-desktop', ConsoleColor.yellow)}   : Compiles the Flutter Desktop application.');
  console.writeLine('   ${color('--install-desktop', ConsoleColor.yellow)} : Builds and installs the Desktop app to your system.');
  console.writeLine('   ${color('--update', ConsoleColor.yellow)}          : Automatically updates to the latest version.');
  console.writeLine('   ${color('--stats', ConsoleColor.yellow)}           : Views your lifetime storage savings dashboard.');
  console.writeLine('   ${color('--doctor', ConsoleColor.yellow)}          : Runs a health check on your dev environment.');
  console.writeLine('   ${color('-h, --help', ConsoleColor.yellow)}        : Shows this help guide.');
  console.writeLine('');
  console.writeLine(' ${color('Keyboard Shortcuts (Inside Console):', ConsoleColor.cyan, isBold: true)}');
  console.writeLine('   ${color('Arrows ↑/↓', ConsoleColor.white, isBold: true)}  : Navigate the list');
  console.writeLine('   ${color('Space', ConsoleColor.white, isBold: true)}      : Toggle item for cleanup');
  console.writeLine('   ${color('Enter', ConsoleColor.white, isBold: true)}      : Open a batch sub-menu OR Run Cleanup (if selected)');
  console.writeLine('   ${color('M', ConsoleColor.white, isBold: true)}          : Toggle Maintenance [FIX] (Auto-upgrade deps)');
  console.writeLine('   ${color('A', ConsoleColor.white, isBold: true)}          : Toggle Archive (Zip and delete)');
  console.writeLine('   ${color('I', ConsoleColor.white, isBold: true)}          : Add project to permanent Ignore list');
  console.writeLine('   ${color('D', ConsoleColor.white, isBold: true)}          : Toggle Dry Run mode (Simulation)');
  console.writeLine('   ${color('1, 2, 3', ConsoleColor.white, isBold: true)}    : Presets (1: Safe, 2: Deep, 3: Stale Nuke)');
  console.writeLine('   ${color('X', ConsoleColor.white, isBold: true)}          : Execute all selected tasks');
  console.writeLine('   ${color('B', ConsoleColor.white, isBold: true)}          : Go back from a sub-menu');
  console.writeLine('   ${color('Q / ESC', ConsoleColor.white, isBold: true)}    : Exit the tool');
  console.writeLine(color('-----------------------------------------------------------------------', ConsoleColor.blue, isBold: true) + '\n');
}

Future<void> runDoctor() async {
  console.writeLine('\n' + color('-----------------------------------------------------------------------', ConsoleColor.blue, isBold: true));
  console.writeLine(' ' + color('🩺 Sweep Environment Doctor', ConsoleColor.white, isBold: true));
  console.writeLine(color('-----------------------------------------------------------------------', ConsoleColor.blue, isBold: true));
  
  final checks = {
    'Dart': 'dart --version',
    'Flutter': 'flutter --version',
    'Node.js': 'node --version',
    'NPM': 'npm --version',
    'Python': 'python3 --version',
    'Rust': 'rustc --version',
    'Go': 'go version',
    'Docker': 'docker --version',
    'Homebrew': 'brew --version',
    'Git': 'git --version'
  };

  for (var entry in checks.entries) {
    stdout.write('${entry.key.padRight(12)}: ');
    try {
      final res = await Process.run(entry.value.split(' ')[0], entry.value.split(' ').sublist(1), runInShell: true);
      if (res.exitCode == 0) {
        console.writeLine(color('✅ Found (${res.stdout.toString().split('\n').first.trim()})', ConsoleColor.green));
      } else {
        console.writeLine(color('❌ Error (Code ${res.exitCode})', ConsoleColor.red));
      }
    } catch (_) {
      console.writeLine(color('⚠️  Not found in PATH', ConsoleColor.yellow));
    }
  }
}

Future<void> runInstallation() async {
  final binaryName = Platform.isWindows ? 'sweep.exe' : 'sweep';
  console.writeLine('Compiling to $binaryName...');
  final res = await Process.run('dart', ['compile', 'exe', Platform.script.toFilePath(), '-o', binaryName]);
  if (res.exitCode == 0) {
    if (Platform.isWindows) {
      console.writeLine(color('Success! Add the folder containing $binaryName to your PATH.', ConsoleColor.green));
    } else {
      await Process.run('sudo', ['mv', binaryName, '/usr/local/bin/sweep'], runInShell: true);
      console.writeLine(color('Success! Run using "sweep".', ConsoleColor.green));
    }
  } else {
    console.writeLine(color('Failed: ${res.stderr}', ConsoleColor.red));
  }
}

Future<void> runUninstall() async {
  if (Platform.isWindows) {
    console.writeLine('Please manually delete sweep.exe from your PATH folder.');
  } else {
    final res = await Process.run('sudo', ['rm', '/usr/local/bin/sweep'], runInShell: true);
    if (res.exitCode == 0) {
      console.writeLine(color('Success! Sweep uninstalled.', ConsoleColor.green));
    } else {
      console.writeLine(color('Failed: ${res.stderr}', ConsoleColor.red));
    }
  }
}

Future<bool> checkFlutterInstalled() async {
  try {
    final res = await Process.run('flutter', ['--version']);
    return res.exitCode == 0;
  } catch (_) {
    return false;
  }
}

Future<bool> promptInstallFlutter() async {
  console.writeLine('\n' + color('⚠️ Flutter SDK not found!', ConsoleColor.red, isBold: true));
  console.writeLine('Building the Desktop app requires the Flutter SDK.');
  stdout.write(color('Would you like to attempt automated installation? (y/n/skip): ', ConsoleColor.white, isBold: true));
  final choice = stdin.readLineSync()?.toLowerCase();
  
  if (choice == 'y') {
    console.writeLine('\n' + color('Attempting automated installation...', ConsoleColor.blue));
    if (Platform.isMacOS) {
      console.writeLine('Running: brew install --cask flutter');
      final res = await Process.run('brew', ['install', '--cask', 'flutter'], runInShell: true);
      if (res.exitCode == 0) return true;
    } else if (Platform.isLinux) {
      console.writeLine('Running: sudo snap install flutter --classic');
      final res = await Process.run('sudo', ['snap', 'install', 'flutter', '--classic'], runInShell: true);
      if (res.exitCode == 0) return true;
    } else if (Platform.isWindows) {
      console.writeLine('Running: choco install flutter');
      final res = await Process.run('choco', ['install', 'flutter'], runInShell: true);
      if (res.exitCode == 0) return true;
    }
    console.writeLine('\n' + color('⚠️ Automated install failed or platform not supported.', ConsoleColor.yellow));
    console.writeLine('Please install manually from: ${color('https://docs.flutter.dev/get-started/install', ConsoleColor.white, isBold: true)}');
  }
  return false;
}

Future<void> runDesktopBuild() async {
  if (!await checkFlutterInstalled()) {
    if (!await promptInstallFlutter()) {
      console.writeLine('\n' + color('Desktop installation skipped.', ConsoleColor.yellow));
      return;
    }
  }

  console.writeLine('\n' + color('🚀 Initiating Sweep Desktop Build Sequence...', ConsoleColor.blue, isBold: true));
  final desktopDir = Directory('${Directory(Platform.script.toFilePath()).parent.path}/sweep_desktop');
  String platform = Platform.isMacOS ? 'macos' : Platform.isWindows ? 'windows' : 'linux';
  
  console.writeLine(color('Step 1/3: Resolving dependencies...', ConsoleColor.black));
  showProgressBar(1, 3, status: 'flutter pub get');
  await Process.run('flutter', ['pub', 'get'], workingDirectory: desktopDir.path, runInShell: true);
  
  console.writeLine('\n' + color('Step 2/3: Compiling native $platform bundle...', ConsoleColor.black));
  showProgressBar(2, 3, status: 'flutter build $platform');
  
  final process = await Process.start('flutter', ['build', platform], workingDirectory: desktopDir.path, runInShell: true);
  
  process.stdout.transform(utf8.decoder).listen((data) {
    if (data.trim().isNotEmpty) stdout.write('  ${color('[LOG]', ConsoleColor.black)} ${data.trim()}\n');
  });
  
  final exitCode = await process.exitCode;
  
  if (exitCode == 0) {
    console.writeLine('\n' + color('Step 3/3: Build successful!', ConsoleColor.black));
    showProgressBar(3, 3, status: 'Ready');
    console.writeLine('\n' + color('✅ Desktop build completed successfully.', ConsoleColor.green, isBold: true));
  } else {
    console.writeLine('\n' + color('❌ Build process failed (Exit Code: $exitCode).', ConsoleColor.red, isBold: true));
  }
}

Future<void> runDesktopInstall() async {
  await runDesktopBuild();
  final projectDir = Directory(Platform.script.toFilePath()).parent.path;
  final desktopDir = '$projectDir/sweep_desktop';
  
  console.writeLine('\n' + color('🚚 Finalizing Installation...', ConsoleColor.blue, isBold: true));
  
  if (Platform.isMacOS) {
    console.writeLine(color('Copying Sweep.app to /Applications...', ConsoleColor.black));
    showProgressBar(90, 100, status: 'Installing');
    await Process.run('cp', ['-R', '$desktopDir/build/macos/Build/Products/Release/Sweep.app', '/Applications/'], runInShell: true);
    console.writeLine('\n' + color('✨ Success! Sweep is now in your Applications folder.', ConsoleColor.green, isBold: true) + '\n');
  } else if (Platform.isWindows) {
    console.writeLine(color('Deploying Windows artifacts to AppData...', ConsoleColor.black));
    showProgressBar(90, 100, status: 'Installing');
    final installDir = Directory('${Platform.environment['APPDATA']}\\Sweep');
    if (!installDir.existsSync()) installDir.createSync(recursive: true);
    
    final buildDir = '$desktopDir\\build\\windows\\x64\\runner\\Release';
    await Process.run('powershell', ['Copy-Item', '-Path', '"$buildDir\\*"', '-Destination', '"${installDir.path}"', '-Recurse', '-Force']);
    
    console.writeLine('\n' + color('✨ Success! Sweep Desktop is installed in ${installDir.path}.', ConsoleColor.green, isBold: true));
    console.writeLine(color('Tip: Create a shortcut to ${installDir.path}\\sweep_desktop.exe to launch it easily.', ConsoleColor.yellow) + '\n');
  } else if (Platform.isLinux) {
    console.writeLine(color('Installing Linux bundle and menu entry...', ConsoleColor.black));
    showProgressBar(90, 100, status: 'Installing');
    final installDir = Directory('${Platform.environment['HOME']}/.local/share/sweep');
    if (!installDir.existsSync()) installDir.createSync(recursive: true);
    
    final buildDir = '$desktopDir/build/linux/x64/release/bundle';
    await Process.run('cp', ['-r', '$buildDir/.', installDir.path], runInShell: true);
    
    final desktopFile = File('${Platform.environment['HOME']}/.local/share/applications/sweep.desktop');
    desktopFile.writeAsStringSync('''[Desktop Entry]
Name=Sweep
Comment=Master Maintenance Suite for Developers
Exec=${installDir.path}/sweep_desktop
Icon=${installDir.path}/data/flutter_assets/assets/icon.png
Terminal=false
Type=Application
Categories=Utility;
''');
    
    console.writeLine('\n' + color('✨ Success! Sweep Desktop is installed and added to your application menu.', ConsoleColor.green, isBold: true) + '\n');
  }
}

Future<void> updateSweep() async {
  console.writeLine('Updating Sweep CLI...');
  try {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse('https://raw.githubusercontent.com/abdulrasol/sweep-cli/main/sweep.dart'));
    final response = await request.close();
    final contents = await response.transform(utf8.decoder).join();
    File(Platform.script.toFilePath()).writeAsStringSync(contents);
    console.writeLine('Update downloaded. Re-installing binary...');
    await runInstallation();
  } catch (e) { console.writeLine(color('Update failed: $e', ConsoleColor.red)); }
}

void main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) { await showHelp(); return; }
  if (args.contains('--install')) { await runInstallation(); return; }
  if (args.contains('--uninstall')) { await runUninstall(); return; }
  if (args.contains('--build-desktop')) { await runDesktopBuild(); return; }
  if (args.contains('--install-desktop')) { await runDesktopInstall(); return; }
  if (args.contains('--update')) { await updateSweep(); return; }
  if (args.contains('--stats')) { await showDashboard(); return; }
  if (args.contains('--doctor')) { await runDoctor(); return; }

  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  final config = await Config.load();

  while (true) {
    console.clearScreen();
    console.resetCursorPosition();
    
    console.writeLine(color('-----------------------------------------------------------------------', ConsoleColor.blue, isBold: true));
    console.writeLine(' ' + color('Sweep CLI: Legendary Master Suite v3.0', ConsoleColor.white, isBold: true));
    console.writeLine(' ' + color('Powered and built by Abdulrasol with love of AI', ConsoleColor.green));
    console.writeLine(color('-----------------------------------------------------------------------', ConsoleColor.blue, isBold: true));
    
    stdout.write(color('Enter directory to scan [default: ${config.lastPath}]: ', ConsoleColor.white, isBold: true));
    
    // Read input
    String input = stdin.readLineSync()?.trim() ?? '';
    if (input.isNotEmpty) config.lastPath = input;
    final scanDir = Directory(config.lastPath);
    if (!scanDir.existsSync()) {
      console.writeLine(color('Error: Not found.', ConsoleColor.red));
      await Future.delayed(Duration(seconds: 1));
      continue;
    }
    config.save();

    console.writeLine(color('Performing Legendary Deep Scan & Cloud Audit...', ConsoleColor.black));
    final allItems = await SweepEngine.scan(config.lastPath, config.ignoredPaths);

    List<CleanupItem> currentList = allItems;
    int cursor = 0; 
    int scrollOffset = 0; 
    bool dryRun = false;
    final stack = <List<CleanupItem>>[];
    final cursorStack = <int>[];
    
    bool actionConfirmed = false;
    
    while (!actionConfirmed) {
      console.clearScreen();
      console.resetCursorPosition();
      
      console.writeLine(color('-----------------------------------------------------------------------', ConsoleColor.blue, isBold: true));
      console.writeLine(' ' + color('Sweep Master Maintenance Console', ConsoleColor.white, isBold: true));
      console.writeLine(color('-----------------------------------------------------------------------', ConsoleColor.blue, isBold: true));
      console.writeLine(' ' + color('Presets:', ConsoleColor.white, isBold: true) + ' ' + color('1', ConsoleColor.white, isBold: true) + ' Safe | ' + color('2', ConsoleColor.white, isBold: true) + ' Deep | ' + color('3', ConsoleColor.white, isBold: true) + ' Stale Nuke');
      console.writeLine(' ' + color('A', ConsoleColor.white, isBold: true) + ' Archive | ' + color('M', ConsoleColor.white, isBold: true) + ' Fix | ' + color('I', ConsoleColor.white, isBold: true) + ' Ignore | ' + color('D', ConsoleColor.white, isBold: true) + ' Dry Run | ' + color('X', ConsoleColor.white, isBold: true) + ' Execute');
      console.writeLine(color('-----------------------------------------------------------------------', ConsoleColor.blue, isBold: true));

      if (cursor < scrollOffset) scrollOffset = cursor;
      if (cursor >= scrollOffset + 12) scrollOffset = cursor - 12 + 1;
      
      double totalMb = 0; 
      String? lastCat;
      
      for (var i = 0; i < currentList.length; i++) {
        final item = currentList[i];
        if (item.selected) totalMb += SweepEngine.parseSizeToMb(item.estimatedSize);
        if (i < scrollOffset || i >= scrollOffset + 12) continue;
        
        if (item.category != lastCat) {
          console.writeLine(' ' + color('[ ${item.category} ]', ConsoleColor.blue, isBold: true));
          lastCat = item.category;
        }
        
        final isCursor = cursor == i;
        final healthMarker = item.healthStatus == 'HEALTHY' ? color("[OK] ", ConsoleColor.green) : (item.healthStatus == 'OUTDATED DEPS' ? color("[OLD] ", ConsoleColor.yellow) : (item.healthStatus == 'VULNERABILITIES FOUND' ? color("[!!!] ", ConsoleColor.red) : ""));
        final markers = '$healthMarker${item.isDirty ? color("[DIRTY] ", ConsoleColor.red) : ""}${item.isStale ? color("[STALE] ", ConsoleColor.red) : ""}${item.maintainSelected ? color("[FIX] ", ConsoleColor.yellow) : ""}${item.archiveSelected ? color("[ZIP] ", ConsoleColor.cyan) : ""}';
        
        final pointer = isCursor ? color("> ", ConsoleColor.yellow) : "  ";
        final checkbox = item.selected ? color("[x]", ConsoleColor.green) : "[ ]";
        
        console.writeLine('$pointer$checkbox $markers${item.label} ${color('(${item.estimatedSize ?? '0M'})', ConsoleColor.black)}');
        
        if (isCursor && item.note != null) {
          console.writeLine('     ' + color('ℹ️  ${item.note}', ConsoleColor.blue));
        }
      }
      
      console.writeLine(color('-----------------------------------------------------------------------', ConsoleColor.blue, isBold: true));
      console.writeLine('${color('Selection:', ConsoleColor.white, isBold: true)} ${currentList.where((i)=>i.selected).length} | ${color('Total:', ConsoleColor.white, isBold: true)} ${color(SweepEngine.formatMb(totalMb), ConsoleColor.green)}');
      
      final sysStats = await SweepEngine.getSystemStats();
      console.writeLine('${color('Free Disk:', ConsoleColor.white)} ${color(sysStats.storageLeft, ConsoleColor.green)} | ${color('RAM:', ConsoleColor.white)} ${color(sysStats.ramUsage, ConsoleColor.yellow)} | ${color('CPU:', ConsoleColor.white)} ${color(sysStats.cpuUsage, ConsoleColor.blue)}');

      final key = console.readKey();
      
      if (key.controlChar == ControlCharacter.arrowUp) {
        cursor = (cursor - 1 + currentList.length) % currentList.length;
      } else if (key.controlChar == ControlCharacter.arrowDown) {
        cursor = (cursor + 1) % currentList.length;
      } else if (key.char == ' ') {
        currentList[cursor].selected = !currentList[cursor].selected;
        if (currentList[cursor].isBatch && currentList[cursor].subItems != null) {
          for (var s in currentList[cursor].subItems!) s.selected = currentList[cursor].selected;
        }
      } else if (key.char == '1') { // 1 - Safe
        for (var i in allItems) i.selected = i.category.contains('PROJECTS');
      } else if (key.char == '2') { // 2 - Deep
        for (var i in allItems) i.selected = true;
      } else if (key.char == '3') { // 3 - Stale Nuke
        for (var i in allItems) {
          if (i.isBatch && i.subItems != null) {
            i.selected = false;
            for (var s in i.subItems!) s.selected = s.isStale;
          } else {
            i.selected = i.isStale;
          }
        }
      } else if (key.char == 'a' || key.char == 'A') { // A - Archive
        if (currentList[cursor].path != null) currentList[cursor].archiveSelected = !currentList[cursor].archiveSelected;
      } else if (key.controlChar == ControlCharacter.enter) {
        if (currentList[cursor].isBatch && currentList[cursor].subItems != null) {
          stack.add(currentList);
          cursorStack.add(cursor);
          currentList = currentList[cursor].subItems!;
          cursor = 0;
          scrollOffset = 0;
        } else {
          actionConfirmed = true;
        }
      } else if (key.char == 'm' || key.char == 'M') {
        if (currentList[cursor].upgradeCommand != null) {
          currentList[cursor].maintainSelected = !currentList[cursor].maintainSelected;
          if (currentList[cursor].isBatch && currentList[cursor].subItems != null) {
            for (var s in currentList[cursor].subItems!) s.maintainSelected = currentList[cursor].maintainSelected;
          }
        }
      } else if (key.char == 'i' || key.char == 'I') {
        if (currentList[cursor].path != null) {
          config.ignoredPaths.add(currentList[cursor].path!);
          config.save();
          currentList.removeAt(cursor);
          if (cursor >= currentList.length) cursor = currentList.length - 1;
        }
      } else if (key.char == 'b' || key.char == 'B') {
        if (stack.isNotEmpty) {
          currentList = stack.removeLast();
          cursor = cursorStack.removeLast();
        } else {
          break;
        }
      } else if (key.char == 'x' || key.char == 'X') {
        actionConfirmed = true;
      } else if (key.char == 'q' || key.char == 'Q' || key.controlChar == ControlCharacter.escape) {
        return;
      }
    }

    if (!actionConfirmed) continue;
    
    console.writeLine('\n' + color('🚀 Executing Legendary Cleanup...', ConsoleColor.cyan, isBold: true) + '\n');
    
    final selected = <CleanupItem>[];
    void collect(List<CleanupItem> list) {
      for (var i in list) {
        if (i.isBatch && i.subItems != null) {
          collect(i.subItems!);
        } else if (i.selected || i.maintainSelected || i.archiveSelected) {
          selected.add(i);
        }
      }
    }
    collect(allItems);
    
    selected.sort((a, b) => SweepEngine.parseSizeToMb(b.estimatedSize).compareTo(SweepEngine.parseSizeToMb(a.estimatedSize)));
    
    int completed = 0; 
    double reclaimedMb = 0;
    
    for (var item in selected) {
      showProgressBar(completed, selected.length, status: item.label);
      
      if (!dryRun) {
        if (item.archiveSelected && item.path != null) {
          final archiveDir = Directory('$home/Downloads/Sweep_Archives');
          if (!archiveDir.existsSync()) archiveDir.createSync(recursive: true);
          final zipName = '${item.label}_${DateTime.now().millisecondsSinceEpoch}.zip';
          await Process.run('zip', ['-r', '${archiveDir.path}/$zipName', '.'], workingDirectory: item.path, runInShell: true);
          Directory(item.path!).deleteSync(recursive: true);
        } else {
          if (item.maintainSelected && item.upgradeCommand != null) {
            await Process.run(item.upgradeCommand!.split(' ')[0], item.upgradeCommand!.split(' ').sublist(1), workingDirectory: item.path, runInShell: true);
          }
          if (item.selected) {
            if (item.command != null) {
              await Process.run(item.command!.split(' ')[0], item.command!.split(' ').sublist(1), workingDirectory: item.path, runInShell: true);
            } else if (item.path != null) { 
              if (FileSystemEntity.isDirectorySync(item.path!)) {
                Directory(item.path!).deleteSync(recursive: true);
              } else {
                File(item.path!).delete();
              }
            }
          }
        }
      }
      
      completed++; 
      reclaimedMb += SweepEngine.parseSizeToMb(item.estimatedSize);
    }
    
    if (!dryRun) {
      final s = await Stats.load();
      s.addRecord(reclaimedMb);
      s.save();
    }
    
    console.writeLine('\n\n' + color('✨ DONE! Reclaimed ${SweepEngine.formatMb(reclaimedMb)}.', ConsoleColor.green, isBold: true));
    console.writeLine(color('Press any key to return to scan menu...', ConsoleColor.black));
    console.readKey();
  }
}

import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:system_tray/system_tray.dart';
import 'sweep_engine.dart';

// --- THEME & STATE MANAGEMENT ---

class AppTheme extends ChangeNotifier {
  final SharedPreferences? _prefs;
  bool isDark = true;
  Color accentColor = const Color(0xFFF59E0B); // Amber by default
  String accentName = 'Amber';

  final Map<String, Color> palette = {
    'Emerald': const Color(0xFF10B981),
    'Sapphire': const Color(0xFF3B82F6),
    'Amethyst': const Color(0xFF8B5CF6),
    'Crimson': const Color(0xFFEF4444),
    'Amber': const Color(0xFFF59E0B),
  };

  AppTheme(this._prefs) {
    _loadSettings();
  }

  void _loadSettings() {
    if (_prefs == null) return;
    isDark = _prefs!.getBool('isDark') ?? true;
    accentName = _prefs!.getString('accentName') ?? 'Amber';
    accentColor = palette[accentName] ?? const Color(0xFFF59E0B);
    notifyListeners();
  }

  void toggleTheme() {
    isDark = !isDark;
    _prefs?.setBool('isDark', isDark);
    notifyListeners();
  }

  void setAccent(String name) {
    accentName = name;
    accentColor = palette[name]!;
    _prefs?.setString('accentName', name);
    notifyListeners();
  }

  Color get textPrimary => isDark ? Colors.white : Colors.black;
  Color get textSecondary => isDark ? Colors.white70 : Colors.black87;
  Color get textTertiary => isDark ? Colors.white54 : Colors.black54;
  Color get textMuted => isDark ? Colors.white38 : Colors.black45;
  Color get textHint => isDark ? Colors.white24 : Colors.black26;
  Color get textDisabled => isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1);
  
  Color get cardColor => isDark ? const Color(0xFF14191F) : Colors.white;
  Color get sidebarColor => isDark ? const Color(0xFF0D1117) : const Color(0xFFE5E7EB);
  Color get bgSubtle => isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);
  Color get borderSubtle => isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1);

  ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: isDark ? const Color(0xFF0A0E12) : const Color(0xFFF3F4F6),
      colorScheme: ColorScheme.fromSeed(
        seedColor: accentColor,
        brightness: isDark ? Brightness.dark : Brightness.light,
        surface: isDark ? const Color(0xFF14191F) : Colors.white,
      ),
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF14191F) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
    );
  }
}

class AppState extends ChangeNotifier {
  final SharedPreferences? _prefs;
  String currentNav = 'Scan Scope';
  String scanPath = '';
  List<CleanupItem> detectedItems = [];
  bool isScanning = false;
  bool isCleaning = false;
  double progress = 0;
  String status = '';
  SystemStats systemStats = SystemStats.empty();
  Stats? appStats;

  final Map<String, bool> activeModules = {
    'Flutter / Dart': true,
    'Node / PNPM': true,
    'Rust / Cargo': true,
    'AI / ML Models': true,
    'Android / Kotlin': true,
    'Python / Conda': true,
    'PHP / Laravel': true,
    'NET / C#': true,
    'Unreal Engine': true,
  };

  AppState(this._prefs) {
    _loadSettings();
    _startStats();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    appStats = await Stats.load();
    notifyListeners();
  }

  void _loadSettings() {
    scanPath = _prefs?.getString('scanPath') ?? Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '/';
    final modulesJson = _prefs?.getString('activeModules');
    if (modulesJson != null) {
      try {
        final Map<String, dynamic> saved = jsonDecode(modulesJson);
        saved.forEach((key, value) {
          if (activeModules.containsKey(key)) {
            activeModules[key] = value as bool;
          }
        });
      } catch (_) {}
    }
    notifyListeners();
  }

  void _saveModules() {
    _prefs?.setString('activeModules', jsonEncode(activeModules));
  }

  void setNav(String nav) {
    currentNav = nav;
    notifyListeners();
  }

  void toggleModule(String name) {
    activeModules[name] = !(activeModules[name] ?? false);
    _saveModules();
    notifyListeners();
  }

  void toggleItemSelection(CleanupItem item) {
    item.selected = !item.selected;
    notifyListeners();
  }

  void ignoreItem(CleanupItem item) {
    detectedItems.remove(item);
    notifyListeners();
  }

  void setPath(String path) {
    scanPath = path;
    _prefs?.setString('scanPath', path);
    notifyListeners();
  }

  void _startStats() {
    SweepEngine.getSystemStats().then((s) {
      systemStats = s;
      notifyListeners();
    });
    Timer.periodic(const Duration(seconds: 5), (t) async {
      systemStats = await SweepEngine.getSystemStats();
      notifyListeners();
    });
  }

  Future<void> runScan() async {
    isScanning = true;
    currentNav = 'Review Targets';
    notifyListeners();

    try {
      final items = await SweepEngine.scan(scanPath, []);
      
      // Filter items based on active modules
      detectedItems = items.where((item) {
        if (item.category == 'GLOBAL OS CACHES' || item.category == 'GLOBAL CACHES' || item.category == 'BIG FILES (>100MB)') return true;
        
        final cat = item.category.toUpperCase();
        if (cat.contains('FLUTTER') && !(activeModules['Flutter / Dart'] ?? false)) return false;
        if (cat.contains('NODE') && !(activeModules['Node / PNPM'] ?? false)) return false;
        if (cat.contains('RUST') && !(activeModules['Rust / Cargo'] ?? false)) return false;
        if (cat.contains('ANDROID') && !(activeModules['Android / Kotlin'] ?? false)) return false;
        if (cat.contains('PYTHON') && !(activeModules['Python / Conda'] ?? false)) return false;
        if (cat.contains('PHP') && !(activeModules['PHP / Laravel'] ?? false)) return false;
        if (cat.contains('NET') && !(activeModules['NET / C#'] ?? false)) return false;
        
        return true;
      }).toList();
      
      // Parallel sizing
      await Future.wait(detectedItems.map((item) async {
        if (item.path != null) item.estimatedSize = await SweepEngine.getDirSize(item.path!);
        else if (item.isBatch && item.subItems != null) {
          double total = 0;
          final res = await Future.wait(item.subItems!.map((p) => SweepEngine.getDirSize(p.path!)));
          for (var s in res) total += SweepEngine.parseSizeToMb(s);
          if (total > 0) item.estimatedSize = SweepEngine.formatMb(total);
        }
      }));
    } finally {
      isScanning = false;
      notifyListeners();
    }
  }

  Future<void> runCleanup() async {
    isCleaning = true;
    currentNav = 'Purge Sequence';
    progress = 0;
    notifyListeners();

    final selected = <CleanupItem>[];
    void collect(List<CleanupItem> list) {
      for (var i in list) {
        if (i.isBatch && i.subItems != null) collect(i.subItems!);
        else if (i.selected || i.maintainSelected) selected.add(i);
      }
    }
    collect(detectedItems);

    double totalReclaimed = 0;
    int completed = 0;

    for (var item in selected) {
      status = 'Cleaning ${item.label}...';
      progress = completed / selected.length;
      notifyListeners();

      try {
        if (item.maintainSelected && item.upgradeCommand != null) {
          await Process.run(item.upgradeCommand!.split(' ')[0], item.upgradeCommand!.split(' ').sublist(1), workingDirectory: item.path, runInShell: true);
        }
        if (item.selected) {
          if (item.command != null) {
            await Process.run(item.command!.split(' ')[0], item.command!.split(' ').sublist(1), workingDirectory: item.path, runInShell: true);
          } else if (item.path != null) {
            if (FileSystemEntity.isDirectorySync(item.path!)) await Directory(item.path!).delete(recursive: true);
            else await File(item.path!).delete();
          }
        }
      } catch (_) {}
      completed++;
      totalReclaimed += SweepEngine.parseSizeToMb(item.estimatedSize);
    }

    if (totalReclaimed > 0 && appStats != null) {
      appStats!.addRecord(totalReclaimed);
      appStats!.save();
      await _loadHistory();
    }

    status = 'Cleanup Complete! ${SweepEngine.formatMb(totalReclaimed)} reclaimed.';
    isCleaning = false;
    progress = 1.0;
    notifyListeners();
  }
}

// --- MAIN APP ---

Future<void> initSystemTray() async {
  String path = Platform.isWindows ? 'assets/icon.ico' : 'assets/icon.png';
  final AppWindow appWindow = AppWindow();
  final SystemTray systemTray = SystemTray();
  
  await systemTray.initSystemTray(
    title: "Sweep",
    iconPath: path,
  );
  
  final Menu menu = Menu();
  await menu.buildFrom([
    MenuItemLabel(label: 'Show Dashboard', onClicked: (menuItem) => appWindow.show()),
    MenuItemLabel(label: 'Hide', onClicked: (menuItem) => appWindow.hide()),
    MenuSeparator(),
    MenuItemLabel(label: 'Exit Sweep', onClicked: (menuItem) => exit(0)),
  ]);
  
  await systemTray.setContextMenu(menu);
  
  systemTray.registerSystemTrayEventHandler((eventName) {
    if (eventName == kSystemTrayEventClick) {
      Platform.isWindows ? appWindow.show() : systemTray.popUpContextMenu();
    } else if (eventName == kSystemTrayEventRightClick) {
      Platform.isWindows ? systemTray.popUpContextMenu() : appWindow.show();
    }
  });
}

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();
    
    SharedPreferences? prefs;
    try { prefs = await SharedPreferences.getInstance(); } catch (e) { debugPrint('Prefs load failed: $e'); }

    // Try optional components but don't crash
    try { await localNotifier.setup(appName: 'Sweep'); } catch (e) { debugPrint('Local Notifier failed: $e'); }
    try { await initSystemTray(); } catch (e) { debugPrint('System Tray failed: $e'); }

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1300, 900),
      minimumSize: Size(800, 600),
      center: true,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'Sweep',
    );
    
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppTheme(prefs)),
          ChangeNotifierProvider(create: (_) => AppState(prefs)),
        ],
        child: const SweepApp(),
      ),
    );
  } catch (e) {
    // Last resort: just try to run something so it doesn't close
    debugPrint('FATAL STARTUP ERROR: $e');
    runApp(MaterialApp(home: Scaffold(body: Center(child: Text('Startup Error: $e')))));
  }
}

class SweepApp extends StatelessWidget {
  const SweepApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return MaterialApp(
      title: 'Sweep',
      debugShowCheckedModeBanner: false,
      theme: theme.themeData,
      home: const MainLayout(),
    );
  }
}

class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          const Sidebar(),
          Expanded(
            child: Column(
              children: [
                const TopBar(),
                Expanded(child: _buildCurrentPage(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentPage(BuildContext context) {
    final nav = context.watch<AppState>().currentNav;
    switch (nav) {
      case 'Dashboard': return const DashboardPage();
      case 'Scan Scope': return const ScanScopePage();
      case 'Review Targets': return const ReviewTargetsPage();
      case 'Purge Sequence': return const PurgeSequencePage();
      case 'Custom Rules': return const RulesManagerPage();
      case 'Settings': return const SettingsPage();
      case 'About System': return const AboutSystemPage();
      default: return const ScanScopePage();
    }
  }
}

// --- SHARED WIDGETS ---

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = context.watch<AppTheme>();

    return Container(
      width: 300,
      color: theme.isDark ? const Color(0xFF0D1117) : const Color(0xFFE5E7EB),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/icon.png', width: 56, height: 56),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sweep', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  Text('RECLAIM YOUR STORAGE', style: TextStyle(fontSize: 10, color: theme.accentColor, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 64),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NAVIGATION', style: TextStyle(fontSize: 11, color: theme.textHint, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const SizedBox(height: 24),
                  _NavLink('Dashboard', Icons.dashboard_outlined),
                  _NavLink('Scan Scope', Icons.filter_center_focus),
                  _NavLink('Review Targets', Icons.list_alt),
                  _NavLink('Purge Sequence', Icons.bolt_outlined),
                  _NavLink('Custom Rules', Icons.rule),
                  _NavLink('Settings', Icons.settings_outlined),
                  _NavLink('About System', Icons.info_outline),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const RuntimeStatusCard(),
        ],
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  final String label;
  final IconData icon;
  const _NavLink(this.label, this.icon);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = context.watch<AppTheme>();
    bool isActive = state.currentNav == label;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isActive ? theme.bgSubtle : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: isActive ? Border.all(color: theme.borderSubtle) : null,
      ),
      child: ListTile(
        onTap: () => state.setNav(label),
        leading: Icon(icon, color: isActive ? theme.accentColor : theme.textMuted, size: 22),
        title: Text(label, style: TextStyle(color: isActive ? theme.textPrimary : theme.textMuted, fontSize: 15, fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final state = context.watch<AppState>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: theme.bgSubtle, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(Icons.memory, size: 14, color: theme.accentColor),
                const SizedBox(width: 10),
                Text('SWEEP . CORE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1, color: theme.textSecondary)),
              ],
            ),
          ),
          const Spacer(),
          // Palette
          Row(
            children: theme.palette.keys.map((name) {
              bool isSelected = theme.accentName == name;
              return GestureDetector(
                onTap: () => theme.setAccent(name),
                child: Container(
                  width: 14, height: 14,
                  margin: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(
                    color: theme.palette[name]!.withOpacity(isSelected ? 1 : 0.3),
                    shape: BoxShape.circle,
                    border: isSelected ? Border.all(color: theme.textPrimary, width: 2) : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(width: 32),
          IconButton(
            onPressed: theme.toggleTheme,
            icon: Icon(theme.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 22, color: theme.textMuted),
          ),
          const SizedBox(width: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: theme.accentColor.withOpacity(0.1), borderRadius: BorderRadius.circular(24)),
            child: Text('ENGINE V2.0.4', style: TextStyle(fontSize: 10, color: theme.accentColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class RuntimeStatusCard extends StatelessWidget {
  const RuntimeStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = context.watch<AppTheme>();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.bgSubtle,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RUNTIME STATUS', style: TextStyle(fontSize: 11, color: theme.textHint, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 24),
          _StatusLine('CPU', state.systemStats.cpuUsage, Colors.blueAccent),
          const SizedBox(height: 20),
          _StatusLine('RAM', state.systemStats.ramUsage, Colors.orangeAccent),
          const SizedBox(height: 20),
          _StatusLine('Disk', state.systemStats.storageLeft, Colors.greenAccent),
          const SizedBox(height: 24),
          Text(Platform.operatingSystemVersion.toUpperCase(), style: TextStyle(fontSize: 9, color: theme.textDisabled)),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatusLine(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    double progress = 0.5; // Dummy
    if (value != '-' && value.isNotEmpty) {
      final clean = value.replaceAll(RegExp(r'[^0-9\.]'), '');
      final val = double.tryParse(clean) ?? 0;
      if (label == 'CPU') progress = (val / 100).clamp(0, 1.0);
      else if (label == 'RAM') progress = (val / 16).clamp(0, 1.0);
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: theme.textTertiary)),
            Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.textSecondary)),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(value: progress, minHeight: 4, backgroundColor: theme.textDisabled, valueColor: AlwaysStoppedAnimation(color)),
        ),
      ],
    );
  }
}

// --- PAGES ---

class ScanScopePage extends StatelessWidget {
  const ScanScopePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = context.watch<AppTheme>();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 48),
          const Text('Target Scope Configuration', style: TextStyle(fontSize: 42, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Text('Sweep now supports technical and stealth storage eaters, including virtual machines, emulators, and communication caches.', style: TextStyle(color: theme.textMuted, fontSize: 18, height: 1.5)),
          const SizedBox(height: 64),
          // Path Card
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(color: theme.bgSubtle, borderRadius: BorderRadius.circular(24), border: Border.all(color: theme.borderSubtle)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Icon(Icons.folder_outlined, size: 18, color: theme.accentColor), const SizedBox(width: 12), Text('ROOT DIRECTORY SCOPE', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: theme.textSecondary))]),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: BoxDecoration(color: theme.isDark ? Colors.black.withOpacity(0.3) : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: theme.borderSubtle)),
                  child: Row(
                    children: [
                      Icon(Icons.computer, color: theme.textHint),
                      const SizedBox(width: 20),
                      Expanded(child: Text(state.scanPath, style: TextStyle(fontSize: 16, color: theme.textSecondary))),
                      TextButton.icon(
                        onPressed: () async {
                          String? path = await FilePicker.platform.getDirectoryPath();
                          if (path != null) state.setPath(path);
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('MODIFY'),
                        style: TextButton.styleFrom(foregroundColor: theme.isDark ? Colors.white : Colors.black, padding: const EdgeInsets.symmetric(horizontal: 24)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 64),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ANALYSIS MODULES (${state.activeModules.values.where((v) => v).length} ACTIVE)', style: TextStyle(fontSize: 13, color: theme.textHint, fontWeight: FontWeight.bold, letterSpacing: 2)),
              TextButton(onPressed: () {
                for (var key in state.activeModules.keys) {
                  if (!(state.activeModules[key] ?? false)) state.toggleModule(key);
                }
              }, child: Text('SELECT ALL MODULES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.accentColor))),
            ],
          ),
          const SizedBox(height: 32),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            crossAxisSpacing: 32,
            mainAxisSpacing: 32,
            childAspectRatio: 2.2,
            children: state.activeModules.keys.map((name) => _ModuleCard(name)).toList(),
          ),
          const SizedBox(height: 64),
          Center(
            child: SizedBox(
              width: 400, height: 72,
              child: ElevatedButton(
                onPressed: state.runScan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.isDark ? Colors.white : theme.accentColor,
                  foregroundColor: theme.isDark ? Colors.black : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bolt, size: 24),
                    SizedBox(width: 16),
                    Text('INITIATE GLOBAL SCAN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    SizedBox(width: 16),
                    Icon(Icons.chevron_right, size: 24),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 64),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final String name;
  const _ModuleCard(this.name);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = context.watch<AppTheme>();
    bool isActive = state.activeModules[name]!;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isActive ? theme.accentColor.withOpacity(0.05) : theme.bgSubtle,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isActive ? theme.accentColor.withOpacity(0.3) : theme.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: theme.isDark ? Colors.black.withOpacity(0.2) : theme.accentColor.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
            child: _getIcon(name),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.textPrimary)),
                const SizedBox(height: 6),
                Text(_getDesc(name), style: TextStyle(fontSize: 11, color: theme.textHint)),
              ],
            ),
          ),
          Switch(
            value: isActive,
            onChanged: (v) => state.toggleModule(name),
            activeColor: theme.accentColor,
          ),
        ],
      ),
    );
  }

  Widget _getIcon(String name) {
    String asset = 'ai.png';
    if (name.contains('Flutter')) asset = 'flutter.png';
    else if (name.contains('Node')) asset = 'nodejs.png';
    else if (name.contains('Rust')) asset = 'rust.png';
    else if (name.contains('Python')) asset = 'python.png';
    else if (name.contains('Android')) asset = 'android.png';
    else if (name.contains('PHP')) asset = 'php.png';
    else if (name.contains('NET')) asset = 'dotnet.png';
    else if (name.contains('Unreal')) asset = 'unreal.png';
    
    return Image.asset('assets/frameworks/$asset', fit: BoxFit.contain, errorBuilder: (c, e, s) => Icon(Icons.developer_mode, color: Colors.white24, size: 28));
  }

  String _getDesc(String name) {
    if (name.contains('Flutter')) return 'Dart tool, Gradle, Pods...';
    if (name.contains('Node')) return 'node_modules, dist, .next...';
    if (name.contains('Rust')) return 'Target, cargo artifacts...';
    if (name.contains('AI')) return 'HuggingFace, cache, datasets...';
    if (name.contains('Android')) return 'Build, .gradle, emulators...';
    if (name.contains('Python')) return 'venv, __pycache__, conda...';
    if (name.contains('PHP')) return 'Vendor, storage, logs...';
    if (name.contains('NET')) return 'bin/obj, NuGet caches...';
    if (name.contains('Unreal')) return 'Binaries, intermediate, saved...';
    return 'Marker required';
  }
}

class ReviewTargetsPage extends StatelessWidget {
  const ReviewTargetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = context.watch<AppTheme>();

    if (state.isScanning) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: theme.accentColor),
            const SizedBox(height: 24),
            Text('TARGETING 19 MODULES ...', style: TextStyle(color: theme.textMuted, letterSpacing: 2)),
          ],
        ),
      );
    }

    double totalSelected = 0;
    for (var i in state.detectedItems) if (i.selected) totalSelected += SweepEngine.parseSizeToMb(i.estimatedSize);

    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Review Identified Junk', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text('We found ${state.detectedItems.length} items. Review the list below and select items to purge.', style: TextStyle(color: theme.textMuted)),
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            ElevatedButton(onPressed: state.runCleanup, style: ElevatedButton.styleFrom(backgroundColor: theme.isDark ? Colors.white : theme.accentColor, foregroundColor: theme.isDark ? Colors.black : Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18)), child: const Text('START PURGE SEQUENCE')),
                            const SizedBox(width: 16),
                            OutlinedButton(onPressed: () => state.setNav('Scan Scope'), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18)), child: const Text('ADJUST SCOPE')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: 300,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('TOTAL RECLAIMABLE', style: TextStyle(fontSize: 10, color: theme.textHint, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                        const SizedBox(height: 16),
                        Text(SweepEngine.formatMb(totalSelected).split(' ').first, style: TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: theme.textPrimary)),
                        Text(SweepEngine.formatMb(totalSelected).split(' ').last, style: TextStyle(fontSize: 18, color: theme.textMuted)),
                        const SizedBox(height: 16),
                        Text('≈ 1.28% OF HARD DRIVE', style: TextStyle(fontSize: 10, color: theme.accentColor, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 48),
          Expanded(
            child: ListView.builder(
              itemCount: state.detectedItems.length,
              itemBuilder: (context, idx) {
                final item = state.detectedItems[idx];
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: BoxDecoration(color: theme.bgSubtle, borderRadius: BorderRadius.circular(16), border: Border.all(color: theme.borderSubtle)),
                  child: Row(
                    children: [
                      Checkbox(
                        value: item.selected,
                        onChanged: (v) => state.toggleItemSelection(item),
                        activeColor: theme.accentColor,
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.path ?? item.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: theme.textPrimary)),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: theme.accentColor.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                              child: Text(item.note ?? 'Recommended for review. Build artifacts detected.', style: TextStyle(fontSize: 11, color: theme.accentColor)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 48),
                      Column(
                        children: [
                          Text('TYPE', style: TextStyle(fontSize: 9, color: theme.textHint, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(item.category.split(' ').first, style: TextStyle(fontSize: 12, color: theme.textSecondary)),
                        ],
                      ),
                      const SizedBox(width: 48),
                      Column(
                        children: [
                          Text('SIZE', style: TextStyle(fontSize: 9, color: theme.textHint, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(item.estimatedSize ?? '0M', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: theme.textPrimary)),
                        ],
                      ),
                      const SizedBox(width: 48),
                      ElevatedButton(
                        onPressed: () => state.ignoreItem(item),
                        style: ElevatedButton.styleFrom(backgroundColor: theme.bgSubtle, foregroundColor: Colors.redAccent.withOpacity(0.8)),
                        child: const Text('IGNORE', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class PurgeSequencePage extends StatelessWidget {
  const PurgeSequencePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = context.watch<AppTheme>();

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bolt, size: 80, color: theme.accentColor),
          const SizedBox(height: 32),
          Text(state.isCleaning ? 'PURGE IN SEQUENCE' : 'PURGE COMPLETE', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2, color: theme.textPrimary)),
          const SizedBox(height: 12),
          Text(state.status, style: TextStyle(color: theme.textMuted, fontSize: 16)),
          const SizedBox(height: 64),
          SizedBox(
            width: 500,
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: state.progress, minHeight: 8, backgroundColor: theme.textDisabled, valueColor: AlwaysStoppedAnimation(theme.accentColor)),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${(state.progress * 100).toInt()}% COMPLETE', style: TextStyle(fontSize: 11, color: theme.textHint, fontWeight: FontWeight.bold)),
                    if (!state.isCleaning) TextButton(onPressed: () => state.setNav('Scan Scope'), child: const Text('RETURN TO CONSOLE')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();

    return Padding(
      padding: const EdgeInsets.all(64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Appearance & Identity', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: theme.textPrimary)),
          const SizedBox(height: 48),
          _buildSettingRow(theme, 'Interface Mode', 'Switch between dark for focus or light for clarity.', Row(
            children: [
              _ThemeBtn('Light', Icons.wb_sunny_outlined, !theme.isDark, theme.toggleTheme),
              const SizedBox(width: 12),
              _ThemeBtn('Dark', Icons.dark_mode_outlined, theme.isDark, theme.toggleTheme),
            ],
          )),
          const SizedBox(height: 48),
          _buildSettingRow(theme, 'Accent Palette', 'Select the primary system signal color.', Wrap(
            spacing: 12,
            children: theme.palette.keys.map((name) => _PaletteBtn(name)).toList(),
          )),
        ],
      ),
    );
  }

  Widget _buildSettingRow(AppTheme theme, String title, String desc, Widget ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.textSecondary)),
        const SizedBox(height: 8),
        Text(desc, style: TextStyle(color: theme.textMuted)),
        const SizedBox(height: 24),
        ctrl,
      ],
    );
  }
}

class _ThemeBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback tap;
  const _ThemeBtn(this.label, this.icon, this.active, this.tap);

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return ElevatedButton.icon(
      onPressed: tap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: active ? theme.bgSubtle : Colors.transparent,
        foregroundColor: active ? theme.textPrimary : theme.textMuted,
        side: BorderSide(color: active ? theme.borderSubtle : Colors.transparent),
      ),
    );
  }
}

class _PaletteBtn extends StatelessWidget {
  final String name;
  const _PaletteBtn(this.name);

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    bool active = theme.accentName == name;
    return InkWell(
      onTap: () => theme.setAccent(name),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: active ? theme.palette[name]!.withOpacity(0.1) : theme.bgSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? theme.palette[name]! : theme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: theme.palette[name], shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Text(name, style: TextStyle(color: active ? theme.textPrimary : theme.textMuted, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

class AboutSystemPage extends StatelessWidget {
  const AboutSystemPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(64),
      child: Column(
        children: [
          Image.asset('assets/icon.png', width: 100),
          const SizedBox(height: 24),
          Text('Sweep Orchestrator', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: theme.textPrimary)),
          Text('RECLAIM YOUR STORAGE', style: TextStyle(color: theme.textHint, letterSpacing: 2)),
          const SizedBox(height: 64),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('THE "1GB INCIDENT" ORIGIN', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1, color: theme.textSecondary)),
                        const SizedBox(height: 24),
                        Text(
                          'Sweep was born in a moment of pure developer frustration. Yesterday at work, a classmate asked me to run a Flutter app on his device. I ran `flutter run ios`, but it crashed.\n\n'
                          'We assumed it was his iPhone storage. He had 100GB free. I checked my Mac and realized I had exactly **1 GB of space left**.\n\n'
                          'Google Antigravity guided me to the hidden artifacts eating my disk. I realized every dev needs a better way to clean their workspace.',
                          style: TextStyle(color: theme.textTertiary, height: 1.6),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 32),
              Expanded(
                child: Column(
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Text('AI COLLABORATION', style: TextStyle(fontWeight: FontWeight.bold, color: theme.textSecondary)),
                            const SizedBox(height: 16),
                            Text(
                              'This entire application was architected and built using Vide Coding techniques with Google Gemini. When cloud limits hit, we pushed through using Gemini 1.5 Flash to maintain the high-performance momentum.',
                              style: TextStyle(color: theme.textMuted, fontStyle: FontStyle.italic, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('MADE WITH PRECISION IN IRAQ • 2026', style: TextStyle(fontSize: 10, color: theme.textDisabled)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = context.watch<AppTheme>();
    final stats = state.appStats?.history ?? {};
    
    if (stats.isEmpty) {
      return Center(child: Text("No cleanup history yet.", style: TextStyle(color: theme.textMuted, fontSize: 18)));
    }

    final double totalLifetime = stats.values.fold(0, (a, b) => a + b);
    
    final List<BarChartGroupData> barGroups = [];
    int x = 0;
    stats.forEach((date, mb) {
      barGroups.add(
        BarChartGroupData(
          x: x,
          barRods: [
            BarChartRodData(
              toY: mb,
              color: theme.accentColor,
              width: 16,
              borderRadius: BorderRadius.circular(4),
            )
          ],
        )
      );
      x++;
    });

    return Padding(
      padding: const EdgeInsets.all(64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Savings Dashboard', style: TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: theme.textPrimary)),
          const SizedBox(height: 16),
          Text('Lifetime Storage Reclaimed: ${SweepEngine.formatMb(totalLifetime)}', style: TextStyle(color: theme.textSecondary, fontSize: 18, fontWeight: FontWeight.w500)),
          const SizedBox(height: 64),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: theme.bgSubtle,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: theme.borderSubtle),
              ),
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => theme.sidebarColor,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          SweepEngine.formatMb(rod.toY),
                          TextStyle(color: theme.textPrimary, fontWeight: FontWeight.bold),
                        );
                      }
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() < stats.keys.length) {
                            final dateStr = stats.keys.elementAt(value.toInt());
                            final parts = dateStr.split('-');
                            final shortDate = parts.length > 2 ? "${parts[1]}/${parts[2]}" : dateStr;
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(shortDate, style: TextStyle(color: theme.textMuted, fontSize: 10)),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: theme.borderSubtle,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: barGroups,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RulesManagerPage extends StatefulWidget {
  const RulesManagerPage({super.key});

  @override
  State<RulesManagerPage> createState() => _RulesManagerPageState();
}

class _RulesManagerPageState extends State<RulesManagerPage> {
  List<dynamic> _rules = [];
  String _rulesPath = '';

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  void _loadRules() {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    _rulesPath = '$home/.sweep_rules.json';
    final file = File(_rulesPath);
    if (file.existsSync()) {
      try {
        setState(() {
          _rules = jsonDecode(file.readAsStringSync());
        });
      } catch (_) {
        setState(() { _rules = []; });
      }
    }
  }

  void _saveRules() {
    final file = File(_rulesPath);
    file.writeAsStringSync(jsonEncode(_rules));
    _loadRules();
  }

  void _deleteRule(int index) {
    _rules.removeAt(index);
    _saveRules();
  }

  void _showAddRuleDialog(BuildContext context, AppTheme theme) {
    String name = '';
    String markers = '';
    String cleanupLabel = '';
    String command = '';
    String foldersToNuke = '';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: theme.sidebarColor,
          title: Text('Add Custom Rule', style: TextStyle(color: theme.textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  style: TextStyle(color: theme.textPrimary),
                  decoration: InputDecoration(labelText: 'Framework Name', labelStyle: TextStyle(color: theme.textHint)),
                  onChanged: (v) => name = v,
                ),
                TextField(
                  style: TextStyle(color: theme.textPrimary),
                  decoration: InputDecoration(labelText: 'Markers (comma separated, e.g. pubspec.yaml)', labelStyle: TextStyle(color: theme.textHint)),
                  onChanged: (v) => markers = v,
                ),
                TextField(
                  style: TextStyle(color: theme.textPrimary),
                  decoration: InputDecoration(labelText: 'Cleanup Label', labelStyle: TextStyle(color: theme.textHint)),
                  onChanged: (v) => cleanupLabel = v,
                ),
                TextField(
                  style: TextStyle(color: theme.textPrimary),
                  decoration: InputDecoration(labelText: 'Cleanup Command (optional)', labelStyle: TextStyle(color: theme.textHint)),
                  onChanged: (v) => command = v,
                ),
                TextField(
                  style: TextStyle(color: theme.textPrimary),
                  decoration: InputDecoration(labelText: 'Folders to Nuke (comma separated)', labelStyle: TextStyle(color: theme.textHint)),
                  onChanged: (v) => foldersToNuke = v,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: theme.textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: theme.accentColor),
              onPressed: () {
                if (name.isEmpty || markers.isEmpty) return;
                _rules.add({
                  'name': name,
                  'markers': markers.split(',').map((e) => e.trim()).toList(),
                  'cleanupLabel': cleanupLabel.isEmpty ? 'Clean' : cleanupLabel,
                  'command': command.isEmpty ? null : command,
                  'foldersToNuke': foldersToNuke.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                });
                _saveRules();
                Navigator.pop(context);
              },
              child: const Text('Save Rule', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Padding(
      padding: const EdgeInsets.all(64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Custom Rules Manager', style: TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: theme.textPrimary)),
              ElevatedButton.icon(
                onPressed: () => _showAddRuleDialog(context, theme),
                icon: const Icon(Icons.add),
                label: const Text('Add Rule'),
                style: ElevatedButton.styleFrom(backgroundColor: theme.accentColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Define your own markers and cleanup commands for unsupported frameworks.', style: TextStyle(color: theme.textMuted, fontSize: 18, height: 1.5)),
          const SizedBox(height: 64),
          Expanded(
            child: _rules.isEmpty 
              ? Center(child: Text("No custom rules defined.", style: TextStyle(color: theme.textMuted, fontSize: 18)))
              : ListView.builder(
                  itemCount: _rules.length,
                  itemBuilder: (context, index) {
                    final rule = _rules[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      decoration: BoxDecoration(color: theme.bgSubtle, borderRadius: BorderRadius.circular(16), border: Border.all(color: theme.borderSubtle)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(rule['name'] ?? 'Unknown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.textPrimary)),
                                const SizedBox(height: 8),
                                Text('Markers: ${(rule['markers'] as List).join(", ")}', style: TextStyle(color: theme.textSecondary)),
                                if (rule['command'] != null) Text('Command: ${rule['command']}', style: TextStyle(color: theme.textHint)),
                                if (rule['foldersToNuke'] != null && (rule['foldersToNuke'] as List).isNotEmpty) Text('Nukes: ${(rule['foldersToNuke'] as List).join(", ")}', style: TextStyle(color: theme.textHint)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () => _deleteRule(index),
                          ),
                        ],
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}

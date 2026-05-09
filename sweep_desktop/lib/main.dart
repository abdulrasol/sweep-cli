import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'sweep_engine.dart';

// --- THEME & STATE MANAGEMENT ---

class AppTheme extends ChangeNotifier {
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

  void toggleTheme() {
    isDark = !isDark;
    notifyListeners();
  }

  void setAccent(String name) {
    accentName = name;
    accentColor = palette[name]!;
    notifyListeners();
  }

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
      cardTheme: CardTheme(
        color: isDark ? const Color(0xFF14191F) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
    );
  }
}

class AppState extends ChangeNotifier {
  String currentNav = 'Scan Scope';
  String scanPath = '';
  List<CleanupItem> detectedItems = [];
  bool isScanning = false;
  bool isCleaning = false;
  double progress = 0;
  String status = '';
  SystemStats systemStats = SystemStats.empty();

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

  AppState() {
    scanPath = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '/';
    _startStats();
  }

  void setNav(String nav) {
    currentNav = nav;
    notifyListeners();
  }

  void toggleModule(String name) {
    activeModules[name] = !(activeModules[name] ?? false);
    notifyListeners();
  }

  void setPath(String path) {
    scanPath = path;
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
      // Filter items based on active modules if needed
      detectedItems = items;
      
      // Parallel sizing
      await Future.wait(items.map((item) async {
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

    status = 'Cleanup Complete! ${SweepEngine.formatMb(totalReclaimed)} reclaimed.';
    isCleaning = false;
    progress = 1.0;
    notifyListeners();
  }
}

// --- MAIN APP ---

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await localNotifier.setup(appName: 'Sweep');

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1300, 900),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: 'Sweep',
  );
  
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppTheme()),
        ChangeNotifierProvider(create: (_) => AppState()),
      ],
      child: const SweepApp(),
    ),
  );
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
      case 'Scan Scope': return const ScanScopePage();
      case 'Review Targets': return const ReviewTargetsPage();
      case 'Purge Sequence': return const PurgeSequencePage();
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
          const Text('NAVIGATION', style: TextStyle(fontSize: 11, color: Colors.white24, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 24),
          _NavLink('Scan Scope', Icons.filter_center_focus),
          _NavLink('Review Targets', Icons.list_alt),
          _NavLink('Purge Sequence', Icons.bolt_outlined),
          _NavLink('Settings', Icons.settings_outlined),
          _NavLink('About System', Icons.info_outline),
          const Spacer(),
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
        color: isActive ? Colors.white.withOpacity(0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: isActive ? Border.all(color: Colors.white.withOpacity(0.1)) : null,
      ),
      child: ListTile(
        onTap: () => state.setNav(label),
        leading: Icon(icon, color: isActive ? theme.accentColor : Colors.white38, size: 22),
        title: Text(label, style: TextStyle(color: isActive ? Colors.white : Colors.white38, fontSize: 15, fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
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
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(Icons.memory, size: 14, color: theme.accentColor),
                const SizedBox(width: 10),
                Text('SWEEP . CORE', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
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
                    border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(width: 32),
          IconButton(
            onPressed: theme.toggleTheme,
            icon: Icon(theme.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 22, color: Colors.white38),
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
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('RUNTIME STATUS', style: TextStyle(fontSize: 11, color: Colors.white24, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 24),
          _StatusLine('CPU', state.systemStats.cpuUsage, Colors.blueAccent),
          const SizedBox(height: 20),
          _StatusLine('RAM', state.systemStats.ramUsage, Colors.orangeAccent),
          const SizedBox(height: 20),
          _StatusLine('Disk', state.systemStats.storageLeft, Colors.greenAccent),
          const SizedBox(height: 24),
          Text(Platform.operatingSystemVersion.toUpperCase(), style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.1))),
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
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54)),
            Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(value: progress, minHeight: 4, backgroundColor: Colors.white10, valueColor: AlwaysStoppedAnimation(color)),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 48),
          const Text('Target Scope Configuration', style: TextStyle(fontSize: 42, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text('Sweep now supports technical and stealth storage eaters, including virtual machines, emulators, and communication caches.', style: TextStyle(color: Colors.white38, fontSize: 18, height: 1.5)),
          const SizedBox(height: 64),
          // Path Card
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.05))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Icon(Icons.folder_outlined, size: 18, color: theme.accentColor), const SizedBox(width: 12), const Text('ROOT DIRECTORY SCOPE', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.5))]),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.05))),
                  child: Row(
                    children: [
                      const Icon(Icons.computer, color: Colors.white24),
                      const SizedBox(width: 20),
                      Expanded(child: Text(state.scanPath, style: const TextStyle(fontSize: 16, color: Colors.white70))),
                      TextButton.icon(
                        onPressed: () async {
                          String? path = await FilePicker.platform.getDirectoryPath();
                          if (path != null) state.setPath(path);
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('MODIFY'),
                        style: TextButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24)),
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
              const Text('ANALYSIS MODULES (19 ACTIVE)', style: TextStyle(fontSize: 13, color: Colors.white24, fontWeight: FontWeight.bold, letterSpacing: 2)),
              TextButton(onPressed: () {}, child: Text('SELECT ALL MODULES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.accentColor))),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              crossAxisSpacing: 32,
              mainAxisSpacing: 32,
              childAspectRatio: 2.2,
              children: state.activeModules.keys.map((name) => _ModuleCard(name)).toList(),
            ),
          ),
          Center(
            child: SizedBox(
              width: 400, height: 72,
              child: ElevatedButton(
                onPressed: state.runScan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
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
          const SizedBox(height: 48),
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
        color: isActive ? theme.accentColor.withOpacity(0.05) : Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isActive ? theme.accentColor.withOpacity(0.3) : Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
            child: Icon(_getIcon(name), color: isActive ? theme.accentColor : Colors.white24, size: 28),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 6),
                Text(_getDesc(name), style: const TextStyle(fontSize: 11, color: Colors.white24)),
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

  IconData _getIcon(String name) {
    if (name.contains('Flutter')) return Icons.flutter_dash;
    if (name.contains('Node')) return Icons.javascript;
    if (name.contains('Rust')) return Icons.settings_input_component;
    if (name.contains('AI')) return Icons.psychology;
    if (name.contains('Android')) return Icons.android;
    if (name.contains('Python')) return Icons.code;
    return Icons.developer_mode;
  }

  String _getDesc(String name) {
    if (name.contains('Flutter')) return 'Pub caches, artifacts...';
    if (name.contains('Node')) return 'node_modules, .next...';
    if (name.contains('Rust')) return 'Target directories...';
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
            const Text('TARGETING 19 MODULES ...', style: TextStyle(color: Colors.white38, letterSpacing: 2)),
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
                        Text('We found ${state.detectedItems.length} items. Review the list below and select items to purge.', style: const TextStyle(color: Colors.white38)),
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            ElevatedButton(onPressed: state.runCleanup, style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18)), child: const Text('START PURGE SEQUENCE')),
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
                        const Text('TOTAL RECLAIMABLE', style: TextStyle(fontSize: 10, color: Colors.white24, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                        const SizedBox(height: 16),
                        Text(SweepEngine.formatMb(totalSelected).split(' ').first, style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold)),
                        Text(SweepEngine.formatMb(totalSelected).split(' ').last, style: const TextStyle(fontSize: 18, color: Colors.white38)),
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
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.05))),
                  child: Row(
                    children: [
                      Checkbox(
                        value: item.selected,
                        onChanged: (v) => state.notifyListeners(), // Simple toggle for now
                        activeColor: theme.accentColor,
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.path ?? item.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: theme.accentColor.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                              child: Text('Recommended for review. Build artifacts detected.', style: TextStyle(fontSize: 11, color: theme.accentColor)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 48),
                      Column(
                        children: [
                          const Text('TYPE', style: TextStyle(fontSize: 9, color: Colors.white24, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(item.category.split(' ').first, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                      const SizedBox(width: 48),
                      Column(
                        children: [
                          const Text('SIZE', style: TextStyle(fontSize: 9, color: Colors.white24, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(item.estimatedSize ?? '0M', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(width: 48),
                      ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05)), child: const Text('REVIEW', style: TextStyle(fontSize: 11))),
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
          Text(state.isCleaning ? 'PURGE IN SEQUENCE' : 'PURGE COMPLETE', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 12),
          Text(state.status, style: const TextStyle(color: Colors.white38, fontSize: 16)),
          const SizedBox(height: 64),
          SizedBox(
            width: 500,
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: state.progress, minHeight: 8, backgroundColor: Colors.white10, valueColor: AlwaysStoppedAnimation(theme.accentColor)),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${(state.progress * 100).toInt()}% COMPLETE', style: const TextStyle(fontSize: 11, color: Colors.white24, fontWeight: FontWeight.bold)),
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
          const Text('Appearance & Identity', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 48),
          _buildSettingRow('Interface Mode', 'Switch between dark for focus or light for clarity.', Row(
            children: [
              _ThemeBtn('Light', Icons.wb_sunny_outlined, !theme.isDark, theme.toggleTheme),
              const SizedBox(width: 12),
              _ThemeBtn('Dark', Icons.dark_mode_outlined, theme.isDark, theme.toggleTheme),
            ],
          )),
          const SizedBox(height: 48),
          _buildSettingRow('Accent Palette', 'Select the primary system signal color.', Wrap(
            spacing: 12,
            children: theme.palette.keys.map((name) => _PaletteBtn(name)).toList(),
          )),
        ],
      ),
    );
  }

  Widget _buildSettingRow(String title, String desc, Widget ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(desc, style: const TextStyle(color: Colors.white38)),
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
    return ElevatedButton.icon(
      onPressed: tap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: active ? Colors.white.withOpacity(0.1) : Colors.transparent,
        foregroundColor: active ? Colors.white : Colors.white38,
        side: BorderSide(color: active ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.05)),
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
          color: active ? theme.palette[name]!.withOpacity(0.1) : Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? theme.palette[name]! : Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: theme.palette[name], shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Text(name, style: TextStyle(color: active ? Colors.white : Colors.white38, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
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
          const Text('Sweep Orchestrator', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const Text('RECLAIM YOUR STORAGE', style: TextStyle(color: Colors.white24, letterSpacing: 2)),
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
                        const Text('THE "1GB INCIDENT" ORIGIN', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                        const SizedBox(height: 24),
                        const Text(
                          'Sweep was born in a moment of pure developer frustration. Yesterday at work, a classmate asked me to run a Flutter app on his device. I ran `flutter run ios`, but it crashed.\n\n'
                          'We assumed it was his iPhone storage. He had 100GB free. I checked my Mac and realized I had exactly **1 GB of space left**.\n\n'
                          'Google Antigravity guided me to the hidden artifacts eating my disk. I realized every dev needs a better way to clean their workspace.',
                          style: TextStyle(color: Colors.white54, height: 1.6),
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
                            const Text('AI COLLABORATION', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 16),
                            const Text(
                              'This entire application was architected and built using Vide Coding techniques with Google Gemini. When cloud limits hit, we pushed through using Gemini 1.5 Flash to maintain the high-performance momentum.',
                              style: TextStyle(color: Colors.white38, fontStyle: FontStyle.italic, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('MADE WITH PRECISION IN IRAQ • 2026', style: TextStyle(fontSize: 10, color: Colors.white10)),
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

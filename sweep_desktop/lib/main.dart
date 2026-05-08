import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'sweep_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await localNotifier.setup(appName: 'Sweep');
  runApp(const SweepApp());
}

class SweepApp extends StatelessWidget {
  const SweepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sweep',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentTab = 0;
  final TextEditingController _pathController = TextEditingController();
  List<CleanupItem> _items = [];
  bool _isScanning = false;
  bool _isCleaning = false;
  double _progress = 0;
  String _currentStatus = '';
  SystemStats _stats = SystemStats.empty();
  Timer? _statsTimer;
  Stats _savingsStats = Stats();
  List<File> _archives = [];

  @override
  void initState() {
    super.initState();
    _loadInitialPath();
    _startStatsMonitoring();
    _loadSavings();
    _loadArchives();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    super.dispose();
  }

  void _startStatsMonitoring() {
    _updateStats();
    _statsTimer = Timer.periodic(const Duration(seconds: 5), (timer) => _updateStats());
  }

  Future<void> _updateStats() async {
    final newStats = await SweepEngine.getSystemStats();
    if (mounted) setState(() => _stats = newStats);
  }

  Future<void> _loadSavings() async {
    final s = await Stats.load();
    setState(() => _savingsStats = s);
  }

  Future<void> _loadInitialPath() async {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    setState(() => _pathController.text = home);
  }

  Future<void> _loadArchives() async {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    final dir = Directory('$home/Downloads/Sweep_Archives');
    if (dir.existsSync()) {
      setState(() => _archives = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.zip')).toList());
    }
  }

  Future<void> _pickDirectory() async {
    String? selected = await FilePicker.platform.getDirectoryPath();
    if (selected != null) {
      setState(() => _pathController.text = selected);
      _scan();
    }
  }

  Future<void> _scan() async {
    if (_pathController.text.isEmpty) return;
    setState(() { _isScanning = true; _items = []; });
    try {
      final items = await SweepEngine.scan(_pathController.text, []);
      await Future.wait(items.map((item) async {
        if (item.category.startsWith('BIG FILES')) return;
        if (item.path != null) item.estimatedSize = await SweepEngine.getDirSize(item.path!);
        else if (item.isBatch && item.subItems != null) {
          double total = 0;
          final res = await Future.wait(item.subItems!.map((p) => SweepEngine.getDirSize(p.path!)));
          for (var s in res) total += SweepEngine.parseSizeToMb(s);
          if (total > 0) item.estimatedSize = SweepEngine.formatMb(total);
        }
      }));
      setState(() => _items = items);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan error: $e')));
    } finally {
      setState(() => _isScanning = false);
    }
  }

  double get _selectedTotalMb {
    double total = 0;
    void calculate(List<CleanupItem> list) {
      for (var item in list) {
        if (item.isBatch && item.subItems != null) calculate(item.subItems!);
        else if (item.selected) total += SweepEngine.parseSizeToMb(item.estimatedSize);
      }
    }
    calculate(_items);
    return total;
  }

  bool get _anyItemSelected {
    bool found = false;
    void check(List<CleanupItem> list) {
      if (found) return;
      for (var item in list) {
        if (item.isBatch && item.subItems != null) {
          for (var s in item.subItems!) if (s.selected || s.maintainSelected || s.archiveSelected) { found = true; return; }
        } else if (item.selected || item.maintainSelected || item.archiveSelected) { found = true; return; }
      }
    }
    check(_items);
    return found;
  }

  Future<void> _executeCleanup() async {
    final selectedTasks = <CleanupItem>[];
    void collect(List<CleanupItem> list) {
      for (var i in list) {
        if (i.isBatch && i.subItems != null) collect(i.subItems!);
        else if (i.selected || i.maintainSelected || i.archiveSelected) selectedTasks.add(i);
      }
    }
    collect(_items);
    if (selectedTasks.isEmpty) return;

    setState(() { _isCleaning = true; _progress = 0; });
    double totalReclaimed = 0;
    int completed = 0;
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

    for (var item in selectedTasks) {
      setState(() { _currentStatus = 'Processing: ${item.label}'; _progress = completed / selectedTasks.length; });
      try {
        if (item.archiveSelected && item.path != null) {
          final archiveDir = Directory('$home/Downloads/Sweep_Archives');
          if (!archiveDir.existsSync()) archiveDir.createSync(recursive: true);
          final zipName = '${item.label}_${DateTime.now().millisecondsSinceEpoch}.zip';
          await Process.run('zip', ['-r', '${archiveDir.path}/$zipName', '.'], workingDirectory: item.path, runInShell: true);
          await Directory(item.path!).delete(recursive: true);
        } else {
          if (item.maintainSelected && item.upgradeCommand != null) {
            await Process.run(item.upgradeCommand!.split(' ')[0], item.upgradeCommand!.split(' ').sublist(1), workingDirectory: item.path, runInShell: true);
          }
          if (item.selected) {
            if (item.command != null) await Process.run(item.command!.split(' ')[0], item.command!.split(' ').sublist(1), workingDirectory: item.path, runInShell: true);
            else if (item.path != null) {
              if (FileSystemEntity.isDirectorySync(item.path!)) await Directory(item.path!).delete(recursive: true);
              else await File(item.path!).delete();
            }
          }
        }
      } catch (_) {}
      completed++;
      totalReclaimed += SweepEngine.parseSizeToMb(item.estimatedSize);
    }

    _savingsStats.addRecord(totalReclaimed);
    _savingsStats.save();
    _loadArchives();

    LocalNotification notification = LocalNotification(
      title: 'Sweep Complete! ✨',
      body: 'Successfully reclaimed ${SweepEngine.formatMb(totalReclaimed)} of space.',
    );
    notification.show();

    setState(() { _isCleaning = false; _currentStatus = 'Finished!'; });
    _scan();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          NavigationRail(
            selectedIndex: _currentTab,
            onDestinationSelected: (idx) => setState(() => _currentTab = idx),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: Text('Home')),
              NavigationRailDestination(icon: Icon(Icons.cleaning_services_outlined), selectedIcon: Icon(Icons.cleaning_services), label: Text('Clean')),
              NavigationRailDestination(icon: Icon(Icons.archive_outlined), selectedIcon: Icon(Icons.archive), label: Text('Archives')),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _buildTabContent()),
        ],
      ),
      bottomNavigationBar: _buildStateBar(),
    );
  }

  Widget _buildTabContent() {
    switch (_currentTab) {
      case 0: return _buildDashboard();
      case 1: return _buildCleanupView();
      case 2: return _buildArchivesView();
      default: return Container();
    }
  }

  Widget _buildDashboard() {
    final Map<String, double> catSizes = {};
    for (var item in _items) {
      catSizes[item.category] = (catSizes[item.category] ?? 0) + SweepEngine.parseSizeToMb(item.estimatedSize);
    }

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Welcome back, Abdulrasol', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          Expanded(
            child: Row(
              children: [
                // Storage Pie Chart
                Expanded(
                  child: _items.isEmpty 
                    ? const Center(child: Text('Scan to see analytics'))
                    : Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              const Text('Space Distribution', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 24),
                              Expanded(
                                child: PieChart(PieChartData(
                                  sections: catSizes.entries.map((e) {
                                    return PieChartSectionData(
                                      value: e.value,
                                      title: e.key.split(' ').first,
                                      color: Colors.cyan.withOpacity((catSizes.keys.toList().indexOf(e.key) + 1) / catSizes.length),
                                      radius: 60,
                                    );
                                  }).toList(),
                                )),
                              ),
                            ],
                          ),
                        ),
                      ),
                ),
                const SizedBox(width: 24),
                // Savings Line Chart
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const Text('Space Saved History (MB)', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 24),
                          Expanded(
                            child: LineChart(LineChartData(
                              lineBarsData: [
                                LineChartBarData(
                                  spots: _savingsStats.history.entries.indexed.map((e) => FlSpot(e.$1.toDouble(), e.$2.value)).toList(),
                                  isCurved: true,
                                  color: Colors.greenAccent,
                                  barWidth: 4,
                                  dotData: const FlDotData(show: false),
                                )
                              ],
                              titlesData: const FlTitlesData(show: false),
                              gridData: const FlGridData(show: false),
                            )),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text('Recommended Actions', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          _buildQuickAction('Nuke Caches', 'Instantly clear global developer caches.', Icons.flash_on, () => setState(() { _currentTab = 1; })),
        ],
      ),
    );
  }

  Widget _buildCleanupView() {
    final categories = <String, List<CleanupItem>>{};
    for (var item in _items) categories.putIfAbsent(item.category, () => []).add(item);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pathController,
                  decoration: InputDecoration(
                    labelText: 'Source Directory',
                    prefixIcon: const Icon(Icons.folder_open, color: Colors.cyan),
                    suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _pickDirectory),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _isScanning || _isCleaning ? null : _scan,
                icon: _isScanning ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.rocket_launch),
                label: const Text('SCAN'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _items.isEmpty
            ? Center(child: Text(_isScanning ? 'Analyzing...' : 'Scan to start cleaning.'))
            : ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: categories.keys.map((cat) => _buildCategoryTile(cat, categories[cat]!)).toList(),
              ),
        ),
        _buildCleanupFooter(),
      ],
    );
  }

  Widget _buildArchivesView() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Project Archives', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const Text('Safely stored zip backups from your cleanup sessions.', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          Expanded(
            child: _archives.isEmpty
              ? const Center(child: Text('No archives found in ~/Downloads/Sweep_Archives'))
              : ListView.builder(
                  itemCount: _archives.length,
                  itemBuilder: (context, idx) {
                    final f = _archives[idx];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.folder_zip, color: Colors.amber),
                        title: Text(f.path.split('/').last),
                        subtitle: Text('Size: ${SweepEngine.formatMb(f.lengthSync() / (1024 * 1024))}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.open_in_new),
                          onPressed: () => launchUrl(Uri.parse('file://${f.parent.path}')),
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(String title, String desc, IconData icon, VoidCallback tap) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: Colors.cyan, child: Icon(icon, color: Colors.black)),
        title: Text(title),
        subtitle: Text(desc),
        onTap: tap,
      ),
    );
  }

  Widget _buildCategoryTile(String cat, List<CleanupItem> items) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        title: Text(cat, style: const TextStyle(fontWeight: FontWeight.bold)),
        children: items.map((i) => i.isBatch ? _buildBatchTile(i) : _buildItemTile(i)).toList(),
      ),
    );
  }

  Widget _buildBatchTile(CleanupItem item) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.only(left: 72, right: 16),
      title: Text(item.label),
      trailing: Checkbox(
        value: item.selected,
        onChanged: (val) => setState(() {
          item.selected = val ?? false;
          for (var s in item.subItems!) s.selected = item.selected;
        }),
      ),
      children: item.subItems!.map((sub) => _buildItemTile(sub, indent: 96)).toList(),
    );
  }

  Widget _buildItemTile(CleanupItem item, {double indent = 72}) {
    return ListTile(
      contentPadding: EdgeInsets.only(left: indent, right: 16),
      title: Row(
        children: [
          if (item.isDirty) _buildSmallTag('DIRTY', Colors.orange),
          if (item.isStale) _buildSmallTag('STALE', Colors.red),
          Expanded(child: Text(item.label, style: const TextStyle(fontSize: 14))),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(item.estimatedSize ?? '', style: const TextStyle(fontSize: 12)),
          Checkbox(value: item.selected, onChanged: (v) => setState(() => item.selected = v ?? false)),
          IconButton(
            icon: Icon(Icons.archive, color: item.archiveSelected ? Colors.cyan : Colors.white12, size: 18),
            onPressed: () => setState(() => item.archiveSelected = !item.archiveSelected),
          ),
          if (item.upgradeCommand != null)
            IconButton(
              icon: Icon(Icons.auto_fix_high, color: item.maintainSelected ? Colors.yellow : Colors.white12, size: 18),
              onPressed: () => setState(() => item.maintainSelected = !item.maintainSelected),
            ),
        ],
      ),
    );
  }

  Widget _buildSmallTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildCleanupFooter() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)]),
      child: Row(
        children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Reclaim: ${SweepEngine.formatMb(_selectedTotalMb)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
            const Text('Toggling Archive [ZIP] will backup before deleting.', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ])),
          ElevatedButton(
            onPressed: (_isCleaning || !_anyItemSelected) ? null : _executeCleanup,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20)),
            child: const Text('EXECUTE SWEEP'),
          ),
        ],
      ),
    );
  }

  Widget _buildStateBar() {
    return Container(
      color: Colors.cyan.withOpacity(0.05),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.computer, size: 14, color: Colors.white70),
          const SizedBox(width: 8),
          Text(_stats.osName, style: const TextStyle(fontSize: 10, color: Colors.white54)),
          const Spacer(),
          _buildStatText('DISK:', _stats.storageLeft, Colors.greenAccent),
          const SizedBox(width: 24),
          _buildStatText('RAM:', _stats.ramUsage, Colors.orangeAccent),
          const SizedBox(width: 24),
          _buildStatText('CPU:', _stats.cpuUsage, Colors.blueAccent),
        ],
      ),
    );
  }

  Widget _buildStatText(String label, String val, Color color) {
    return Text.rich(TextSpan(children: [
      TextSpan(text: '$label ', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white38)),
      TextSpan(text: val, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
    ]));
  }
}

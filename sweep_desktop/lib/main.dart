import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'sweep_engine.dart';

void main() {
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
  final TextEditingController _pathController = TextEditingController();
  List<CleanupItem> _items = [];
  bool _isScanning = false;
  bool _isCleaning = false;
  double _progress = 0;
  String _currentStatus = '';
  double _totalReclaimedMb = 0;
  SystemStats _stats = SystemStats.empty();
  Timer? _statsTimer;

  @override
  void initState() {
    super.initState();
    _loadInitialPath();
    _startStatsMonitoring();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    super.dispose();
  }

  void _startStatsMonitoring() {
    _updateStats();
    _statsTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _updateStats();
    });
  }

  Future<void> _updateStats() async {
    final newStats = await SweepEngine.getSystemStats();
    if (mounted) {
      setState(() {
        _stats = newStats;
      });
    }
  }

  Future<void> _loadInitialPath() async {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    setState(() {
      _pathController.text = home;
    });
  }

  Future<void> _pickDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      setState(() {
        _pathController.text = selectedDirectory;
      });
      _scan();
    }
  }

  Future<void> _scan() async {
    if (_pathController.text.isEmpty) return;
    setState(() {
      _isScanning = true;
      _items = [];
    });

    try {
      final items = await SweepEngine.scan(_pathController.text, []);
      
      await Future.wait(items.map((item) async {
        if (item.category.startsWith('BIG FILES')) return;
        if (item.path != null) {
          item.estimatedSize = await SweepEngine.getDirSize(item.path!);
        } else if (item.isBatch && item.subItems != null) {
          double total = 0;
          final res = await Future.wait(item.subItems!.map((p) => SweepEngine.getDirSize(p.path!)));
          for (var s in res) total += SweepEngine.parseSizeToMb(s);
          if (total > 0) item.estimatedSize = SweepEngine.formatMb(total);
        }
      }));

      setState(() {
        _items = items;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan error: $e')));
      }
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  double get _selectedTotalMb {
    double total = 0;
    void calculate(List<CleanupItem> list) {
      for (var item in list) {
        if (item.isBatch && item.subItems != null) {
          calculate(item.subItems!);
        } else if (item.selected) {
          total += SweepEngine.parseSizeToMb(item.estimatedSize);
        }
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
          for (var s in item.subItems!) {
            if (s.selected || s.maintainSelected) { found = true; return; }
          }
        } else if (item.selected || item.maintainSelected) {
          found = true; return;
        }
      }
    }
    check(_items);
    return found;
  }

  Future<void> _executeCleanup() async {
    final selectedTasks = <CleanupItem>[];
    void collect(List<CleanupItem> list) {
      for (var i in list) {
        if (i.isBatch && i.subItems != null) {
          collect(i.subItems!);
        } else if (i.selected || i.maintainSelected) {
          selectedTasks.add(i);
        }
      }
    }
    collect(_items);

    if (selectedTasks.isEmpty) return;

    setState(() {
      _isCleaning = true;
      _progress = 0;
      _totalReclaimedMb = 0;
    });

    int completed = 0;
    for (var item in selectedTasks) {
      setState(() {
        _currentStatus = 'Processing: ${item.label}';
        _progress = completed / selectedTasks.length;
      });

      try {
        if (item.maintainSelected && item.upgradeCommand != null) {
          await Process.run(item.upgradeCommand!.split(' ')[0], item.upgradeCommand!.split(' ').sublist(1), workingDirectory: item.path, runInShell: true);
        }
        if (item.selected) {
          if (item.command != null) {
            await Process.run(item.command!.split(' ')[0], item.command!.split(' ').sublist(1), workingDirectory: item.path, runInShell: true);
          } else if (item.path != null) {
            if (FileSystemEntity.isDirectorySync(item.path!)) {
              await Directory(item.path!).delete(recursive: true);
            } else if (FileSystemEntity.isFileSync(item.path!)) {
              await File(item.path!).delete();
            }
          }
        }
      } catch (e) {}

      completed++;
      _totalReclaimedMb += SweepEngine.parseSizeToMb(item.estimatedSize);
    }

    setState(() {
      _isCleaning = false;
      _currentStatus = 'Finished! Reclaimed ${SweepEngine.formatMb(_totalReclaimedMb)}';
    });
    
    _scan();
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Colors.cyan),
            SizedBox(width: 12),
            Text('Sweep Guide'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Sweep is your ultimate cross-platform maintenance suite.', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _buildHelpSection('Cleanup', 'Select items or expand batches to clean build artifacts, caches, and large files.'),
                _buildHelpSection('Maintenance (M)', 'Click the magic wand icon to toggle maintenance mode, which upgrades dependencies while cleaning.'),
                _buildHelpSection('Health Check', 'Sweep automatically audits projects for outdated or vulnerable dependencies during scanning.'),
                _buildHelpSection('Individual Selection', 'Expand project batches to select/deselect specific projects.'),
                const Divider(height: 32),
                const Text('Built with love by Abdulrasol and Google Gemini AI.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.white54)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('GOT IT')),
        ],
      ),
    );
  }

  Widget _buildHelpSection(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
          Text(desc, style: const TextStyle(fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = <String, List<CleanupItem>>{};
    for (var item in _items) {
      categories.putIfAbsent(item.category, () => []).add(item);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('🧹 Sweep Console'),
        centerTitle: true,
        actions: [
          IconButton(onPressed: _showHelpDialog, icon: const Icon(Icons.help_outline)),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.2), Colors.black.withOpacity(0.0)],
          ),
        ),
        child: Column(
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
                        hintText: 'Enter path or use picker...',
                        prefixIcon: const Icon(Icons.folder_open, color: Colors.cyan),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search),
                          tooltip: 'Choose Directory',
                          onPressed: _pickDirectory,
                        ),
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyan,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _items.isEmpty
                  ? Center(
                      child: Opacity(
                        opacity: 0.5,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cleaning_services, size: 64),
                            const SizedBox(height: 16),
                            Text(_isScanning ? 'Analyzing your workspace...' : 'Scan a folder to find artifacts.'),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      children: categories.keys.map((cat) {
                        final catItems = categories[cat]!;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: ExpansionTile(
                            leading: Icon(_getIconForCategory(cat), color: Colors.cyan),
                            title: Text(cat, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                            subtitle: Text('${catItems.length} items detected'),
                            shape: const RoundedRectangleBorder(side: BorderSide.none),
                            children: catItems.map((item) {
                              if (item.isBatch && item.subItems != null) {
                                return _buildBatchTile(item);
                              }
                              return _buildItemTile(item);
                            }).toList(),
                          ),
                        );
                      }).toList(),
                    ),
            ),
            if (_isCleaning)
              Container(
                padding: const EdgeInsets.all(24),
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.cyan.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.cyan.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 16),
                        Expanded(child: Text(_currentStatus, style: const TextStyle(fontWeight: FontWeight.w500))),
                        Text('${(_progress * 100).toInt()}%'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: _progress, backgroundColor: Colors.white10),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Estimated Recovery: ${SweepEngine.formatMb(_selectedTotalMb)}',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                          ),
                          const Text('Individual items can be selected by expanding categories', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 60,
                      child: ElevatedButton(
                        onPressed: (_isCleaning || !_anyItemSelected) ? null : _executeCleanup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 8,
                        ),
                        child: const Text('CLEAN NOW', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              color: Colors.cyan.withOpacity(0.05),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  _buildStatItem(Icons.computer, _stats.osName, Colors.white70),
                  const Spacer(),
                  _buildStatItem(Icons.storage, 'Free Disk: ${_stats.storageLeft}', Colors.greenAccent),
                  const SizedBox(width: 24),
                  _buildStatItem(Icons.memory, 'RAM: ${_stats.ramUsage}', Colors.orangeAccent),
                  const SizedBox(width: 24),
                  _buildStatItem(Icons.speed, 'CPU: ${_stats.cpuUsage}', Colors.blueAccent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildBatchTile(CleanupItem item) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.only(left: 72, right: 16),
      title: Text(item.label, style: const TextStyle(fontSize: 14)),
      subtitle: Text(item.note ?? '', style: const TextStyle(fontSize: 11, color: Colors.white24)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(item.estimatedSize ?? '', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
          Checkbox(
            value: item.selected,
            onChanged: (val) {
              setState(() {
                item.selected = val ?? false;
                for (var s in item.subItems!) s.selected = item.selected;
              });
            },
          ),
        ],
      ),
      children: item.subItems!.map((sub) => _buildItemTile(sub, indent: 96)).toList(),
    );
  }

  Widget _buildItemTile(CleanupItem item, {double indent = 72}) {
    return ListTile(
      contentPadding: EdgeInsets.only(left: indent, right: 16),
      title: Row(
        children: [
          if (item.isStale) 
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
              child: const Text('STALE', style: TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          Expanded(child: Text(item.label, style: const TextStyle(fontSize: 14))),
        ],
      ),
      subtitle: Text(item.note ?? (item.path ?? ''), style: const TextStyle(fontSize: 11, color: Colors.white38), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(item.estimatedSize ?? '', style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 12, color: Colors.white70)),
          const SizedBox(width: 8),
          Checkbox(
            value: item.selected,
            activeColor: Colors.cyan,
            onChanged: (val) {
              setState(() {
                item.selected = val ?? false;
              });
            },
          ),
          if (item.upgradeCommand != null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.auto_fix_high, color: item.maintainSelected ? Colors.yellow : Colors.white12, size: 18),
              onPressed: () {
                setState(() {
                  item.maintainSelected = !item.maintainSelected;
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  IconData _getIconForCategory(String cat) {
    if (cat.contains('GLOBAL')) return Icons.public;
    if (cat.contains('FLUTTER')) return Icons.flutter_dash;
    if (cat.contains('NODE')) return Icons.javascript;
    if (cat.contains('PYTHON')) return Icons.code;
    if (cat.contains('BIG FILES')) return Icons.storage;
    return Icons.category;
  }
}

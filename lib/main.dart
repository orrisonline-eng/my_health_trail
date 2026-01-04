import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyHealthTrail',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Welcome to MyHealthTrail'),
    );
  }
}

/// A single health log entry.
class HealthEntry {
  final String id; // unique
  final String dateTimeIso; // ISO string
  final String bloodSugar; // mmol/L
  final String systolic; // mmHg
  final String diastolic; // mmHg
  final String weight; // kg
  final String notes;

  HealthEntry({
    required this.id,
    required this.dateTimeIso,
    required this.bloodSugar,
    required this.systolic,
    required this.diastolic,
    required this.weight,
    required this.notes,
  });

  DateTime? get dateTime => DateTime.tryParse(dateTimeIso);

  Map<String, dynamic> toMap() => {
        'id': id,
        'dateTimeIso': dateTimeIso,
        'bloodSugar': bloodSugar,
        'systolic': systolic,
        'diastolic': diastolic,
        'weight': weight,
        'notes': notes,
      };

  static HealthEntry fromMap(Map<String, dynamic> map) {
    return HealthEntry(
      id: map['id'] ?? '',
      dateTimeIso: map['dateTimeIso'] ?? '',
      bloodSugar: map['bloodSugar'] ?? '',
      systolic: map['systolic'] ?? '',
      diastolic: map['diastolic'] ?? '',
      weight: map['weight'] ?? '',
      notes: map['notes'] ?? '',
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const String _entriesKey = 'health_entries_list';
  static const String _profileKey = 'health_profile_name';

  final List<HealthEntry> _entries = [];
  final TextEditingController _profileController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _profileController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    await _loadProfileName();
    await _loadEntries();
  }

  // ✅ iPad share popover anchor (safe on iPhone/Android too)
  Rect _shareOrigin() {
    final box = context.findRenderObject() as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _loadProfileName() async {
    final prefs = await SharedPreferences.getInstance();
    _profileController.text = prefs.getString(_profileKey) ?? '';
  }

  Future<void> _saveProfileName(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, value);
  }

  Future<void> _loadEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final items = prefs.getStringList(_entriesKey) ?? [];

    setState(() {
      _entries.clear();
      for (final jsonStr in items) {
        try {
          final map = Map<String, dynamic>.from(jsonDecode(jsonStr));
          _entries.add(HealthEntry.fromMap(map));
        } catch (_) {
          // ignore corrupted rows
        }
      }
      _sortEntriesNewestFirst();
    });
  }

  Future<void> _saveEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final items = _entries.map((e) => jsonEncode(e.toMap())).toList();
    await prefs.setStringList(_entriesKey, items);
  }

  void _sortEntriesNewestFirst() {
    _entries.sort((a, b) {
      final da = a.dateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = b.dateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });
  }

  // ---------- Parsing / formatting helpers ----------

  double _parseNum(String s) {
    final cleaned = s.trim().replaceAll(',', '.').replaceAll(RegExp(r'[^0-9\.\-]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  int _parseIntSafe(String s) {
    final cleaned = s.trim().replaceAll(RegExp(r'[^0-9\-]'), '');
    return int.tryParse(cleaned) ?? 0;
  }

  String _fmtDateTime(DateTime d) {
    // yyyy-MM-dd HH:mm
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$y-$m-$day $hh:$mm';
  }

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  // ---------- Add entry dialog ----------

  Future<void> _addEntry() async {
    final result = await _showEntryDialog();
    if (result == null) return;

    final now = DateTime.now();
    final entry = HealthEntry(
      id: '${now.millisecondsSinceEpoch}',
      dateTimeIso: result.dateTimeIso,
      bloodSugar: result.bloodSugar,
      systolic: result.systolic,
      diastolic: result.diastolic,
      weight: result.weight,
      notes: result.notes,
    );

    setState(() {
      _entries.add(entry);
      _sortEntriesNewestFirst();
    });

    await _saveEntries();
    await _exportToCSV();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Health entry saved.')),
    );
  }

  Future<HealthEntry?> _showEntryDialog({HealthEntry? existing}) async {
    final bsController = TextEditingController(text: existing?.bloodSugar ?? '');
    final sysController = TextEditingController(text: existing?.systolic ?? '');
    final diaController = TextEditingController(text: existing?.diastolic ?? '');
    final wtController = TextEditingController(text: existing?.weight ?? '');
    final notesController = TextEditingController(text: existing?.notes ?? '');

    final dt = existing?.dateTime ?? DateTime.now();
    final dateController = TextEditingController(text: _fmtDate(dt));
    final timeController = TextEditingController(text: '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}');

    return showDialog<HealthEntry>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(existing == null ? 'Add Health Entry' : 'Edit Health Entry'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Date
                TextField(
                  controller: dateController,
                  decoration: const InputDecoration(
                    labelText: 'Date (yyyy-MM-dd)',
                    hintText: '2026-01-04',
                  ),
                ),
                const SizedBox(height: 10),

                // Time
                TextField(
                  controller: timeController,
                  decoration: const InputDecoration(
                    labelText: 'Time (HH:mm)',
                    hintText: '19:30',
                  ),
                ),
                const SizedBox(height: 12),

                // Blood sugar
                TextField(
                  controller: bsController,
                  decoration: const InputDecoration(
                    labelText: 'Blood sugar (mmol/L)',
                    hintText: 'e.g. 5.8',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 10),

                // Blood pressure
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: sysController,
                        decoration: const InputDecoration(
                          labelText: 'Systolic (mmHg)',
                          hintText: 'e.g. 120',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: diaController,
                        decoration: const InputDecoration(
                          labelText: 'Diastolic (mmHg)',
                          hintText: 'e.g. 80',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Weight
                TextField(
                  controller: wtController,
                  decoration: const InputDecoration(
                    labelText: 'Weight (kg)',
                    hintText: 'e.g. 78.4',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 10),

                // Notes
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'e.g. fasting, after meal, exercise',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                // Minimal validation (keep it simple)
                final dateStr = dateController.text.trim();
                final timeStr = timeController.text.trim();

                DateTime? parsed;
                try {
                  final parts = timeStr.split(':');
                  final hh = (parts.isNotEmpty) ? int.parse(parts[0]) : 0;
                  final mm = (parts.length > 1) ? int.parse(parts[1]) : 0;
                  final d = DateTime.parse(dateStr);
                  parsed = DateTime(d.year, d.month, d.day, hh, mm);
                } catch (_) {
                  parsed = null;
                }

                if (parsed == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid date/time.')),
                  );
                  return;
                }

                // store as ISO
                final iso = parsed.toIso8601String();

                Navigator.of(context).pop(
                  HealthEntry(
                    id: existing?.id ?? '',
                    dateTimeIso: iso,
                    bloodSugar: bsController.text.trim(),
                    systolic: sysController.text.trim(),
                    diastolic: diaController.text.trim(),
                    weight: wtController.text.trim(),
                    notes: notesController.text.trim(),
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  // ---------- CSV export / share ----------

  Future<void> _exportToCSV() async {
    try {
      final rows = <List<dynamic>>[
        ['Profile', 'DateTime', 'BloodSugar(mmol/L)', 'Systolic(mmHg)', 'Diastolic(mmHg)', 'Weight(kg)', 'Notes'],
      ];

      for (final e in _entries) {
        final dt = e.dateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        rows.add([
          _profileController.text.trim(),
          _fmtDateTime(dt),
          e.bloodSugar,
          e.systolic,
          e.diastolic,
          e.weight,
          e.notes,
        ]);
      }

      final csv = const ListToCsvConverter().convert(rows);
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/myhealthtrail_readings.csv';
      await File(path).writeAsString(csv);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _shareCSV() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/myhealthtrail_readings.csv';

    if (!await File(path).exists()) {
      await _exportToCSV();
    }

    if (await File(path).exists()) {
      await Share.shareXFiles(
        [XFile(path)],
        sharePositionOrigin: _shareOrigin(),
        text: 'MyHealthTrail readings (CSV)',
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No CSV file found.')),
      );
    }
  }

  // ---------- 3-month PDF report ----------

  List<HealthEntry> _entriesInLast3Months() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 2, 1); // 3-month window start

    final filtered = <HealthEntry>[];
    for (final e in _entries) {
      final dt = e.dateTime;
      if (dt == null) continue;
      if (!dt.isBefore(start) && !dt.isAfter(now)) filtered.add(e);
    }

    filtered.sort((a, b) {
      final da = a.dateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = b.dateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });

    return filtered;
  }

  Future<void> _export3MonthReportPdf() async {
    final items = _entriesInLast3Months();

    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No health entries found in the last 3 months.')),
      );
      return;
    }

    final now = DateTime.now();
    final periodStart = DateTime(now.year, now.month - 2, 1);
    final periodEnd = now;

    double avgSugar = 0;
    double avgWeight = 0;
    double avgSys = 0;
    double avgDia = 0;

    int sugarCount = 0, weightCount = 0, bpCount = 0;

    for (final e in items) {
      final bs = _parseNum(e.bloodSugar);
      if (bs > 0) {
        avgSugar += bs;
        sugarCount++;
      }
      final wt = _parseNum(e.weight);
      if (wt > 0) {
        avgWeight += wt;
        weightCount++;
      }
      final sys = _parseIntSafe(e.systolic);
      final dia = _parseIntSafe(e.diastolic);
      if (sys > 0 && dia > 0) {
        avgSys += sys;
        avgDia += dia;
        bpCount++;
      }
    }

    avgSugar = sugarCount == 0 ? 0 : (avgSugar / sugarCount);
    avgWeight = weightCount == 0 ? 0 : (avgWeight / weightCount);
    avgSys = bpCount == 0 ? 0 : (avgSys / bpCount);
    avgDia = bpCount == 0 ? 0 : (avgDia / bpCount);

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => [
          pw.Text(
            'MyHealthTrail - 3-Month Report',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Profile: ${_profileController.text.trim().isEmpty ? '(not set)' : _profileController.text.trim()}'),
          pw.Text('Period: ${_fmtDate(periodStart)} to ${_fmtDate(periodEnd)}'),
          pw.SizedBox(height: 12),

          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 0.8),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Summary', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                pw.Text('Total entries: ${items.length}'),
                pw.SizedBox(height: 6),
                pw.Text('Average blood sugar: ${avgSugar.toStringAsFixed(1)} mmol/L (from $sugarCount readings)'),
                pw.Text('Average blood pressure: ${avgSys.toStringAsFixed(0)}/${avgDia.toStringAsFixed(0)} mmHg (from $bpCount readings)'),
                pw.Text('Average weight: ${avgWeight.toStringAsFixed(1)} kg (from $weightCount readings)'),
              ],
            ),
          ),

          pw.SizedBox(height: 16),

          pw.Text(
            'Full entry list',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),

          pw.Table.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headers: const ['Date/Time', 'Sugar', 'BP', 'Weight', 'Notes'],
            data: items.map((e) {
              final dt = e.dateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bp = (e.systolic.trim().isEmpty && e.diastolic.trim().isEmpty)
                  ? ''
                  : '${e.systolic}/${e.diastolic}';
              return [
                _fmtDateTime(dt),
                e.bloodSugar,
                bp,
                e.weight,
                e.notes,
              ];
            }).toList(),
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FlexColumnWidth(2.0),
              1: const pw.FlexColumnWidth(1.1),
              2: const pw.FlexColumnWidth(1.1),
              3: const pw.FlexColumnWidth(1.1),
              4: const pw.FlexColumnWidth(2.7),
            },
          ),

          pw.SizedBox(height: 10),
          pw.Text(
            'Note: This report is for personal tracking and sharing with healthcare professionals. It is not a medical diagnosis.',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'myhealthtrail_3month_report_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final path = '${dir.path}/$fileName';

    await File(path).writeAsBytes(await doc.save());

    await Share.shareXFiles(
      [XFile(path)],
      sharePositionOrigin: _shareOrigin(),
      text: 'MyHealthTrail 3-month report (PDF)',
    );
  }

  // ---------- Clear all ----------

  Future<void> _confirmAndClearAll() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Permanently delete all entries?'),
            content: const Text(
              'These entries will be permanently deleted from this device.\n\n'
              'Please export/share your data before continuing.\n\n'
              'This will not delete anything you have already shared.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_entriesKey);

    setState(() => _entries.clear());
    await _exportToCSV();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All entries deleted.')),
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final countText = '${_entries.length} entries';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        elevation: 2,
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile Section
            Container(
              color: Colors.grey[100],
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Profile (optional)',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _profileController,
                    decoration: InputDecoration(
                      hintText: 'Enter your name or label...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                    onChanged: _saveProfileName,
                  ),
                ],
              ),
            ),

            // Features
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MyHealthTrail Features',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureRow('✅ Track blood sugar (mmol/L)'),
                  _buildFeatureRow('✅ Track blood pressure (mmHg)'),
                  _buildFeatureRow('✅ Track weight (kg)'),
                  _buildFeatureRow('✅ CSV export + sharing'),
                  _buildFeatureRow('✅ 3-month PDF report'),
                  _buildFeatureRow('✅ Secure local storage on device'),
                ],
              ),
            ),

            // Quick actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _addEntry,
                      icon: const Icon(Icons.add, size: 24),
                      label: const Text('Add Health Entry', style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _shareCSV,
                      icon: const Icon(Icons.table_chart, size: 24),
                      label: const Text('Share CSV File', style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _export3MonthReportPdf,
                      icon: const Icon(Icons.picture_as_pdf, size: 24),
                      label: const Text('Export 3-Month PDF Report', style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black87,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _confirmAndClearAll,
                      icon: const Icon(Icons.delete_forever, size: 24),
                      label: const Text('Clear All Entries', style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Entries list
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Your Readings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                      Text(
                        countText,
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  _entries.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(40),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Column(
                              children: [
                                Icon(Icons.monitor_heart, size: 64, color: Colors.grey),
                                SizedBox(height: 16),
                                Text(
                                  'No readings yet',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Tap "Add Health Entry" to get started!',
                                  style: TextStyle(fontSize: 14, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _entries.length,
                          itemBuilder: (context, index) {
                            final e = _entries[index];
                            final dt = e.dateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
                            final bp = (e.systolic.trim().isEmpty && e.diastolic.trim().isEmpty)
                                ? '—'
                                : '${e.systolic}/${e.diastolic}';

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                leading: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: Colors.teal.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.monitor_heart, color: Colors.teal),
                                ),
                                title: Text(
                                  _fmtDateTime(dt),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 6),
                                    Text('Blood sugar: ${e.bloodSugar.isEmpty ? "—" : e.bloodSugar} mmol/L'),
                                    Text('Blood pressure: $bp mmHg'),
                                    Text('Weight: ${e.weight.isEmpty ? "—" : e.weight} kg'),
                                    if (e.notes.trim().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          'Notes: ${e.notes}',
                                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () async {
                                    setState(() => _entries.removeAt(index));
                                    await _saveEntries();
                                    await _exportToCSV();
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Entry deleted')),
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, color: Colors.black87),
      ),
    );
  }
}
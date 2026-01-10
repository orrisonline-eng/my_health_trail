// --------------------  main.dart  --------------------
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pro_limits.dart'; // helper with usage limits

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
        useMaterial3: false, // classic Material look
      ),
      home: const MyHomePage(title: 'Welcome to MyHealthTrail'),
    );
  }
}

// ─────────────────────────  MODEL  ─────────────────────────
class HealthEntry {
  final String id;
  final String dateTimeIso;
  final String bloodSugar;
  final String systolic;
  final String diastolic;
  final String weight;
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

  static HealthEntry fromMap(Map<String, dynamic> map) => HealthEntry(
        id: map['id'] ?? '',
        dateTimeIso: map['dateTimeIso'] ?? '',
        bloodSugar: map['bloodSugar'] ?? '',
        systolic: map['systolic'] ?? '',
        diastolic: map['diastolic'] ?? '',
        weight: map['weight'] ?? '',
        notes: map['notes'] ?? '',
      );
}

// ─────────────────────────  HOME  ─────────────────────────
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const _entriesKey = 'health_entries_list';
  static const _profileKey = 'health_profile_name';

  final _entries = <HealthEntry>[];
  final _profileController = TextEditingController();

  // ── lifecycle ──
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

  // anchor for iPad share sheet
  Rect _shareOrigin() {
    final box = context.findRenderObject() as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  // ── persistence ──
  Future<void> _loadProfileName() async {
    final p = await SharedPreferences.getInstance();
    _profileController.text = p.getString(_profileKey) ?? '';
  }

  Future<void> _saveProfileName(String v) async =>
      (await SharedPreferences.getInstance()).setString(_profileKey, v);

  Future<void> _loadEntries() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_entriesKey) ?? [];
    setState(() {
      _entries
        ..clear()
        ..addAll(list
            .map((s) =>
                HealthEntry.fromMap(Map<String, dynamic>.from(jsonDecode(s))))
            .toList());
      _sortNewestFirst();
    });
  }

  Future<void> _saveEntries() async =>
      (await SharedPreferences.getInstance()).setStringList(
          _entriesKey, _entries.map((e) => jsonEncode(e.toMap())).toList());

  void _sortNewestFirst() {
    _entries.sort((a, b) =>
        (b.dateTime ?? DateTime(0)).compareTo(a.dateTime ?? DateTime(0)));
  }

  // ── dialogs ──
  void _showUpgrade(String msg) => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Upgrade to Pro'),
          content: Text(msg),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Not now')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Upgrade')),
          ],
        ),
      );

  // ─────────────────────────  ADD ENTRY  ─────────────────────────
  Future<void> _addEntry() async {
    if (!await ProLimits.canAddEntry()) {
      _showUpgrade(
          'You’ve reached 10 entries this month on the Free plan.\n\nUpgrade to Pro for unlimited entries.');
      return;
    }

    final entry = await _showEntryDialog();
    if (entry == null) return;

    setState(() {
      _entries.add(entry);
      _sortNewestFirst();
    });

    await _saveEntries();
    await _exportToCSV();
    await ProLimits.incrementEntries();

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Health entry saved.')));
  }

  // ── entry dialog ──
  Future<HealthEntry?> _showEntryDialog({HealthEntry? existing}) async {
    final sugar = TextEditingController(text: existing?.bloodSugar ?? '');
    final sys = TextEditingController(text: existing?.systolic ?? '');
    final dia = TextEditingController(text: existing?.diastolic ?? '');
    final weight = TextEditingController(text: existing?.weight ?? '');
    final notes = TextEditingController(text: existing?.notes ?? '');

    return showDialog<HealthEntry>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Health Entry'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Blood sugar
              TextField(
                controller: sugar,
                decoration: const InputDecoration(
                  labelText: 'Blood sugar (mmol/L)',
                  hintText: 'e.g. 5.8',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              // Blood pressure
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Blood Pressure (mmHg)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: sys,
                      decoration: const InputDecoration(
                        labelText: 'Systolic',
                        hintText: 'e.g. 120',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: dia,
                      decoration: const InputDecoration(
                        labelText: 'Diastolic',
                        hintText: 'e.g. 80',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Weight
              TextField(
                controller: weight,
                decoration: const InputDecoration(
                  labelText: 'Weight (kg)',
                  hintText: 'e.g. 78.4',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              // Notes
              TextField(
                controller: notes,
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
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final now = DateTime.now();
              Navigator.pop(
                context,
                HealthEntry(
                  id: existing?.id ?? '${now.millisecondsSinceEpoch}',
                  dateTimeIso: now.toIso8601String(),
                  bloodSugar: sugar.text.trim(),
                  systolic: sys.text.trim(),
                  diastolic: dia.text.trim(),
                  weight: weight.text.trim(),
                  notes: notes.text.trim(),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // -------------- CSV Export --------------
  Future<void> _exportToCSV() async {
    final rows = [
      [
        'Profile',
        'DateTime',
        'BloodSugar(mmol/L)',
        'Systolic(mmHg)',
        'Diastolic(mmHg)',
        'Weight(kg)',
        'Notes'
      ],
      ..._entries.map((e) => [
            _profileController.text,
            e.dateTimeIso,
            e.bloodSugar,
            e.systolic,
            e.diastolic,
            e.weight,
            e.notes
          ])
    ];
    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/myhealthtrail_readings.csv');
    await file.writeAsString(csv);
  }

  Future<void> _shareCSV() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/myhealthtrail_readings.csv');
    if (!await file.exists()) await _exportToCSV();
    await Share.shareXFiles(
      [XFile(file.path)],
      sharePositionOrigin: _shareOrigin(),
      text: 'MyHealthTrail readings (CSV)',
    );
  }

  // -------------- PDF Export (1/month) --------------
  List<HealthEntry> _entriesInLast3Months() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 2, 1);
    return _entries
        .where((e) =>
            e.dateTime != null &&
            !e.dateTime!.isBefore(start) &&
            !e.dateTime!.isAfter(now))
        .toList();
  }

  Future<void> _export3MonthReportPdf() async {
    if (!await ProLimits.canExportPdf()) {
      _showUpgrade(
          'You’ve reached your 1 free PDF export this month.\n\nUpgrade to Pro for unlimited reports.');
      return;
    }

    final items = _entriesInLast3Months();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No health entries found in the last 3 months.')));
      return;
    }

    final doc = pw.Document();
    doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Center(
            child: pw.Text('MyHealthTrail - ${items.length} entries'))));

    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        '${dir.path}/myhealthtrail_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await doc.save());
    await Share.shareXFiles(
      [XFile(file.path)],
      sharePositionOrigin: _shareOrigin(),
      text: 'MyHealthTrail 3-Month Report (PDF)',
    );
    await ProLimits.incrementPdfExports();
  }

  // -------------- Clear All (unlimited) --------------
  Future<void> _confirmAndClearAll() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete all entries?'),
            content: const Text(
                'These entries will be permanently deleted from this device.\n\nPlease export your data first if needed.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;

    if (!ok) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_entriesKey);
    setState(() => _entries.clear());
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('All entries deleted.')));
  }

  // -------------- UI --------------
  @override
  Widget build(BuildContext context) {
    final countText = '${_entries.length} entries';
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile
            const Text('Profile (optional)',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal)),
            const SizedBox(height: 8),
            TextField(
              controller: _profileController,
              decoration: InputDecoration(
                hintText: 'Enter your name or label...',
                filled: true,
                fillColor: Colors.white,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: _saveProfileName,
            ),
            const SizedBox(height: 24),

            // Features
            const Text('MyHealthTrail Features',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal)),
            const SizedBox(height: 12),
            _buildFeatureRow('✅ Track blood sugar (mmol/L)'),
            _buildFeatureRow('✅ Track blood pressure (mmHg)'),
            _buildFeatureRow('✅ Track weight (kg)'),
            _buildFeatureRow('✅ CSV export + sharing'),
            _buildFeatureRow('✅ 3-month PDF report'),
            _buildFeatureRow('✅ Secure local storage on device'),
            const SizedBox(height: 24),

            // Quick Actions
            const Text('Quick Actions',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal)),
            const SizedBox(height: 16),
            _buildActionButton(
                Colors.teal, Icons.add, 'Add Health Entry', _addEntry),
            const SizedBox(height: 12),
            _buildActionButton(
                Colors.green, Icons.table_chart, 'Share CSV File', _shareCSV),
            const SizedBox(height: 12),
            _buildActionButton(Colors.black, Icons.picture_as_pdf,
                'Export 3-Month PDF Report', _export3MonthReportPdf),
            const SizedBox(height: 12),
            _buildActionButton(Colors.red, Icons.delete_forever,
                'Clear All Entries', _confirmAndClearAll),
            const SizedBox(height: 24),
            const Center(
              child: Text(
                'Free plan: 10 entries / month • 1 PDF export / month',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text,
            style: const TextStyle(fontSize: 15, color: Colors.black87)),
      );

  Widget _buildActionButton(
      Color color, IconData icon, String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 24),
        label: Text(label, style: const TextStyle(fontSize: 16)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

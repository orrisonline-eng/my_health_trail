import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pro_limits.dart';

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
        useMaterial3: false,
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

// ─────────────────────────  HOME PAGE  ─────────────────────────
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const _entriesKey = 'health_entries_list';
  static const _profileKey = 'health_profile_name';
  static const _nhsKey = 'health_nhs_number';

  final _entries = <HealthEntry>[];
  final _profileController = TextEditingController();
  final _nhsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _profileController.dispose();
    _nhsController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    await _loadProfileData();
    await _loadEntries();
  }

  Rect _shareOrigin() {
    final box = context.findRenderObject() as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  // ── Persistence ──
  Future<void> _loadProfileData() async {
    final p = await SharedPreferences.getInstance();
    _profileController.text = p.getString(_profileKey) ?? '';
    _nhsController.text = p.getString(_nhsKey) ?? '';
  }

  Future<void> _saveProfileName(String v) async =>
      (await SharedPreferences.getInstance()).setString(_profileKey, v);

  Future<void> _saveNhsNumber(String v) async =>
      (await SharedPreferences.getInstance()).setString(_nhsKey, v);

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

  // ── Dialogs ──
  void _showUpgrade(String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Upgrade to Pro'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }

  void _showValidationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // ─────────────────────────  ADD ENTRY  ─────────────────────────
  Future<void> _addEntry() async {
    if (!await ProLimits.canAddEntry()) {
      _showUpgrade(
          'You\'ve reached 10 entries this month on the Free plan.\n\nUpgrade to Pro for unlimited entries.');
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

  Future<HealthEntry?> _showEntryDialog({HealthEntry? existing}) async {
    final sugar = TextEditingController(text: existing?.bloodSugar ?? '');
    final sys = TextEditingController(text: existing?.systolic ?? '');
    final dia = TextEditingController(text: existing?.diastolic ?? '');
    final weight = TextEditingController(text: existing?.weight ?? '');
    final notes = TextEditingController(text: existing?.notes ?? '');

    return showDialog<HealthEntry>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Health Entry'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              // Validate at least one value
              if (sugar.text.trim().isEmpty &&
                  sys.text.trim().isEmpty &&
                  dia.text.trim().isEmpty &&
                  weight.text.trim().isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter at least one health reading'),
                  ),
                );
                return;
              }

              final now = DateTime.now();
              Navigator.pop(
                dialogContext,
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

  // ─────────────────────────  CSV EXPORT  ─────────────────────────
  Future<void> _exportToCSV() async {
    final rows = [
      [
        'Profile',
        'NHS Number',
        'DateTime',
        'BloodSugar(mmol/L)',
        'Systolic(mmHg)',
        'Diastolic(mmHg)',
        'Weight(kg)',
        'Notes'
      ],
      ..._entries.map((e) => [
            _profileController.text,
            _nhsController.text,
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

  // ─────────────────────────  PDF EXPORT  ─────────────────────────
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
          'You\'ve reached your 1 free PDF export this month.\n\nUpgrade to Pro for unlimited reports.');
      return;
    }

    final items = _entriesInLast3Months();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No health entries found in the last 3 months.')));
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final pdf = _buildHealthReportPdf(items);
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
          '${dir.path}/myhealthtrail_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(await pdf.save());

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      await Share.shareXFiles(
        [XFile(file.path)],
        sharePositionOrigin: _shareOrigin(),
        text: 'MyHealthTrail 3-Month Health Report',
      );
      await ProLimits.incrementPdfExports();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    }
  }

  pw.Document _buildHealthReportPdf(List<HealthEntry> items) {
    final doc = pw.Document();
    final now = DateTime.now();
    final profileName = _profileController.text.trim();
    final nhsNumber = _nhsController.text.trim();
    final stats = _calculateStats(items);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (context) => _buildPdfHeader(profileName, nhsNumber, now),
        footer: (context) => _buildPdfFooter(context),
        build: (context) => [
          _buildSummarySection(stats, items.length),
          pw.SizedBox(height: 20),

          // Blood Sugar
          if (items.any((e) => e.bloodSugar.isNotEmpty)) ...[
            _buildSectionTitle('Blood Sugar Readings', PdfColors.red),
            _buildBloodSugarTable(items),
            pw.SizedBox(height: 20),
          ],
          // Blood Pressure
          if (items
              .any((e) => e.systolic.isNotEmpty || e.diastolic.isNotEmpty)) ...[
            _buildSectionTitle('Blood Pressure Readings', PdfColors.blue),
            _buildBloodPressureTable(items),
            pw.SizedBox(height: 20),
          ],

          // Weight
          if (items.any((e) => e.weight.isNotEmpty)) ...[
            _buildSectionTitle('Weight Readings', PdfColors.green),
            _buildWeightTable(items),
            pw.SizedBox(height: 20),
          ],

          // Disclaimer
          _buildDisclaimer(),
        ],
      ),
    );

    return doc;
  }

  // ─────────────────────────  PDF COMPONENTS  ─────────────────────────

  pw.Widget _buildPdfHeader(
      String profileName, String nhsNumber, DateTime now) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 20),
      decoration: const pw.BoxDecoration(
        border:
            pw.Border(bottom: pw.BorderSide(color: PdfColors.teal, width: 2)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'MyHealthTrail',
                style: pw.TextStyle(
                  fontSize: 28,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.teal,
                ),
              ),
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: PdfColors.teal50,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  'HEALTH REPORT',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.teal,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (profileName.isNotEmpty)
                    pw.Text(
                      'Name: $profileName',
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                  if (nhsNumber.isNotEmpty)
                    pw.Text(
                      'Patient Ref: $nhsNumber',
                      style: const pw.TextStyle(fontSize: 11),
                    ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Generated: ${_formatDate(now)}',
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                  pw.Text(
                    'Period: Last 3 Months',
                    style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfFooter(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated by MyHealthTrail App',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSummarySection(Map<String, dynamic> stats, int totalEntries) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColors.teal50,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.teal100),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Summary Overview',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.teal,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _buildStatBox('Total Entries', '$totalEntries', PdfColors.teal),
              if (stats['avgBloodSugar'] != null)
                _buildStatBox('Avg Blood Sugar',
                    '${stats['avgBloodSugar']} mmol/L', PdfColors.red),
              if (stats['avgSystolic'] != null && stats['avgDiastolic'] != null)
                _buildStatBox(
                    'Avg BP',
                    '${stats['avgSystolic']}/${stats['avgDiastolic']} mmHg',
                    PdfColors.blue),
              if (stats['avgWeight'] != null)
                _buildStatBox(
                    'Avg Weight', '${stats['avgWeight']} kg', PdfColors.green),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildStatBox(String label, String value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSectionTitle(String title, PdfColor color) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 14,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }

  pw.Widget _buildBloodSugarTable(List<HealthEntry> items) {
    final filtered = items.where((e) => e.bloodSugar.isNotEmpty).toList();

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(1.5),
        2: const pw.FlexColumnWidth(1.5),
        3: const pw.FlexColumnWidth(1),
        4: const pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.red50),
          children: [
            _tableHeader('Date'),
            _tableHeader('Time'),
            _tableHeader('Value (mmol/L)'),
            _tableHeader('Status'),
            _tableHeader('Notes'),
          ],
        ),
        ...filtered.map((e) {
          final status = _getBloodSugarStatus(e.bloodSugar);
          return pw.TableRow(
            children: [
              _tableCell(_formatDateOnly(e.dateTime)),
              _tableCell(_formatTimeOnly(e.dateTime)),
              _tableCell(e.bloodSugar),
              _statusCell(status),
              _tableCell(e.notes),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _buildBloodPressureTable(List<HealthEntry> items) {
    final filtered = items
        .where((e) => e.systolic.isNotEmpty || e.diastolic.isNotEmpty)
        .toList();

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(1.5),
        2: const pw.FlexColumnWidth(1.5),
        3: const pw.FlexColumnWidth(1),
        4: const pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blue50),
          children: [
            _tableHeader('Date'),
            _tableHeader('Time'),
            _tableHeader('Reading (mmHg)'),
            _tableHeader('Status'),
            _tableHeader('Notes'),
          ],
        ),
        ...filtered.map((e) {
          final status = _getBPStatus(e.systolic, e.diastolic);
          return pw.TableRow(
            children: [
              _tableCell(_formatDateOnly(e.dateTime)),
              _tableCell(_formatTimeOnly(e.dateTime)),
              _tableCell('${e.systolic}/${e.diastolic}'),
              _statusCell(status),
              _tableCell(e.notes),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _buildWeightTable(List<HealthEntry> items) {
    final filtered = items.where((e) => e.weight.isNotEmpty).toList();

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(1.5),
        2: const pw.FlexColumnWidth(1.5),
        3: const pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.green50),
          children: [
            _tableHeader('Date'),
            _tableHeader('Time'),
            _tableHeader('Weight (kg)'),
            _tableHeader('Notes'),
          ],
        ),
        ...filtered.map((e) => pw.TableRow(
              children: [
                _tableCell(_formatDateOnly(e.dateTime)),
                _tableCell(_formatTimeOnly(e.dateTime)),
                _tableCell(e.weight),
                _tableCell(e.notes),
              ],
            )),
      ],
    );
  }

  pw.Widget _tableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      ),
    );
  }

  pw.Widget _tableCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 9)),
    );
  }

  pw.Widget _statusCell(String status) {
    PdfColor bgColor;
    PdfColor textColor;

    switch (status.toLowerCase()) {
      case 'low':
        bgColor = PdfColors.orange100;
        textColor = PdfColors.orange900;
        break;
      case 'high':
        bgColor = PdfColors.red100;
        textColor = PdfColors.red900;
        break;
      case 'elevated':
        bgColor = PdfColors.yellow100;
        textColor = PdfColors.orange800;
        break;
      case 'normal':
        bgColor = PdfColors.green100;
        textColor = PdfColors.green900;
        break;
      default:
        bgColor = PdfColors.grey100;
        textColor = PdfColors.grey700;
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      margin: const pw.EdgeInsets.all(2),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Center(
        child: pw.Text(
          status,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: textColor,
          ),
        ),
      ),
    );
  }

  pw.Widget _buildDisclaimer() {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 20),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.orange),
        borderRadius: pw.BorderRadius.circular(4),
        color: PdfColors.orange50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Medical Disclaimer',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.orange900,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'This report is for informational purposes only and does not constitute '
            'medical advice, diagnosis, or treatment. The status indicators (Normal, High, Low) '
            'are based on general guidelines and may not apply to your specific health situation. '
            'Always consult your healthcare provider for medical decisions.',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Reference Ranges:\n'
            '• Blood Sugar: Normal 4.0-7.0 mmol/L | High >7.0 | Low <4.0\n'
            '• Blood Pressure: Normal <120/80 mmHg | Elevated 120-129 | High ≥130/80',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────  HELPER METHODS  ─────────────────────────

  Map<String, dynamic> _calculateStats(List<HealthEntry> items) {
    final stats = <String, dynamic>{};

    // Blood Sugar
    final sugarValues = items
        .where((e) => e.bloodSugar.isNotEmpty)
        .map((e) => double.tryParse(e.bloodSugar))
        .whereType<double>()
        .toList();

    if (sugarValues.isNotEmpty) {
      stats['avgBloodSugar'] =
          (sugarValues.reduce((a, b) => a + b) / sugarValues.length)
              .toStringAsFixed(1);
    }

    // Blood Pressure
    final sysValues = items
        .where((e) => e.systolic.isNotEmpty)
        .map((e) => int.tryParse(e.systolic))
        .whereType<int>()
        .toList();

    final diaValues = items
        .where((e) => e.diastolic.isNotEmpty)
        .map((e) => int.tryParse(e.diastolic))
        .whereType<int>()
        .toList();

    if (sysValues.isNotEmpty) {
      stats['avgSystolic'] =
          (sysValues.reduce((a, b) => a + b) / sysValues.length).round();
    }

    if (diaValues.isNotEmpty) {
      stats['avgDiastolic'] =
          (diaValues.reduce((a, b) => a + b) / diaValues.length).round();
    }

    // Weight
    final weightValues = items
        .where((e) => e.weight.isNotEmpty)
        .map((e) => double.tryParse(e.weight))
        .whereType<double>()
        .toList();

    if (weightValues.isNotEmpty) {
      stats['avgWeight'] =
          (weightValues.reduce((a, b) => a + b) / weightValues.length)
              .toStringAsFixed(1);
    }

    return stats;
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatDateOnly(DateTime? date) {
    if (date == null) return '-';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatTimeOnly(DateTime? date) {
    if (date == null) return '-';
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _getBloodSugarStatus(String value) {
    final v = double.tryParse(value);
    if (v == null) return '-';
    if (v < 4.0) return 'Low';
    if (v > 7.0) return 'High';
    return 'Normal';
  }

  String _getBPStatus(String systolic, String diastolic) {
    final sys = int.tryParse(systolic);
    final dia = int.tryParse(diastolic);
    if (sys == null || dia == null) return '-';

    if (sys < 90 || dia < 60) return 'Low';
    if (sys >= 140 || dia >= 90) return 'High';
    if (sys >= 120 || dia >= 80) return 'Elevated';
    return 'Normal';
  }

  // ─────────────────────────  CLEAR ALL  ─────────────────────────

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
                child: const Text('Cancel'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
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

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('All entries deleted.')));
  }

  // ─────────────────────────  UI BUILD  ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showAboutDialog,
            tooltip: 'About',
          ),
        ],
      ),
      body: Column(
        children: [
          // DEV MODE BANNER
          if (ProLimits.devMode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.orange,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.developer_mode, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'DEV MODE - Limits Disabled',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          // MAIN CONTENT
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildProfileSection(),
                  const SizedBox(height: 24),
                  _buildFeaturesSection(),
                  const SizedBox(height: 24),
                  _buildActionsSection(),
                  const SizedBox(height: 24),
                  if (_entries.isNotEmpty) ...[
                    _buildRecentEntriesSection(),
                    const SizedBox(height: 24),
                  ],
                  _buildFooter(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Profile',
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
                labelText: 'Name (optional)',
                hintText: 'Enter your name...',
                prefixIcon: const Icon(Icons.person_outline),
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: _saveProfileName,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nhsController,
              decoration: InputDecoration(
                labelText: 'Patient Reference (optional)',
                hintText: 'Enter your patient reference...',
                prefixIcon: const Icon(Icons.badge_outlined),
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                helperText:
                    'For your reference only. Stored securely on device.',
                helperStyle: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
              onChanged: _saveNhsNumber,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturesSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
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
            _buildFeatureRow(
                Icons.water_drop, 'Track blood sugar (mmol/L)', Colors.red),
            _buildFeatureRow(
                Icons.favorite, 'Track blood pressure (mmHg)', Colors.blue),
            _buildFeatureRow(
                Icons.monitor_weight, 'Track weight (kg)', Colors.green),
            _buildFeatureRow(
                Icons.table_chart, 'CSV export + sharing', Colors.orange),
            _buildFeatureRow(Icons.picture_as_pdf, '3-month PDF health report',
                Colors.indigo),
            _buildFeatureRow(
                Icons.lock, 'Secure local storage on device', Colors.teal),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsSection() {
    return Column(
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
        _buildActionButton(
            Colors.teal, Icons.add, 'Add Health Entry', _addEntry),
        const SizedBox(height: 12),
        _buildActionButton(
            Colors.green, Icons.table_chart, 'Share CSV File', _shareCSV),
        const SizedBox(height: 12),
        _buildActionButton(Colors.indigo, Icons.picture_as_pdf,
            'Export 3-Month PDF Report', _export3MonthReportPdf),
        const SizedBox(height: 12),
        _buildActionButton(Colors.red, Icons.delete_forever,
            'Clear All Entries', _confirmAndClearAll),
      ],
    );
  }

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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
      ),
    );
  }

  Widget _buildRecentEntriesSection() {
    final recentEntries = _entries.take(5).toList();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Entries',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
                Text(
                  '${_entries.length} total',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            ...recentEntries.map((entry) => _buildEntryTile(entry)),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryTile(HealthEntry entry) {
    final values = <String>[];
    if (entry.bloodSugar.isNotEmpty) {
      values.add('🩸 ${entry.bloodSugar} mmol/L');
    }
    if (entry.systolic.isNotEmpty && entry.diastolic.isNotEmpty) {
      values.add('❤️ ${entry.systolic}/${entry.diastolic} mmHg');
    }
    if (entry.weight.isNotEmpty) {
      values.add('⚖️ ${entry.weight} kg');
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date/Time
          SizedBox(
            width: 85,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDateOnly(entry.dateTime),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
                Text(
                  _formatTimeOnly(entry.dateTime),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Values
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: values
                      .map((v) => Text(v, style: const TextStyle(fontSize: 13)))
                      .toList(),
                ),
                if (entry.notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      entry.notes,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Delete button
          IconButton(
            icon: Icon(Icons.delete_outline, size: 20, color: Colors.grey[400]),
            onPressed: () => _deleteEntry(entry),
            tooltip: 'Delete entry',
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEntry(HealthEntry entry) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete entry?'),
            content:
                Text('Delete entry from ${_formatDateOnly(entry.dateTime)}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    setState(() {
      _entries.removeWhere((e) => e.id == entry.id);
    });
    await _saveEntries();
    await _exportToCSV();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Entry deleted.')),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        const Divider(),
        const SizedBox(height: 8),
        if (ProLimits.devMode)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange[100],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.orange),
            ),
            child: const Text(
              '⚠️ Dev Mode: All limits bypassed',
              style: TextStyle(fontSize: 11, color: Colors.orange),
            ),
          )
        else
          Text(
            'Free plan: 10 entries/month • 1 PDF export/month',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 4),
        if (!ProLimits.devMode)
          TextButton(
            onPressed: () => _showUpgrade(
                'Upgrade to Pro for unlimited entries and PDF exports!'),
            child: const Text('Upgrade to Pro', style: TextStyle(fontSize: 13)),
          ),
        const SizedBox(height: 8),
        Text(
          'Your data is stored securely on this device only.',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.favorite, color: Colors.teal),
            SizedBox(width: 8),
            Text('MyHealthTrail'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Version 1.0.0',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              Text(
                'Track your blood sugar, blood pressure, and weight easily. '
                'All data is stored securely on your device.',
              ),
              SizedBox(height: 16),
              Text(
                '⚠️ Medical Disclaimer',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.orange),
              ),
              SizedBox(height: 4),
              Text(
                'This app is for personal tracking only and does not provide '
                'medical advice, diagnosis, or treatment. Always consult your '
                'healthcare provider for medical decisions.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showPrivacyPolicy();
            },
            child: const Text('Privacy Policy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Privacy Policy'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Data Collection',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text(
                '• Health data (blood sugar, blood pressure, weight)\n'
                '• Optional: Name and Patient Reference for your reference\n'
                '• All data stored locally on your device only',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 12),
              Text('Data Storage',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text(
                'All health data is stored locally on your device. '
                'We do not have access to your data. No data is sent '
                'to any servers.',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 12),
              Text('Data Sharing',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text(
                'We do NOT share your data with any third parties. '
                'You can export your data via email using the CSV or PDF '
                'export features.',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 12),
              Text('Data Deletion',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text(
                'You can delete individual entries or all data at any time '
                'through the app. Uninstalling the app removes all stored data.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

// lib/main.dart
/*
  MyHealthTrail
  --------------
  Entry point for the MyHealthTrail application.

  Purpose:
  - App bootstrap and global configuration
  - Initialises Flutter bindings
  - Sets up Pro purchase verification with backend
  - Launches the main application widget

  Project: MyHealthTrail
*/

import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'app_links.dart';
import 'pro_iap.dart';
import 'widgets/legal_links.dart';

const String trialStartKey = 'trial_start';
const String trialInfoShownKey = 'trial_info_shown';
const int trialDays = 7;

Future<void> startTrialIfNeeded() async {
  final prefs = await SharedPreferences.getInstance();
  if (!prefs.containsKey(trialStartKey)) {
    await prefs.setString(trialStartKey, DateTime.now().toIso8601String());
  }
}

Future<bool> isTrialActive() async {
  final prefs = await SharedPreferences.getInstance();
  final startStr = prefs.getString(trialStartKey);
  if (startStr == null) return true;

  final startDate = DateTime.parse(startStr);
  final now = DateTime.now();
  return now.isBefore(startDate.add(const Duration(days: trialDays)));
}

Future<int> trialDaysLeft() async {
  final prefs = await SharedPreferences.getInstance();
  final startStr = prefs.getString(trialStartKey);
  if (startStr == null) return trialDays;

  final startDate = DateTime.parse(startStr);
  final endDate = startDate.add(const Duration(days: trialDays));
  final now = DateTime.now();
  final daysLeft = endDate.difference(now).inDays;
  return daysLeft > 0 ? daysLeft : 0;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await startTrialIfNeeded();
  await ProIap.init();
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

class EntryEditorPage extends StatefulWidget {
  const EntryEditorPage({
    super.key,
    this.existing,
    required this.formatDateOnly,
  });

  final HealthEntry? existing;
  final String Function(DateTime?) formatDateOnly;

  @override
  State<EntryEditorPage> createState() => _EntryEditorPageState();
}

class _EntryEditorPageState extends State<EntryEditorPage> {
  late final TextEditingController _sugarController;
  late final TextEditingController _systolicController;
  late final TextEditingController _diastolicController;
  late final TextEditingController _weightController;
  late final TextEditingController _notesController;

  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final existingDate = widget.existing?.dateTime ?? DateTime.now();

    _selectedDate = DateTime(
      existingDate.year,
      existingDate.month,
      existingDate.day,
    );

    _sugarController =
        TextEditingController(text: widget.existing?.bloodSugar ?? '');
    _systolicController =
        TextEditingController(text: widget.existing?.systolic ?? '');
    _diastolicController =
        TextEditingController(text: widget.existing?.diastolic ?? '');
    _weightController =
        TextEditingController(text: widget.existing?.weight ?? '');
    _notesController =
        TextEditingController(text: widget.existing?.notes ?? '');
  }

  @override
  void dispose() {
    _sugarController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    _weightController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );

    if (!mounted || picked == null) return;

    setState(() {
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  void _save() {
    if (_sugarController.text.trim().isEmpty &&
        _systolicController.text.trim().isEmpty &&
        _diastolicController.text.trim().isEmpty &&
        _weightController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter at least one health reading'),
        ),
      );
      return;
    }

    final baseTime = widget.existing?.dateTime ?? DateTime.now();
    final entryDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      baseTime.hour,
      baseTime.minute,
      baseTime.second,
      baseTime.millisecond,
      baseTime.microsecond,
    );

    Navigator.of(context).pop(
      HealthEntry(
        id: widget.existing?.id ?? '${DateTime.now().millisecondsSinceEpoch}',
        dateTimeIso: entryDateTime.toIso8601String(),
        bloodSugar: _sugarController.text.trim(),
        systolic: _systolicController.text.trim(),
        diastolic: _diastolicController.text.trim(),
        weight: _weightController.text.trim(),
        notes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Health Entry' : 'Add Health Entry'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Entry date',
                prefixIcon: Icon(Icons.calendar_today_outlined),
                border: OutlineInputBorder(),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(widget.formatDateOnly(_selectedDate)),
                  const Icon(Icons.edit_calendar_outlined, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sugarController,
            decoration: const InputDecoration(
              labelText: 'Blood sugar (mmol/L)',
              hintText: 'e.g. 5.8',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          const Text(
            'Blood Pressure (mmHg)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.teal,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _systolicController,
                  decoration: const InputDecoration(
                    labelText: 'Systolic',
                    hintText: 'e.g. 120',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _diastolicController,
                  decoration: const InputDecoration(
                    labelText: 'Diastolic',
                    hintText: 'e.g. 80',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _weightController,
            decoration: const InputDecoration(
              labelText: 'Weight (kg)',
              hintText: 'e.g. 78.4',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              hintText: 'e.g. fasting, after meal, exercise',
              border: OutlineInputBorder(),
            ),
            minLines: 1,
            maxLines: 4,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _EntryListItem extends StatelessWidget {
  const _EntryListItem({
    required this.entry,
    required this.formatDateOnly,
    required this.formatTimeOnly,
    required this.onEdit,
    required this.onDelete,
  });

  final HealthEntry entry;
  final String Function(DateTime?) formatDateOnly;
  final String Function(DateTime?) formatTimeOnly;
  final Future<void> Function(HealthEntry entry) onEdit;
  final Future<void> Function(HealthEntry entry) onDelete;

  @override
  Widget build(BuildContext context) {
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
          SizedBox(
            width: 85,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDateOnly(entry.dateTime),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  formatTimeOnly(entry.dateTime),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (values.isNotEmpty)
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: values
                        .map((v) =>
                            Text(v, style: const TextStyle(fontSize: 13)))
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
          IconButton(
            icon: Icon(Icons.edit_outlined, size: 20, color: Colors.grey[500]),
            tooltip: 'Edit entry',
            onPressed: () => onEdit(entry),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 20, color: Colors.grey[400]),
            tooltip: 'Delete entry',
            onPressed: () => onDelete(entry),
          ),
        ],
      ),
    );
  }
}

class AllEntriesPage extends StatefulWidget {
  const AllEntriesPage({
    super.key,
    required this.entries,
    required this.formatDateOnly,
    required this.formatTimeOnly,
    required this.onEdit,
    required this.onDelete,
  });

  final List<HealthEntry> entries;
  final String Function(DateTime?) formatDateOnly;
  final String Function(DateTime?) formatTimeOnly;
  final Future<HealthEntry?> Function(HealthEntry entry) onEdit;
  final Future<bool> Function(HealthEntry entry) onDelete;

  @override
  State<AllEntriesPage> createState() => _AllEntriesPageState();
}

class _AllEntriesPageState extends State<AllEntriesPage> {
  final TextEditingController _searchController = TextEditingController();
  late List<HealthEntry> _entries;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _entries = List<HealthEntry>.from(widget.entries);
    _sortNewestFirst();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _sortNewestFirst() {
    _entries.sort(
      (a, b) =>
          (b.dateTime ?? DateTime(0)).compareTo(a.dateTime ?? DateTime(0)),
    );
  }

  List<HealthEntry> get _filteredEntries {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _entries;

    return _entries.where((entry) {
      final date = widget.formatDateOnly(entry.dateTime).toLowerCase();
      final time = widget.formatTimeOnly(entry.dateTime).toLowerCase();
      final sugar = entry.bloodSugar.toLowerCase();
      final bp = '${entry.systolic}/${entry.diastolic}'.toLowerCase();
      final weight = entry.weight.toLowerCase();
      final notes = entry.notes.toLowerCase();

      return date.contains(q) ||
          time.contains(q) ||
          sugar.contains(q) ||
          bp.contains(q) ||
          weight.contains(q) ||
          notes.contains(q);
    }).toList();
  }

  Future<void> _handleEdit(HealthEntry entry) async {
    final updated = await widget.onEdit(entry);
    if (!mounted || updated == null) return;

    setState(() {
      final index = _entries.indexWhere((e) => e.id == entry.id);
      if (index != -1) {
        _entries[index] = updated;
      }
      _sortNewestFirst();
    });
  }

  Future<void> _handleDelete(HealthEntry entry) async {
    final deleted = await widget.onDelete(entry);
    if (!mounted || !deleted) return;

    setState(() {
      _entries.removeWhere((e) => e.id == entry.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEntries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Entries'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search entries',
                hintText: 'Date, notes, sugar, blood pressure, weight...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${filtered.length} of ${_entries.length} entries',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _query.isEmpty
                            ? 'No entries found.'
                            : 'No entries match your search.',
                        style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      return _EntryListItem(
                        entry: entry,
                        formatDateOnly: widget.formatDateOnly,
                        formatTimeOnly: widget.formatTimeOnly,
                        onEdit: _handleEdit,
                        onDelete: _handleDelete,
                      );
                    },
                  ),
          ),
        ],
      ),
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
  static const _entriesKey = 'health_entries_list';
  static const _profileKey = 'health_profile_name';
  static const _nhsKey = 'health_nhs_number';
  static const _appUserIdKey = 'app_user_id';

  static const String _supabaseUrl = 'https://yaaqlytgwjblgqvhkhno.supabase.co';
  static const String _supabasePublishableKey =
      'sb_publishable_C-EC1V1EPiKiO-yfbxQaEg_h3vrT0Fu';

  final _entries = <HealthEntry>[];
  final _profileController = TextEditingController();
  final _nhsController = TextEditingController();

  String? _appUserId;
  String? _iapError;

  @override
  void initState() {
    super.initState();
    _initIapAndData();
  }

  @override
  void dispose() {
    ProIap.dispose();
    _profileController.dispose();
    _nhsController.dispose();
    super.dispose();
  }

  Future<void> _openTutorial() async {
    final uri = Uri.parse(AppLinks.healthTutorial);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch tutorial');
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  Widget _paywallLegalLinks() {
    return Wrap(
      spacing: 12,
      children: [
        TextButton(
          onPressed: () => _openUrl(AppLinks.privacyPolicy),
          child: const Text('Privacy Policy'),
        ),
        TextButton(
          onPressed: () => _openUrl(AppLinks.termsOfUse),
          child: const Text('Terms of Use'),
        ),
      ],
    );
  }

  Future<void> _initIapAndData() async {
    await startTrialIfNeeded();
    await _loadOrCreateAppUserId();
    await _loadProfileData();
    await _loadEntries();

    ProIap.onVerifiedPurchase = (purchase) async {
      await _verifyIapWithBackend(
        productId: purchase.productID,
        receiptData: purchase.verificationData.serverVerificationData,
      );
    };

    try {
      await ProIap.init();
    } catch (e) {
      _iapError = e.toString();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      final trialActive = await isTrialActive();
      final infoShown = prefs.getBool(trialInfoShownKey) ?? false;

      if (!ProIap.isPro && trialActive && !infoShown) {
        _showTrialInfoDialog();
        await prefs.setBool(trialInfoShownKey, true);
      } else if (!ProIap.isPro && !trialActive) {
        _showTrialExpiredDialog();
      }
    });

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadOrCreateAppUserId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_appUserIdKey);

    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_appUserIdKey, id);
    }

    _appUserId = id;
  }

  Future<void> _refreshProStatusFromBackend() async {
    if (_appUserId == null || _appUserId!.isEmpty) return;

    final uri = Uri.parse('$_supabaseUrl/functions/v1/get-entitlement');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'apikey': _supabasePublishableKey,
      },
      body: jsonEncode({
        'app_user_id': _appUserId,
        'app': 'myhealthtrail',
      }),
    );

    if (response.statusCode != 200) {
      debugPrint('get-entitlement failed: ${response.body}');
      return;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final isPro = data['isPro'] == true;

    await ProIap.debugSetPro(isPro);

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _verifyIapWithBackend({
    required String productId,
    required String receiptData,
  }) async {
    if (_appUserId == null || _appUserId!.isEmpty) return;

    final uri = Uri.parse('$_supabaseUrl/functions/v1/verify-iap');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'apikey': _supabasePublishableKey,
      },
      body: jsonEncode({
        'app_user_id': _appUserId,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'product_id': productId,
        'receipt_data': receiptData,
        'app': 'myhealthtrail',
        'publishable_key': _supabasePublishableKey,
      }),
    );

    if (response.statusCode != 200) {
      debugPrint('verify-iap failed: ${response.body}');
      return;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final isPro = data['isPro'] == true;

    await ProIap.debugSetPro(isPro);

    if (isPro) {
      await _refreshProStatusFromBackend();
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<bool> _hasActiveAccess() async {
    if (ProIap.isPro) return true;
    return isTrialActive();
  }

  void _showTrialInfoDialog() async {
    final daysLeft = await trialDaysLeft();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Start your 7-day free trial'),
        content: Text(
          'No charge is made during your 7-day free trial.\n\n'
          'You have $daysLeft day(s) left.\n\n'
          'After the trial ends, MyHealthTrail Pro automatically renews at {_proPriceText()} unless cancelled.\n\n'
          'Cancel at any time in Google Play > Subscriptions before the trial ends and you will not be charged.\n\n'
          'By continuing, you agree to the Google Play subscription terms.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ProIap.restore();
            },
            child: const Text('Restore'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showUpgrade();
            },
            child: const Text('Start 7-day free trial'),
          ),
        ],
      ),
    );
  }

  String _proPriceText() {
    return ProIap.cachedProduct?.price ?? 'the price shown in Google Play';
  }

  void _showTrialExpiredDialog() {
    final priceText = _proPriceText();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Trial Expired'),
        content: Text(
          'Your 7-day free trial has ended.\n\n'
          'Subscribe to MyHealthTrail Pro for $priceText per month.\n\n'
          'Your subscription renews automatically every month until cancelled.\n\n'
          'Cancel anytime in Google Play under Subscriptions.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ProIap.restore();
            },
            child: const Text('Restore'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showUpgrade();
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _showUpgrade() {
    final priceText = _proPriceText();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Start your 7-day free trial'),
        content: SingleChildScrollView(
          child: Text(
            'Free trial: 7 days\n'
            'After the trial: $priceText per month\n'
            'Renews automatically every month unless cancelled\n'
            'Cancel before the trial ends in Google Play > Subscriptions and you will not be charged.\n'
            'By tapping Continue, you agree to the Google Play subscription terms.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ProIap.buyPro();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString())),
                );
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Rect _shareOrigin() {
    final box = context.findRenderObject() as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    _profileController.text = prefs.getString(_profileKey) ?? '';
    _nhsController.text = prefs.getString(_nhsKey) ?? '';
  }

  Future<void> _saveProfileName(String value) async {
    await (await SharedPreferences.getInstance()).setString(_profileKey, value);
  }

  Future<void> _saveNhsNumber(String value) async {
    await (await SharedPreferences.getInstance()).setString(_nhsKey, value);
  }

  Future<void> _loadEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_entriesKey) ?? [];

    setState(() {
      _entries
        ..clear()
        ..addAll(
          list
              .map(
                (s) => HealthEntry.fromMap(
                  Map<String, dynamic>.from(jsonDecode(s)),
                ),
              )
              .toList(),
        );
      _sortNewestFirst();
    });
  }

  Future<void> _saveEntries() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _entriesKey,
      _entries.map((e) => jsonEncode(e.toMap())).toList(),
    );
  }

  void _sortNewestFirst() {
    _entries.sort(
      (a, b) =>
          (b.dateTime ?? DateTime(0)).compareTo(a.dateTime ?? DateTime(0)),
    );
  }

  Future<HealthEntry?> _openEntryEditor({HealthEntry? existing}) {
    return Navigator.of(context).push<HealthEntry>(
      MaterialPageRoute(
        builder: (_) => EntryEditorPage(
          existing: existing,
          formatDateOnly: _formatDateOnly,
        ),
      ),
    );
  }

  Future<void> _addEntry() async {
    if (!await _hasActiveAccess()) {
      _showTrialExpiredDialog();
      return;
    }

    final entry = await _openEntryEditor();
    if (entry == null) return;

    setState(() {
      _entries.add(entry);
      _sortNewestFirst();
    });

    await _saveEntries();
    await _exportToCSV();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Health entry saved.')),
    );
  }

  Future<HealthEntry?> _editEntry(HealthEntry existing) async {
    if (!await _hasActiveAccess()) {
      _showTrialExpiredDialog();
      return null;
    }

    final updated = await _openEntryEditor(existing: existing);
    if (updated == null) return null;

    setState(() {
      final index = _entries.indexWhere((e) => e.id == existing.id);
      if (index != -1) {
        _entries[index] = updated;
      }
      _sortNewestFirst();
    });

    await _saveEntries();
    await _exportToCSV();

    if (!mounted) return updated;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Health entry updated.')),
    );

    return updated;
  }

  Future<void> _openAllEntriesPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AllEntriesPage(
          entries: List<HealthEntry>.from(_entries),
          formatDateOnly: _formatDateOnly,
          formatTimeOnly: _formatTimeOnly,
          onEdit: _editEntry,
          onDelete: _deleteEntry,
        ),
      ),
    );

    if (mounted) {
      setState(() {});
    }
  }

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
        'Notes',
      ],
      ..._entries.map((e) => [
            _profileController.text,
            _nhsController.text,
            e.dateTimeIso,
            e.bloodSugar,
            e.systolic,
            e.diastolic,
            e.weight,
            e.notes,
          ]),
    ];

    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/myhealthtrail_readings.csv');
    await file.writeAsString(csv);
  }

  Future<void> _shareCSV() async {
    if (!await _hasActiveAccess()) {
      _showTrialExpiredDialog();
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/myhealthtrail_readings.csv');
    if (!await file.exists()) {
      await _exportToCSV();
    }

    await Share.shareXFiles(
      [XFile(file.path)],
      sharePositionOrigin: _shareOrigin(),
      text: 'MyHealthTrail readings (CSV)',
    );
  }

  List<HealthEntry> _entriesInLast3Months() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 2, 1);

    return _entries
        .where(
          (e) =>
              e.dateTime != null &&
              !e.dateTime!.isBefore(start) &&
              !e.dateTime!.isAfter(now),
        )
        .toList();
  }

  Future<void> _export3MonthReportPdf() async {
    if (!await _hasActiveAccess()) {
      _showTrialExpiredDialog();
      return;
    }

    final items = _entriesInLast3Months();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No health entries found in the last 3 months.'),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final pdf = _buildHealthReportPdf(items);
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/myhealthtrail_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await file.writeAsBytes(await pdf.save());

      if (!mounted) return;
      Navigator.pop(context);

      await Share.shareXFiles(
        [XFile(file.path)],
        sharePositionOrigin: _shareOrigin(),
        text: 'MyHealthTrail 3-Month Health Report',
      );
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
          if (items.any((e) => e.bloodSugar.isNotEmpty)) ...[
            _buildSectionTitle('Blood Sugar Readings', PdfColors.red),
            _buildBloodSugarTable(items),
            pw.SizedBox(height: 20),
          ],
          if (items
              .any((e) => e.systolic.isNotEmpty || e.diastolic.isNotEmpty)) ...[
            _buildSectionTitle('Blood Pressure Readings', PdfColors.blue),
            _buildBloodPressureTable(items),
            pw.SizedBox(height: 20),
          ],
          if (items.any((e) => e.weight.isNotEmpty)) ...[
            _buildSectionTitle('Weight Readings', PdfColors.green),
            _buildWeightTable(items),
            pw.SizedBox(height: 20),
          ],
          _buildDisclaimer(),
        ],
      ),
    );

    return doc;
  }

  pw.Widget _buildPdfHeader(
    String profileName,
    String nhsNumber,
    DateTime now,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 20),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.teal, width: 2),
        ),
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
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
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
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
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
                _buildStatBox(
                  'Avg Blood Sugar',
                  '${stats['avgBloodSugar']} mmol/L',
                  PdfColors.red,
                ),
              if (stats['avgSystolic'] != null && stats['avgDiastolic'] != null)
                _buildStatBox(
                  'Avg BP',
                  '${stats['avgSystolic']}/${stats['avgDiastolic']} mmHg',
                  PdfColors.blue,
                ),
              if (stats['avgWeight'] != null)
                _buildStatBox(
                  'Avg Weight',
                  '${stats['avgWeight']} kg',
                  PdfColors.green,
                ),
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
        ...filtered.map(
          (e) => pw.TableRow(
            children: [
              _tableCell(_formatDateOnly(e.dateTime)),
              _tableCell(_formatTimeOnly(e.dateTime)),
              _tableCell(e.weight),
              _tableCell(e.notes),
            ],
          ),
        ),
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
            '• Blood Pressure: Normal below 120/80 mmHg | Elevated 120-129 | High 130/80 or above',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _calculateStats(List<HealthEntry> items) {
    final stats = <String, dynamic>{};

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
      'Dec',
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
      'Dec',
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
    final parsed = double.tryParse(value);
    if (parsed == null) return '-';
    if (parsed < 4.0) return 'Low';
    if (parsed > 7.0) return 'High';
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

  Future<void> _confirmAndClearAll() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete all entries?'),
            content: const Text(
              'These entries will be permanently deleted from this device.\n\nPlease export your data first if needed.',
            ),
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

    setState(() {
      _entries.clear();
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All entries deleted.')),
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
              Icons.water_drop,
              'Track blood sugar (mmol/L)',
              Colors.red,
            ),
            _buildFeatureRow(
              Icons.favorite,
              'Track blood pressure (mmHg)',
              Colors.blue,
            ),
            _buildFeatureRow(
              Icons.monitor_weight,
              'Track weight (kg)',
              Colors.green,
            ),
            _buildFeatureRow(
              Icons.table_chart,
              'CSV export + sharing',
              Colors.orange,
            ),
            _buildFeatureRow(
              Icons.picture_as_pdf,
              '3-month PDF health report',
              Colors.indigo,
            ),
            _buildFeatureRow(
              Icons.lock,
              'Secure local storage on device',
              Colors.teal,
            ),
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
          Colors.teal,
          Icons.add,
          'Add Health Entry',
          _addEntry,
        ),
        const SizedBox(height: 12),
        _buildActionButton(
          Colors.green,
          Icons.table_chart,
          'Share CSV File',
          _shareCSV,
        ),
        const SizedBox(height: 12),
        _buildActionButton(
          Colors.indigo,
          Icons.picture_as_pdf,
          'Export 3-Month PDF Report',
          _export3MonthReportPdf,
        ),
        const SizedBox(height: 12),
        _buildActionButton(
          Colors.red,
          Icons.delete_forever,
          'Clear All Entries',
          _confirmAndClearAll,
        ),
      ],
    );
  }

  Widget _buildActionButton(
    Color color,
    IconData icon,
    String label,
    VoidCallback onPressed,
  ) {
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
                Row(
                  children: [
                    Text(
                      '${_entries.length} total',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _openAllEntriesPage,
                      child: const Text('View all'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            ...recentEntries.map(_buildEntryTile),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryTile(HealthEntry entry) {
    return _EntryListItem(
      entry: entry,
      formatDateOnly: _formatDateOnly,
      formatTimeOnly: _formatTimeOnly,
      onEdit: (item) async {
        await _editEntry(item);
      },
      onDelete: (item) async {
        await _deleteEntry(item);
      },
    );
  }

  Future<bool> _deleteEntry(HealthEntry entry) async {
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

    if (!ok) return false;

    setState(() {
      _entries.removeWhere((e) => e.id == entry.id);
    });

    await _saveEntries();
    await _exportToCSV();

    if (!mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Entry deleted.')),
    );

    return true;
  }

  Widget _buildFooter() {
    final priceText =
        ProIap.cachedProduct?.price ?? 'the price shown in Google Play';

    return Column(
      children: [
        const Divider(),
        const SizedBox(height: 8),
        FutureBuilder<int>(
          future: trialDaysLeft(),
          builder: (context, snapshot) {
            final days = snapshot.data ?? trialDays;

            final text = ProIap.isPro
                ? 'Pro active'
                : days > 0
                    ? 'Free trial active: $days day(s) remaining. Then $priceText per month unless cancelled before the trial ends.'
                    : 'Trial ended. Subscribe for $priceText per month. Auto-renews monthly until cancelled.';

            return Text(
              text,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            );
          },
        ),
        const SizedBox(height: 4),
        if (!ProIap.isPro)
          TextButton(
            onPressed: _showUpgrade,
            child: const Text(
              'Start 7-day free trial',
              style: TextStyle(fontSize: 13),
            ),
          ),
        const SizedBox(height: 8),
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
              Text(
                'Version 1.0.0',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text(
                'Track your blood sugar, blood pressure, and weight easily. '
                'All data is stored securely on your device.',
              ),
              SizedBox(height: 12),
              Text(
                'Includes a 7-day free trial, with Pro available for continued access afterward.',
                style: TextStyle(fontSize: 12),
              ),
              SizedBox(height: 16),
              Text(
                '⚠️ Medical Disclaimer',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
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
              Text(
                'Data Collection',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                '• Health data (blood sugar, blood pressure, weight)\n'
                '• Optional: Name and Patient Reference for your reference\n'
                '• All data stored locally on your device only',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 12),
              Text(
                'Data Storage',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                'All health data is stored locally on your device. '
                'We do not have access to your data. No data is sent '
                'to any servers.',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 12),
              Text(
                'Data Sharing',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                'We do NOT share your data with any third parties. '
                'You can export your data via email using the CSV or PDF '
                'export features.',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 12),
              Text(
                'Data Deletion',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_circle_outline, color: Colors.white),
            tooltip: 'Watch Tutorial',
            onPressed: _openTutorial,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showAboutDialog,
            tooltip: 'About',
          ),
        ],
      ),
      body: Column(
        children: [
          FutureBuilder<int>(
            future: trialDaysLeft(),
            builder: (context, snapshot) {
              final days = snapshot.data ?? trialDays;
              if (!ProIap.isPro && days > 0) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    border: Border(
                      bottom: BorderSide(color: Colors.orange.shade300),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Free trial: $days day(s) left',
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _showUpgrade,
                        child: const Text('Upgrade'),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
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
          const LegalFooter(),
        ],
      ),
    );
  }
}

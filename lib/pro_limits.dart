import 'package:shared_preferences/shared_preferences.dart';

/// Handles all free-plan limits for MyHealthTrail.
class ProLimits {
  static const _entriesKey = 'entries_this_month';
  static const _pdfKey = 'pdf_exports_this_month';
  static const _monthKey = 'limit_month';

  // 🔒 Free Plan limits
  static const int maxEntriesFree = 10; // entries per month
  static const int maxPdfExportsFree = 1; // PDF exports per month

  /// Returns current month identifier (e.g. "2026-01")
  static String _monthNow() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  /// Resets counters automatically when a new month starts
  static Future<void> _ensureMonthReset() async {
    final prefs = await SharedPreferences.getInstance();
    final storedMonth = prefs.getString(_monthKey);
    final currentMonth = _monthNow();

    if (storedMonth != currentMonth) {
      await prefs.setString(_monthKey, currentMonth);
      await prefs.setInt(_entriesKey, 0);
      await prefs.setInt(_pdfKey, 0);
    }
  }

  // ---------------- Entry tracking ----------------
  static Future<bool> canAddEntry() async {
    await _ensureMonthReset();
    final prefs = await SharedPreferences.getInstance();
    final used = prefs.getInt(_entriesKey) ?? 0;
    return used < maxEntriesFree;
  }

  static Future<void> incrementEntries() async {
    await _ensureMonthReset();
    final prefs = await SharedPreferences.getInstance();
    final used = prefs.getInt(_entriesKey) ?? 0;
    await prefs.setInt(_entriesKey, used + 1);
  }

  // ---------------- PDF export tracking ----------------
  static Future<bool> canExportPdf() async {
    await _ensureMonthReset();
    final prefs = await SharedPreferences.getInstance();
    final used = prefs.getInt(_pdfKey) ?? 0;
    return used < maxPdfExportsFree;
  }

  static Future<void> incrementPdfExports() async {
    await _ensureMonthReset();
    final prefs = await SharedPreferences.getInstance();
    final used = prefs.getInt(_pdfKey) ?? 0;
    await prefs.setInt(_pdfKey, used + 1);
  }

  /// Optional: Developer reset
  static Future<void> resetAllLimits() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_entriesKey);
    await prefs.remove(_pdfKey);
    await prefs.remove(_monthKey);
  }
}
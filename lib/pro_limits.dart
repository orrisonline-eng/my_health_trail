/*

  Project: MyHealthTrail
*/
// --------------------  pro_limits.dart  --------------------

import 'package:shared_preferences/shared_preferences.dart';

class ProLimits {
  // ======================== General/Pro Status ========================
  static const bool devMode = false;
  static const _isProKey = 'is_pro_user';

  static Future<bool> isPro() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isProKey) ?? false;
  }

  static Future<void> setPro(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isProKey, value);
  }

  // ======================== Entry Limits ========================
  static const _entryCountKey = 'pro_entry_count';
  static const _entryMonthKey = 'pro_entry_month';
  static const int freeEntryLimit = 10;

  static Future<bool> canAddEntry() async {
    if (devMode) return true;
    if (await isPro()) return true;
    final prefs = await SharedPreferences.getInstance();
    final currentMonth = _getCurrentMonth();
    final savedMonth = prefs.getString(_entryMonthKey) ?? '';
    if (savedMonth != currentMonth) {
      await prefs.setInt(_entryCountKey, 0);
      await prefs.setString(_entryMonthKey, currentMonth);
      return true;
    }
    final count = prefs.getInt(_entryCountKey) ?? 0;
    return count < freeEntryLimit;
  }

  static Future<void> incrementEntries() async {
    if (await isPro()) return;
    final prefs = await SharedPreferences.getInstance();
    final currentMonth = _getCurrentMonth();
    final savedMonth = prefs.getString(_entryMonthKey) ?? '';
    if (savedMonth != currentMonth) {
      await prefs.setInt(_entryCountKey, 1);
      await prefs.setString(_entryMonthKey, currentMonth);
    } else {
      final count = prefs.getInt(_entryCountKey) ?? 0;
      await prefs.setInt(_entryCountKey, count + 1);
    }
  }

  static Future<int> getRemainingEntries() async {
    if (await isPro()) return -1; // Unlimited
    final prefs = await SharedPreferences.getInstance();
    final currentMonth = _getCurrentMonth();
    final savedMonth = prefs.getString(_entryMonthKey) ?? '';
    if (savedMonth != currentMonth) return freeEntryLimit;
    final count = prefs.getInt(_entryCountKey) ?? 0;
    return freeEntryLimit - count;
  }

  // ======================== CSV Export Limits ========================
  static const _csvCountKey = 'pro_csv_count';
  static const _csvMonthKey = 'pro_csv_month';
  static const int freeCsvLimit = 1;

  static Future<bool> canExportCsv() async {
    if (devMode) return true;
    if (await isPro()) return true;
    final prefs = await SharedPreferences.getInstance();
    final currentMonth = _getCurrentMonth();
    final savedMonth = prefs.getString(_csvMonthKey) ?? '';
    if (savedMonth != currentMonth) {
      await prefs.setInt(_csvCountKey, 0);
      await prefs.setString(_csvMonthKey, currentMonth);
      return true;
    }
    final count = prefs.getInt(_csvCountKey) ?? 0;
    return count < freeCsvLimit;
  }

  static Future<void> incrementCsvExports() async {
    if (await isPro()) return;
    final prefs = await SharedPreferences.getInstance();
    final currentMonth = _getCurrentMonth();
    final savedMonth = prefs.getString(_csvMonthKey) ?? '';
    if (savedMonth != currentMonth) {
      await prefs.setInt(_csvCountKey, 1);
      await prefs.setString(_csvMonthKey, currentMonth);
    } else {
      final count = prefs.getInt(_csvCountKey) ?? 0;
      await prefs.setInt(_csvCountKey, count + 1);
    }
  }

  static Future<int> getRemainingCsvExports() async {
    if (await isPro()) return -1; // Unlimited
    final prefs = await SharedPreferences.getInstance();
    final currentMonth = _getCurrentMonth();
    final savedMonth = prefs.getString(_csvMonthKey) ?? '';
    if (savedMonth != currentMonth) return freeCsvLimit;
    final count = prefs.getInt(_csvCountKey) ?? 0;
    return freeCsvLimit - count;
  }

  // ======================== PDF Export Limits ========================
  static const _pdfCountKey = 'pro_pdf_count';
  static const _pdfMonthKey = 'pro_pdf_month';
  static const int freePdfLimit = 1;

  static Future<bool> canExportPdf() async {
    if (devMode) return true; // fixed (should allow in devMode)
    if (await isPro()) return true;
    final prefs = await SharedPreferences.getInstance();
    final currentMonth = _getCurrentMonth();
    final savedMonth = prefs.getString(_pdfMonthKey) ?? '';
    if (savedMonth != currentMonth) {
      await prefs.setInt(_pdfCountKey, 0);
      await prefs.setString(_pdfMonthKey, currentMonth);
      return true;
    }
    final count = prefs.getInt(_pdfCountKey) ?? 0;
    return count < freePdfLimit;
  }

  static Future<void> incrementPdfExports() async {
    if (await isPro()) return;
    final prefs = await SharedPreferences.getInstance();
    final currentMonth = _getCurrentMonth();
    final savedMonth = prefs.getString(_pdfMonthKey) ?? '';
    if (savedMonth != currentMonth) {
      await prefs.setInt(_pdfCountKey, 1);
      await prefs.setString(_pdfMonthKey, currentMonth);
    } else {
      final count = prefs.getInt(_pdfCountKey) ?? 0;
      await prefs.setInt(_pdfCountKey, count + 1);
    }
  }

  static Future<int> getRemainingPdfExports() async {
    if (await isPro()) return -1; // Unlimited
    final prefs = await SharedPreferences.getInstance();
    final currentMonth = _getCurrentMonth();
    final savedMonth = prefs.getString(_pdfMonthKey) ?? '';
    if (savedMonth != currentMonth) return freePdfLimit;
    final count = prefs.getInt(_pdfCountKey) ?? 0;
    return freePdfLimit - count;
  }

  // ======================== Helper ========================
  static String _getCurrentMonth() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }
}

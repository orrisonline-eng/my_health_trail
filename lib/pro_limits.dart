// --------------------  pro_limits.dart  --------------------
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';


class ProLimits {
  static const bool devMode = true;
  static const _entryCountKey = 'pro_entry_count';
  static const _entryMonthKey = 'pro_entry_month';
  static const _pdfCountKey = 'pro_pdf_count';
  static const _pdfMonthKey = 'pro_pdf_month';
  static const _isProKey = 'is_pro_user';

  static const int freeEntryLimit = 10;
  static const int freePdfLimit = 1;

  // Check if user is Pro
  static Future<bool> isPro() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isProKey) ?? false;
  }

  // Set Pro status (call this after purchase)
  static Future<void> setPro(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isProKey, value);
  }

  // Check if user can add entry
  static Future<bool> canAddEntry() async {
    if (devMode) return true;
    if (await isPro()) return true;

    final prefs = await SharedPreferences.getInstance();
    final currentMonth = _getCurrentMonth();
    final savedMonth = prefs.getString(_entryMonthKey) ?? '';

    // Reset count if new month
    if (savedMonth != currentMonth) {
      await prefs.setInt(_entryCountKey, 0);
      await prefs.setString(_entryMonthKey, currentMonth);
      return true;
    }

    final count = prefs.getInt(_entryCountKey) ?? 0;
    return count < freeEntryLimit;
  }

  // Increment entry count
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

  // Check if user can export PDF
  static Future<bool> canExportPdf() async {
    if (devMode) return true;
    if (await isPro()) return true;
  
    final prefs = await SharedPreferences.getInstance();
    final currentMonth = _getCurrentMonth();
    final savedMonth = prefs.getString(_pdfMonthKey) ?? '';

    // Reset count if new month
    if (savedMonth != currentMonth) {
      await prefs.setInt(_pdfCountKey, 0);
      await prefs.setString(_pdfMonthKey, currentMonth);
      return true;
    }

    final count = prefs.getInt(_pdfCountKey) ?? 0;
    return count < freePdfLimit;
  }

  // Increment PDF export count
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

  // Get remaining entries for current month
  static Future<int> getRemainingEntries() async {
    if (await isPro()) return -1; // Unlimited

    final prefs = await SharedPreferences.getInstance();
    final currentMonth = _getCurrentMonth();
    final savedMonth = prefs.getString(_entryMonthKey) ?? '';

    if (savedMonth != currentMonth) return freeEntryLimit;

    final count = prefs.getInt(_entryCountKey) ?? 0;
    return freeEntryLimit - count;
  }

  // Get remaining PDF exports for current month
  static Future<int> getRemainingPdfExports() async {
    if (await isPro()) return -1; // Unlimited

    final prefs = await SharedPreferences.getInstance();
    final currentMonth = _getCurrentMonth();
    final savedMonth = prefs.getString(_pdfMonthKey) ?? '';

    if (savedMonth != currentMonth) return freePdfLimit;

    final count = prefs.getInt(_pdfCountKey) ?? 0;
    return freePdfLimit - count;
  }

  static String _getCurrentMonth() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }
}
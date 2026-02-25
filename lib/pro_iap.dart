// pro_iap.dart - IAP Implementation for MyHealthTrail
// pro_iap.dart - FOR in_app_purchase 3.2.3

// pro_iap.dart - Adapted from MyTaxTrail for MyHealthTrail
// IMPORTANT NOTES (read once):
// 1) This is a client-side entitlement check. For maximum security you would verify
//    receipts on a server, but for your current app (local-only data) this is a common start.
// 2) Your App Store Connect / Play Console Product ID MUST match `proMonthlyId` exactly.
// 3) Call `await ProIap.init();` once at app start (e.g., in initState).

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;

class ProIap {
  ProIap._(); // no instances

  /// ✅ CHANGE THESE to your MyHealthTrail product IDs
  static const String _iosProId = 'myhealthtrail_pro_monthly'; // Apple
  static const String _androidProId = 'myhealthtrail_pro'; // Google

  static String get proMonthlyId => Platform.isIOS ? _iosProId : _androidProId;

  static const String _isProKey = 'health_is_pro_user'; // Changed for MyHealthTrail

  static final InAppPurchase _iap = InAppPurchase.instance;

  static StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  static bool _isPro = false;

  /// Read-only (sync) getter for UI logic
  static bool get isPro => _isPro;

  /// Optional: handy for widgets that want to rebuild when Pro changes
  static final ValueNotifier<bool> proNotifier = ValueNotifier<bool>(false);

  /// Optional: cache the product so you can show price in UI if you want
  static ProductDetails? cachedProduct;

  static Future<void> _setPro(bool value) async {
    _isPro = value;
    proNotifier.value = value;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isProKey, value);

    debugPrint('✅ MyHealthTrail Pro status set to: $value');
  }

  /// Call once at app start
  static Future<void> init() async {
    debugPrint('🔄 MyHealthTrail ProIap.init() starting...');
    
    // 1) Load cached entitlement first (fast UI unlock)
    await _loadCachedIsPro();
    debugPrint('📱 Loaded cached Pro status: $_isPro');

    // 2) Check store availability
    final available = await _iap.isAvailable();
    debugPrint('IAP available: $available');

    if (!available) {
      debugPrint('⚠️ IAP not available');
      return;
    }

    // 3) Listen for purchase updates (only set up once)
    _purchaseSub ??= _iap.purchaseStream.listen(
      (purchases) {
        _onPurchaseUpdated(purchases); // don't await here
      },
      onError: (e) {
        debugPrint('❌ IAP stream error: $e');
      },
    );

    // 4) Fetch product details + restore (important for iOS)
    await _queryProduct();
    await restore();
    
    debugPrint('✅ MyHealthTrail ProIap.init() completed');
  }

  // 🔔 Handles purchase updates from App Store / Play Store
  static void _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
    debugPrint('🔄 Purchase update received: ${purchases.length} purchase(s)');
    
    for (final p in purchases) {
      debugPrint('Processing purchase: ${p.productID}, status: ${p.status}');
      
      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        // ✅ Unlock Pro
        await _setPro(true);

        // ✅ Finish the transaction (CRITICAL)
        if (p.pendingCompletePurchase) {
          await _iap.completePurchase(p);
          debugPrint('✅ Purchase completed');
        }
      } else if (p.status == PurchaseStatus.error) {
        debugPrint('❌ IAP error: ${p.error}');
      } else if (p.status == PurchaseStatus.pending) {
        debugPrint('⏳ Purchase pending');
      }
    }
  }

  /// Call when app closes (optional)
  static Future<void> dispose() async {
    await _purchaseSub?.cancel();
    _purchaseSub = null;
    debugPrint('🔴 MyHealthTrail ProIap disposed');
  }

  /// Start purchase flow for the subscription
  static Future<void> buyPro() async {
    debugPrint('🛒 buyPro() called for MyHealthTrail');
    
    final available = await _iap.isAvailable();
    debugPrint('IAP available: $available');

    if (!available) {
      debugPrint('❌ IAP not available on this device');
      throw Exception('In-app purchases not available on this device');
    }

    if (cachedProduct == null) {
      debugPrint('🔍 Querying products...');
      await _queryProduct();
    }

    debugPrint('Cached product: ${cachedProduct?.id}');

    final product = cachedProduct;
    if (product == null) {
      debugPrint('❌ Product not found');
      throw Exception('Product not found in store. Please try again later.');
    }

    final purchaseParam = PurchaseParam(productDetails: product);
    debugPrint('🚀 Launching purchase sheet for: ${product.title} (${product.price})');
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  /// Restore purchases (use on app start and also add a "Restore" button for users)
  static Future<void> restore() async {
    debugPrint('🔄 Restoring purchases...');
    try {
      await _iap.restorePurchases();
      debugPrint('✅ Restore request sent');
    } catch (e) {
      debugPrint('❌ Restore error: $e');
      // Don't rethrow - let UI handle gracefully
    }
  }

  /// Manually lock pro (for debugging only)
  static Future<void> debugSetPro(bool v) async {
    debugPrint('🔧 DEBUG: Manually setting Pro to: $v');
    await _setPro(v);
  }

  // -------------------------
  // Internal helpers
  // -------------------------

  static Future<void> _queryProduct() async {
    debugPrint('🔍 Querying product details for: $proMonthlyId');
    final response = await _iap.queryProductDetails({proMonthlyId});
    
    if (response.error != null) {
      debugPrint('❌ Query error: ${response.error!.message}');
      return;
    }
    
    if (response.productDetails.isNotEmpty) {
      cachedProduct = response.productDetails.first;
      debugPrint('✅ Product found: ${cachedProduct!.title} (${cachedProduct!.price})');
    } else {
      debugPrint('❌ No product found for ID: $proMonthlyId');
    }
  }

  static Future<void> _loadCachedIsPro() async {
    final prefs = await SharedPreferences.getInstance();
    _isPro = prefs.getBool(_isProKey) ?? false;
    proNotifier.value = _isPro;
  }
}
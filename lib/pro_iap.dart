// pro_iap.dart - IAP Implementation for MyHealthTrail
//
// Aligned with the MyTaxTrail structure while keeping MyHealthTrail product ids.
// - Persists local Pro state for fast UI unlock on restart
// - Listens to purchase updates
// - Does NOT auto-restore on startup
// - Only unlocks Pro for the expected product id
// - Supports backend verification via `onVerifiedPurchase`

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProIap {
  ProIap._();

  static const String _iosProId = 'myhealthtrail_pro_monthly';
  static const String _androidProId = 'myhealthtrail_pro';

  static String get proMonthlyId => Platform.isIOS ? _iosProId : _androidProId;

  static const String _isProKey = 'health_is_pro_user';

  static final InAppPurchase _iap = InAppPurchase.instance;
  static StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  static bool _isPro = false;
  static bool get isPro => _isPro;

  static final ValueNotifier<bool> proNotifier = ValueNotifier<bool>(false);

  static ProductDetails? cachedProduct;

  static Future<void> _setPro(bool value) async {
    _isPro = value;
    proNotifier.value = value;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isProKey, value);
  }

  static Future<void> _loadCachedIsPro() async {
    final prefs = await SharedPreferences.getInstance();
    _isPro = prefs.getBool(_isProKey) ?? false;
    proNotifier.value = _isPro;
  }

  static Future<void> init() async {
    await _loadCachedIsPro();

    final available = await _iap.isAvailable();
    if (!available) {
      debugPrint('IAP not available');
      return;
    }

    _purchaseSub ??= _iap.purchaseStream.listen(
      (purchases) {
        debugPrint('Purchase stream received ${purchases.length} purchase(s)');

        for (final p in purchases) {
          debugPrint('Purchase: ${p.productID} | Status: ${p.status}');
        }

        _updateProStatus(purchases);
      },
      onError: (e) => debugPrint('IAP stream error: $e'),
    );

    await _queryProduct();
  }

  static Future<void> dispose() async {
    await _purchaseSub?.cancel();
    _purchaseSub = null;
  }

  static Future<void> _queryProduct() async {
    final response = await _iap.queryProductDetails({proMonthlyId});

    if (response.error != null) {
      debugPrint('IAP product query error: ${response.error}');
    }

    if (response.productDetails.isEmpty) {
      cachedProduct = null;
      debugPrint('Product not found for id: $proMonthlyId');
      return;
    }

    ProductDetails? match;
    for (final p in response.productDetails) {
      if (p.id == proMonthlyId) {
        match = p;
        break;
      }
    }

    cachedProduct = match ?? response.productDetails.first;
  }

  static Future<void> buyPro() async {
    final available = await _iap.isAvailable();
    if (!available) {
      debugPrint('IAP not available');
      return;
    }

    if (cachedProduct == null) {
      await _queryProduct();
    }

    final product = cachedProduct;
    if (product == null) {
      debugPrint('Product not found');
      return;
    }

    final purchaseParam = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  static Future<void> restore() async {
    try {
      final available = await _iap.isAvailable();
      if (!available) {
        debugPrint('IAP not available');
        return;
      }

      debugPrint('Restoring purchases...');
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('Restore failed: $e');
    }
  }

  static Future<void> Function(PurchaseDetails purchase)? onVerifiedPurchase;

  static Future<void> _updateProStatus(
    List<PurchaseDetails> purchases,
  ) async {
    for (final p in purchases) {
      debugPrint('IAP update: ${p.productID} - ${p.status}');

      if (p.productID != proMonthlyId) continue;

      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        await _setPro(true);

        try {
          await onVerifiedPurchase?.call(p);
        } catch (e) {
          debugPrint(
              'Backend verify failed, but Apple purchase was restored: $e');
        }

        if (p.pendingCompletePurchase) {
          await _iap.completePurchase(p);
        }
        return;
      }

      if (p.status == PurchaseStatus.error) {
        debugPrint('IAP error: ${p.error}');
      }
    }

    // Do not force Pro to false during restore/update events.
  }

  static Future<void> debugSetPro(bool value) async {
    await _setPro(value);
  }
}

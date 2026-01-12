import 'dart:async';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'pro_limits.dart';

class PurchaseService {
  static final PurchaseService _instance = PurchaseService._internal();
  factory PurchaseService() => _instance;
  PurchaseService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  
  // Product ID - must match App Store Connect & Google Play Console
  static const String proLifetimeId = 'pro_lifetime';
  
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  List<ProductDetails> _products = [];
  
  bool _isAvailable = false;
  bool get isAvailable => _isAvailable;
  
  List<ProductDetails> get products => _products;

  /// Initialize the purchase service
  Future<void> initialize() async {
    _isAvailable = await _iap.isAvailable();
    
    if (!_isAvailable) {
      debugPrint('IAP not available');
      return;
    }

    // Listen to purchase updates
    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription?.cancel(),
      onError: (error) => debugPrint('IAP Error: $error'),
    );

    // Load products
    await _loadProducts();
    
    // Restore previous purchases
    await restorePurchases();
  }

  Future<void> _loadProducts() async {
    final Set<String> productIds = {proLifetimeId};
    final ProductDetailsResponse response = await _iap.queryProductDetails(productIds);
    
    if (response.error != null) {
      debugPrint('Error loading products: ${response.error}');
      return;
    }
    
    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('Products not found: ${response.notFoundIDs}');
    }
    
    _products = response.productDetails;
    debugPrint('Loaded ${_products.length} products');
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    for (final purchase in purchaseDetailsList) {
      _handlePurchase(purchase);
    }
  }

  Future<void> _handlePurchase(PurchaseDetails purchase) async {
    if (purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored) {
      // Verify and deliver the product
      if (purchase.productID == proLifetimeId) {
        await ProLimits.setPro(true);
        debugPrint('Pro unlocked!');
      }
    }

    if (purchase.status == PurchaseStatus.error) {
      debugPrint('Purchase error: ${purchase.error}');
    }

    // Complete the purchase
    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }

  /// Buy Pro Lifetime
  Future<bool> buyProLifetime() async {
    if (!_isAvailable) {
      debugPrint('Store not available');
      return false;
    }

    ProductDetails? product;
    try {
      product = _products.firstWhere((p) => p.id == proLifetimeId);
    } catch (e) {
      debugPrint('Product not found');
      return false;
    }

    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
    
    try {
      return await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      debugPrint('Purchase failed: $e');
      return false;
    }
  }

  /// Restore purchases
  Future<void> restorePurchases() async {
    if (!_isAvailable) return;
    await _iap.restorePurchases();
  }

  /// Get the price string for display
  String get priceString {
    if (_products.isEmpty) return '£2.99';
    try {
      final product = _products.firstWhere((p) => p.id == proLifetimeId);
      return product.price;
    } catch (e) {
      return '£2.99';
    }
  }

  void dispose() {
    _subscription?.cancel();
  }
}
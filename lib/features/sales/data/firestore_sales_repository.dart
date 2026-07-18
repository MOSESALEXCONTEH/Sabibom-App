import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../domain/sale_calculator.dart';
import '../domain/sale_models.dart';
import 'sales_repository.dart';

class FirestoreSalesRepository implements SalesRepository {
  FirestoreSalesRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  @override
  Future<CompletedSale> completeSale(CompleteSaleRequest request) async {
    final user = _auth.currentUser;
    if (user == null) throw const SaleException('unauthenticated');
    if (request.business.businessId.trim().isEmpty) throw const SaleException('failed-precondition');
    if (request.cart.items.isEmpty) throw const SaleException('failed-precondition', message: 'Add at least one item to the sale.');

    final totals = request.cart.totals(
      taxEnabled: request.business.taxEnabled,
      taxPercentage: request.business.taxPercentage,
    );
    if (request.cart.paymentMethod == PaymentMethod.cash && totals.amountPaidMinor < totals.totalMinor) {
      throw const SaleException('failed-precondition', message: 'Cash received must cover the total.');
    }
    if (totals.balanceDueMinor > 0 && request.cart.customer == null) {
      throw const SaleException('failed-precondition', message: 'Select a customer for credit or partial payment.');
    }

    final business = _firestore.collection('businesses').doc(request.business.businessId);
    final sale = business.collection('sales').doc(request.saleId);
    final counter = business.collection('counters').doc('sales');
    final activity = business.collection('activity').doc();
    final today = DateFormat('yyyyMMdd').format(DateTime.now());
    final analytics = business.collection('analytics').doc('daily_$today');

    return _firestore.runTransaction((transaction) async {
      final businessSnapshot = await transaction.get(business);
      if (!businessSnapshot.exists) throw const SaleException('not-found');
      final existing = await transaction.get(sale);
      if (existing.exists) {
        final data = existing.data()!;
        return _completedFromExisting(request.saleId, data);
      }

      final productSnapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final item in request.cart.items.where((item) => item.trackStock && item.productId != null)) {
        productSnapshots[item.productId!] = await transaction.get(business.collection('products').doc(item.productId));
      }
      for (final item in request.cart.items.where((item) => item.trackStock && item.productId != null)) {
        final product = productSnapshots[item.productId!];
        if (product == null || !product.exists) throw SaleException('failed-precondition', message: '${item.name} is no longer available.');
        final available = (product.data()?['quantity'] as num?)?.toDouble() ?? 0;
        if (available < item.quantity) {
          throw SaleException('failed-precondition', message: 'Not enough stock for ${item.name}. Only $available remaining.');
        }
      }

      final counterSnapshot = await transaction.get(counter);
      final nextNumber = ((counterSnapshot.data()?['nextNumber'] as num?)?.toInt() ?? 1);
      final receiptNumber = 'SB-$today-${nextNumber.toString().padLeft(4, '0')}';
      transaction.set(counter, <String, Object?>{'nextNumber': nextNumber + 1, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

      DocumentReference<Map<String, dynamic>>? customerReference;
      DocumentSnapshot<Map<String, dynamic>>? customerSnapshot;
      if (totals.balanceDueMinor > 0) {
        customerReference = business.collection('customers').doc(request.cart.customer!.customerId);
        customerSnapshot = await transaction.get(customerReference);
        if (!customerSnapshot.exists) throw const SaleException('failed-precondition', message: 'The selected customer no longer exists.');
      }

      final paymentStatus = totals.balanceDueMinor == 0
          ? PaymentStatus.paid
          : totals.amountPaidMinor == 0
          ? PaymentStatus.unpaid
          : PaymentStatus.partiallyPaid;
      final itemMaps = request.cart.items.map((item) {
        final subtotal = SaleCalculator.lineSubtotal(item);
        final discount = SaleCalculator.lineDiscount(item);
        return <String, Object?>{
          'saleItemId': item.saleItemId,
          'productId': item.productId,
          'isCustomItem': item.isCustomItem,
          'name': item.name,
          'sku': item.sku,
          'barcode': item.barcode,
          'unit': item.unit,
          'quantity': item.quantity,
          'unitPriceMinor': item.unitPriceMinor,
          'costPriceMinor': item.costPriceMinor,
          'discountType': item.discountType?.name,
          'discountValue': item.discountValue,
          'discountAmountMinor': discount,
          'lineSubtotalMinor': subtotal,
          'lineTotalMinor': subtotal - discount,
          'trackStock': item.trackStock,
        };
      }).toList();

      transaction.set(sale, <String, Object?>{
        'saleId': request.saleId,
        'businessId': request.business.businessId,
        'receiptNumber': receiptNumber,
        'customerId': request.cart.customer?.customerId,
        'customerName': request.cart.customer?.name,
        'customerPhone': request.cart.customer?.phone,
        'items': itemMaps,
        'itemCount': request.cart.items.length,
        'subtotalMinor': totals.subtotalMinor,
        'discountMinor': totals.itemDiscountMinor + totals.orderDiscountMinor,
        'taxMinor': totals.taxMinor,
        'totalMinor': totals.totalMinor,
        'amountPaidMinor': totals.amountPaidMinor,
        'balanceDueMinor': totals.balanceDueMinor,
        'changeMinor': totals.changeMinor,
        // Compatibility fields used by existing dashboard queries.
        'total': minorToMoney(totals.totalMinor),
        'amountPaid': minorToMoney(totals.amountPaidMinor),
        'currencyCode': request.business.currency.code,
        'currencySymbol': request.business.currency.symbol,
        'paymentMethod': request.cart.paymentMethod.storedValue,
        'paymentStatus': paymentStatus.name,
        'saleStatus': SaleStatus.completed.name,
        'status': SaleStatus.completed.name,
        'note': request.cart.note.isEmpty ? null : request.cart.note,
        'createdBy': user.uid,
        'createdByName': request.cashierName,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      for (final item in request.cart.items.where((item) => item.trackStock && item.productId != null)) {
        final productReference = business.collection('products').doc(item.productId);
        transaction.update(productReference, <String, Object?>{
          'quantity': FieldValue.increment(-item.quantity),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (customerReference != null && customerSnapshot != null) {
        final previousBalance = (customerSnapshot.data()?['balanceMinor'] as num?)?.toInt() ?? moneyToMinor(customerSnapshot.data()?['balance']);
        final updatedBalance = previousBalance + totals.balanceDueMinor;
        transaction.update(customerReference, <String, Object?>{
          'balanceMinor': updatedBalance,
          'balance': minorToMoney(updatedBalance),
          'totalCreditMinor': FieldValue.increment(totals.balanceDueMinor),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(customerReference.collection('ledger').doc(), <String, Object?>{
          'type': 'sale_credit',
          'saleId': request.saleId,
          'receiptNumber': receiptNumber,
          'debitMinor': totals.balanceDueMinor,
          'creditMinor': 0,
          'balanceAfterMinor': updatedBalance,
          'createdBy': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      transaction.set(activity, <String, Object?>{
        'activityId': activity.id,
        'businessId': request.business.businessId,
        'type': 'sale',
        'title': 'Sale completed',
        'subtitle': 'Receipt $receiptNumber',
        'amount': minorToMoney(totals.totalMinor),
        'amountMinor': totals.totalMinor,
        'currencyCode': request.business.currency.code,
        'referenceId': request.saleId,
        'createdBy': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
      });
      transaction.set(analytics, <String, Object?>{
        'dateKey': today,
        'grossSalesMinor': FieldValue.increment(totals.subtotalMinor),
        'discountMinor': FieldValue.increment(totals.itemDiscountMinor + totals.orderDiscountMinor),
        'taxMinor': FieldValue.increment(totals.taxMinor),
        'netSalesMinor': FieldValue.increment(totals.totalMinor),
        'amountPaidMinor': FieldValue.increment(totals.amountPaidMinor),
        'creditCreatedMinor': FieldValue.increment(totals.balanceDueMinor),
        'orderCount': FieldValue.increment(1),
        // ignore: avoid_types_as_parameter_names
        'itemsSold': FieldValue.increment(request.cart.items.fold<double>(0, (sum, item) => sum + item.quantity)),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return CompletedSale(
        saleId: request.saleId,
        receiptNumber: receiptNumber,
        totalMinor: totals.totalMinor,
        amountPaidMinor: totals.amountPaidMinor,
        balanceDueMinor: totals.balanceDueMinor,
        changeMinor: totals.changeMinor,
        paymentMethod: request.cart.paymentMethod,
      );
    });
  }

  @override
  Stream<List<SaleHistoryItem>> watchRecentSales(String businessId, {int limit = 25}) {
    if (businessId.trim().isEmpty) return Stream<List<SaleHistoryItem>>.value(const <SaleHistoryItem>[]);
    return _firestore.collection('businesses').doc(businessId).collection('sales').orderBy('createdAt', descending: true).limit(limit).snapshots().map(
      (snapshot) => snapshot.docs.map((doc) => SaleHistoryItem.fromFirestore(doc.id, doc.data())).toList(),
    );
  }

  @override
  Future<Map<String, dynamic>?> getSale(String businessId, String saleId) async {
    if (businessId.trim().isEmpty || saleId.trim().isEmpty) return null;
    return (await _firestore.collection('businesses').doc(businessId).collection('sales').doc(saleId).get()).data();
  }

  CompletedSale _completedFromExisting(String saleId, Map<String, dynamic> data) => CompletedSale(
    saleId: saleId,
    receiptNumber: data['receiptNumber'] as String? ?? saleId,
    totalMinor: (data['totalMinor'] as num?)?.toInt() ?? moneyToMinor(data['total']),
    amountPaidMinor: (data['amountPaidMinor'] as num?)?.toInt() ?? moneyToMinor(data['amountPaid']),
    balanceDueMinor: (data['balanceDueMinor'] as num?)?.toInt() ?? 0,
    changeMinor: (data['changeMinor'] as num?)?.toInt() ?? 0,
    paymentMethod: PaymentMethod.values.firstWhere(
      (method) => method.storedValue == data['paymentMethod'],
      orElse: () => PaymentMethod.cash,
    ),
  );
}

class SaleException implements Exception {
  const SaleException(this.code, {this.message});

  final String code;
  final String? message;

  String get friendlyMessage => message ?? switch (code) {
    'permission-denied' => 'You do not have permission to complete this sale.',
    'unavailable' => 'The sales service is temporarily unavailable.',
    'unauthenticated' => 'Your session expired. Please sign in again.',
    'failed-precondition' => 'Some items no longer have enough stock.',
    'deadline-exceeded' => 'The sale took too long to process. Please try again.',
    'already-exists' => 'This sale has already been completed.',
    _ => 'Something went wrong while completing the sale.',
  };

  @override
  String toString() => 'SaleException($code): $friendlyMessage';
}
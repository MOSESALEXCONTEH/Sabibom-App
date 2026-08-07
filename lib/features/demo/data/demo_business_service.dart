import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../../business_setup/domain/business.dart';
import '../../business_setup/domain/business_setup_data.dart';
import '../../business_setup/domain/receipt_settings.dart';
import '../../team/domain/system_roles.dart';

/// Creates an isolated demo business with fictional sample data.
class DemoBusinessService {
  DemoBusinessService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  static const demoTag = 'Demo Business';

  Future<String> createOrResetDemo() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign in to explore the demo.');
    }

    // Soft-archive previous demo businesses for this owner.
    final existing = await _db
        .collection('businesses')
        .where('ownerId', isEqualTo: user.uid)
        .where('isDemo', isEqualTo: true)
        .limit(5)
        .get();
    final batch = _db.batch();
    for (final doc in existing.docs) {
      batch.set(doc.reference, {
        'status': 'archived',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();

    final businessId = 'demo_${const Uuid().v4().replaceAll('-', '').substring(0, 16)}';
    final business = Business.fromSetupData(
      businessId: businessId,
      ownerId: user.uid,
      data: BusinessSetupData(
        businessName: demoTag,
        businessType: 'Retail Shop',
        customBusinessType: '',
        ownerName: user.displayName ?? 'Demo Owner',
        logoPath: null,
        phoneNumber: '000000000',
        email: 'demo@example.invalid',
        address: 'Sample Street',
        district: 'Western Area Urban',
        customDistrict: '',
        country: 'Sierra Leone',
        currency: CurrencyConfig.sle,
        taxEnabled: false,
        taxPercentage: 0,
        financialYearStartMonth: 'January',
        receiptSettings: ReceiptSettings.initial(),
      ),
    );

    final bizRef = _db.collection('businesses').doc(businessId);
    await bizRef.set({
      ...business.toMap(),
      'isDemo': true,
      'businessTagline': 'Sample data only',
      'timezone': 'Africa/Freetown',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await bizRef.collection('members').doc(user.uid).set({
      'userId': user.uid,
      'role': SystemRoleIds.owner,
      'roleId': SystemRoleIds.owner,
      'status': 'active',
      'isOwner': true,
      'permissions': SystemRoles.defaultPermissionsFor(SystemRoleIds.owner)
          .map((p) => p.code)
          .toList(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    for (final role in SystemRoles.buildDefaults(businessId)) {
      await bizRef.collection('roles').doc(role.id).set({
        ...role.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await _seedSampleData(bizRef, user.uid);

    await _db.collection('users').doc(user.uid).set({
      'activeBusinessId': businessId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return businessId;
  }

  Future<void> _seedSampleData(
    DocumentReference<Map<String, dynamic>> biz,
    String uid,
  ) async {
    final products = [
      ('Soap Bar', 500, 300, 20),
      ('Hair Gel', 1500, 900, 8),
      ('Shampoo', 2500, 1600, 3),
      ('Comb', 800, 400, 15),
      ('Face Cream', 3500, 2000, 0),
    ];
    final productIds = <String>[];
    for (final (name, sell, cost, qty) in products) {
      final ref = biz.collection('products').doc();
      productIds.add(ref.id);
      await ref.set({
        'name': name,
        'sellingPriceMinor': sell,
        'costPriceMinor': cost,
        'quantity': qty,
        'lowStockThreshold': 5,
        'trackStock': true,
        'unit': 'unit',
        'status': 'active',
        'isDemo': true,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    final customers = ['Ada Sample', 'Ben Example', 'Cora Demo', 'Dan Test'];
    final customerIds = <String>[];
    for (var i = 0; i < customers.length; i++) {
      final ref = biz.collection('customers').doc();
      customerIds.add(ref.id);
      await ref.set({
        'name': customers[i],
        'phone': '07000000${i + 1}',
        'balanceMinor': i == 0 ? 85000 : 0,
        'status': 'active',
        'isDemo': true,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    for (final name in ['ABC Trading Demo', 'Fresh Supply Sample']) {
      await biz.collection('suppliers').doc().set({
        'name': name,
        'balanceMinor': name.contains('ABC') ? 250000 : 0,
        'status': 'active',
        'isDemo': true,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    for (var i = 0; i < 8; i++) {
      await biz.collection('sales').doc().set({
        'saleStatus': 'completed',
        'status': 'completed',
        'totalMinor': 2000 + (i * 500),
        'subtotalMinor': 2000 + (i * 500),
        'amountPaidMinor': i.isEven ? 2000 + (i * 500) : 1000,
        'balanceDueMinor': i.isEven ? 0 : 1000 + (i * 250),
        'paymentMethod': i.isEven ? 'cash' : 'credit',
        'customerId': customerIds[i % customerIds.length],
        'customerName': customers[i % customers.length],
        'isDemo': true,
        'createdBy': uid,
        'createdAt': Timestamp.fromDate(
          DateTime.now().subtract(Duration(days: i)),
        ),
      });
    }

    for (final (cat, amount) in [
      ('Rent', 200000),
      ('Transport', 25000),
      ('Utilities', 40000),
    ]) {
      await biz.collection('expenses').doc().set({
        'categoryName': cat,
        'description': 'Sample $cat',
        'amountMinor': amount,
        'status': 'active',
        'expenseDate': FieldValue.serverTimestamp(),
        'isDemo': true,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await biz.collection('activity').doc().set({
      'type': 'demo_seed',
      'title': 'Demo data loaded',
      'subtitle': 'Sample data only — not real business records',
      'createdBy': uid,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}

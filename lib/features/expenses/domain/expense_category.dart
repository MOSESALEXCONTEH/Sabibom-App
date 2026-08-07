import 'package:cloud_firestore/cloud_firestore.dart';

class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.businessId,
    required this.name,
    this.iconName = 'payments',
    this.description,
    this.isSystemCategory = false,
    this.isActive = true,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory ExpenseCategory.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return ExpenseCategory(
      id: snapshot.id,
      businessId: data['businessId'] as String? ?? '',
      name: data['name'] as String? ?? '',
      iconName: data['iconName'] as String? ?? 'payments',
      description: data['description'] as String?,
      isSystemCategory: data['isSystemCategory'] as bool? ?? false,
      isActive: data['isActive'] as bool? ?? true,
      createdBy: data['createdBy'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String businessId;
  final String name;
  final String iconName;
  final String? description;
  final bool isSystemCategory;
  final bool isActive;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const defaultCategories = <({String name, String iconName})>[
    (name: 'Rent', iconName: 'home'),
    (name: 'Electricity', iconName: 'bolt'),
    (name: 'Water', iconName: 'water_drop'),
    (name: 'Internet', iconName: 'wifi'),
    (name: 'Transportation', iconName: 'directions_car'),
    (name: 'Salaries', iconName: 'badge'),
    (name: 'Repairs', iconName: 'build'),
    (name: 'Marketing', iconName: 'campaign'),
    (name: 'Taxes', iconName: 'account_balance'),
    (name: 'Office Supplies', iconName: 'inventory_2'),
    (name: 'Business Purchases', iconName: 'shopping_bag'),
    (name: 'Other', iconName: 'more_horiz'),
  ];
}

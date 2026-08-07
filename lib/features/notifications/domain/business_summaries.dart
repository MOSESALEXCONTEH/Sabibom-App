import 'package:cloud_firestore/cloud_firestore.dart';

class DailyBusinessSummary {
  const DailyBusinessSummary({
    required this.id,
    required this.businessId,
    required this.dateKey,
    required this.timezone,
    required this.status,
    required this.grossSalesMinor,
    required this.netSalesMinor,
    required this.salesCount,
    required this.cashSalesMinor,
    required this.mobileMoneySalesMinor,
    required this.bankTransferSalesMinor,
    required this.cardSalesMinor,
    required this.creditSalesMinor,
    required this.expenseMinor,
    required this.expenseCount,
    required this.costOfGoodsSoldMinor,
    required this.grossProfitMinor,
    required this.netProfitMinor,
    required this.profitIsEstimated,
    required this.customerCreditCreatedMinor,
    required this.customerPaymentsMinor,
    required this.customerOutstandingMinor,
    required this.supplierCreditCreatedMinor,
    required this.supplierPaymentsMinor,
    required this.supplierOutstandingMinor,
    required this.lowStockCount,
    required this.outOfStockCount,
    this.endOfDayStatus,
    this.cashDifferenceMinor = 0,
    this.topProducts = const [],
    this.importantEvents = const [],
    this.generatedAt,
    this.calculationVersion = 1,
  });

  final String id;
  final String businessId;
  final String dateKey;
  final String timezone;
  final String status;
  final int grossSalesMinor;
  final int netSalesMinor;
  final int salesCount;
  final int cashSalesMinor;
  final int mobileMoneySalesMinor;
  final int bankTransferSalesMinor;
  final int cardSalesMinor;
  final int creditSalesMinor;
  final int expenseMinor;
  final int expenseCount;
  final int costOfGoodsSoldMinor;
  final int grossProfitMinor;
  final int netProfitMinor;
  final bool profitIsEstimated;
  final int customerCreditCreatedMinor;
  final int customerPaymentsMinor;
  final int customerOutstandingMinor;
  final int supplierCreditCreatedMinor;
  final int supplierPaymentsMinor;
  final int supplierOutstandingMinor;
  final int lowStockCount;
  final int outOfStockCount;
  final String? endOfDayStatus;
  final int cashDifferenceMinor;
  final List<Map<String, Object?>> topProducts;
  final List<String> importantEvents;
  final DateTime? generatedAt;
  final int calculationVersion;

  factory DailyBusinessSummary.fromMap(String id, Map<String, dynamic> data) {
    return DailyBusinessSummary(
      id: id,
      businessId: (data['businessId'] as String?) ?? '',
      dateKey: (data['dateKey'] as String?) ?? id,
      timezone: (data['timezone'] as String?) ?? 'Africa/Freetown',
      status: (data['status'] as String?) ?? 'ready',
      grossSalesMinor: (data['grossSalesMinor'] as num?)?.toInt() ?? 0,
      netSalesMinor: (data['netSalesMinor'] as num?)?.toInt() ?? 0,
      salesCount: (data['salesCount'] as num?)?.toInt() ?? 0,
      cashSalesMinor: (data['cashSalesMinor'] as num?)?.toInt() ?? 0,
      mobileMoneySalesMinor:
          (data['mobileMoneySalesMinor'] as num?)?.toInt() ?? 0,
      bankTransferSalesMinor:
          (data['bankTransferSalesMinor'] as num?)?.toInt() ?? 0,
      cardSalesMinor: (data['cardSalesMinor'] as num?)?.toInt() ?? 0,
      creditSalesMinor: (data['creditSalesMinor'] as num?)?.toInt() ?? 0,
      expenseMinor: (data['expenseMinor'] as num?)?.toInt() ?? 0,
      expenseCount: (data['expenseCount'] as num?)?.toInt() ?? 0,
      costOfGoodsSoldMinor:
          (data['costOfGoodsSoldMinor'] as num?)?.toInt() ?? 0,
      grossProfitMinor: (data['grossProfitMinor'] as num?)?.toInt() ?? 0,
      netProfitMinor: (data['netProfitMinor'] as num?)?.toInt() ?? 0,
      profitIsEstimated: data['profitIsEstimated'] == true,
      customerCreditCreatedMinor:
          (data['customerCreditCreatedMinor'] as num?)?.toInt() ?? 0,
      customerPaymentsMinor:
          (data['customerPaymentsMinor'] as num?)?.toInt() ?? 0,
      customerOutstandingMinor:
          (data['customerOutstandingMinor'] as num?)?.toInt() ?? 0,
      supplierCreditCreatedMinor:
          (data['supplierCreditCreatedMinor'] as num?)?.toInt() ?? 0,
      supplierPaymentsMinor:
          (data['supplierPaymentsMinor'] as num?)?.toInt() ?? 0,
      supplierOutstandingMinor:
          (data['supplierOutstandingMinor'] as num?)?.toInt() ?? 0,
      lowStockCount: (data['lowStockCount'] as num?)?.toInt() ?? 0,
      outOfStockCount: (data['outOfStockCount'] as num?)?.toInt() ?? 0,
      endOfDayStatus: data['endOfDayStatus'] as String?,
      cashDifferenceMinor:
          (data['cashDifferenceMinor'] as num?)?.toInt() ?? 0,
      topProducts: (data['topProducts'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, Object?>.from(e))
              .toList() ??
          const [],
      importantEvents: (data['importantEvents'] as List?)
              ?.map((e) => '$e')
              .toList() ??
          const [],
      generatedAt: data['generatedAt'] is Timestamp
          ? (data['generatedAt'] as Timestamp).toDate()
          : null,
      calculationVersion: (data['calculationVersion'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'businessId': businessId,
        'dateKey': dateKey,
        'timezone': timezone,
        'status': status,
        'grossSalesMinor': grossSalesMinor,
        'netSalesMinor': netSalesMinor,
        'salesCount': salesCount,
        'cashSalesMinor': cashSalesMinor,
        'mobileMoneySalesMinor': mobileMoneySalesMinor,
        'bankTransferSalesMinor': bankTransferSalesMinor,
        'cardSalesMinor': cardSalesMinor,
        'creditSalesMinor': creditSalesMinor,
        'expenseMinor': expenseMinor,
        'expenseCount': expenseCount,
        'costOfGoodsSoldMinor': costOfGoodsSoldMinor,
        'grossProfitMinor': grossProfitMinor,
        'netProfitMinor': netProfitMinor,
        'profitIsEstimated': profitIsEstimated,
        'customerCreditCreatedMinor': customerCreditCreatedMinor,
        'customerPaymentsMinor': customerPaymentsMinor,
        'customerOutstandingMinor': customerOutstandingMinor,
        'supplierCreditCreatedMinor': supplierCreditCreatedMinor,
        'supplierPaymentsMinor': supplierPaymentsMinor,
        'supplierOutstandingMinor': supplierOutstandingMinor,
        'lowStockCount': lowStockCount,
        'outOfStockCount': outOfStockCount,
        'endOfDayStatus': endOfDayStatus,
        'cashDifferenceMinor': cashDifferenceMinor,
        'topProducts': topProducts,
        'importantEvents': importantEvents,
        'generatedAt': FieldValue.serverTimestamp(),
        'calculationVersion': calculationVersion,
      };
}

class WeeklyBusinessSummary {
  const WeeklyBusinessSummary({
    required this.id,
    required this.businessId,
    required this.weekKey,
    required this.timezone,
    required this.periodStart,
    required this.periodEnd,
    required this.grossSalesMinor,
    required this.netSalesMinor,
    required this.salesCount,
    required this.previousWeekSalesMinor,
    required this.salesChangePercentage,
    required this.expenseMinor,
    required this.previousWeekExpenseMinor,
    required this.expenseChangePercentage,
    required this.costOfGoodsSoldMinor,
    required this.grossProfitMinor,
    required this.netProfitMinor,
    required this.profitIsEstimated,
    this.newCustomers = 0,
    this.customerPaymentsMinor = 0,
    this.customerOutstandingMinor = 0,
    this.supplierPaymentsMinor = 0,
    this.supplierOutstandingMinor = 0,
    this.topProducts = const [],
    this.lowPerformingProducts = const [],
    this.lowStockProducts = const [],
    this.outOfStockProducts = const [],
    this.endOfDayCompletedCount = 0,
    this.endOfDayMissingCount = 0,
    this.cashShortageMinor = 0,
    this.cashSurplusMinor = 0,
    this.approvalCount = 0,
    this.staffActivityHighlights = const [],
    this.generatedAt,
    this.calculationVersion = 1,
  });

  final String id;
  final String businessId;
  final String weekKey;
  final String timezone;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int grossSalesMinor;
  final int netSalesMinor;
  final int salesCount;
  final int previousWeekSalesMinor;
  final double salesChangePercentage;
  final int expenseMinor;
  final int previousWeekExpenseMinor;
  final double expenseChangePercentage;
  final int costOfGoodsSoldMinor;
  final int grossProfitMinor;
  final int netProfitMinor;
  final bool profitIsEstimated;
  final int newCustomers;
  final int customerPaymentsMinor;
  final int customerOutstandingMinor;
  final int supplierPaymentsMinor;
  final int supplierOutstandingMinor;
  final List<Map<String, Object?>> topProducts;
  final List<Map<String, Object?>> lowPerformingProducts;
  final List<Map<String, Object?>> lowStockProducts;
  final List<Map<String, Object?>> outOfStockProducts;
  final int endOfDayCompletedCount;
  final int endOfDayMissingCount;
  final int cashShortageMinor;
  final int cashSurplusMinor;
  final int approvalCount;
  final List<String> staffActivityHighlights;
  final DateTime? generatedAt;
  final int calculationVersion;

  factory WeeklyBusinessSummary.fromMap(String id, Map<String, dynamic> data) {
    DateTime asDate(Object? v, DateTime fallback) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return fallback;
    }

    double safePct(Object? v) {
      final n = (v as num?)?.toDouble() ?? 0;
      if (!n.isFinite) return 0;
      return n;
    }

    return WeeklyBusinessSummary(
      id: id,
      businessId: (data['businessId'] as String?) ?? '',
      weekKey: (data['weekKey'] as String?) ?? id,
      timezone: (data['timezone'] as String?) ?? 'Africa/Freetown',
      periodStart: asDate(data['periodStart'], DateTime.now()),
      periodEnd: asDate(data['periodEnd'], DateTime.now()),
      grossSalesMinor: (data['grossSalesMinor'] as num?)?.toInt() ?? 0,
      netSalesMinor: (data['netSalesMinor'] as num?)?.toInt() ?? 0,
      salesCount: (data['salesCount'] as num?)?.toInt() ?? 0,
      previousWeekSalesMinor:
          (data['previousWeekSalesMinor'] as num?)?.toInt() ?? 0,
      salesChangePercentage: safePct(data['salesChangePercentage']),
      expenseMinor: (data['expenseMinor'] as num?)?.toInt() ?? 0,
      previousWeekExpenseMinor:
          (data['previousWeekExpenseMinor'] as num?)?.toInt() ?? 0,
      expenseChangePercentage: safePct(data['expenseChangePercentage']),
      costOfGoodsSoldMinor:
          (data['costOfGoodsSoldMinor'] as num?)?.toInt() ?? 0,
      grossProfitMinor: (data['grossProfitMinor'] as num?)?.toInt() ?? 0,
      netProfitMinor: (data['netProfitMinor'] as num?)?.toInt() ?? 0,
      profitIsEstimated: data['profitIsEstimated'] == true,
      newCustomers: (data['newCustomers'] as num?)?.toInt() ?? 0,
      customerPaymentsMinor:
          (data['customerPaymentsMinor'] as num?)?.toInt() ?? 0,
      customerOutstandingMinor:
          (data['customerOutstandingMinor'] as num?)?.toInt() ?? 0,
      supplierPaymentsMinor:
          (data['supplierPaymentsMinor'] as num?)?.toInt() ?? 0,
      supplierOutstandingMinor:
          (data['supplierOutstandingMinor'] as num?)?.toInt() ?? 0,
      topProducts: (data['topProducts'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, Object?>.from(e))
              .toList() ??
          const [],
      lowPerformingProducts: (data['lowPerformingProducts'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, Object?>.from(e))
              .toList() ??
          const [],
      lowStockProducts: (data['lowStockProducts'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, Object?>.from(e))
              .toList() ??
          const [],
      outOfStockProducts: (data['outOfStockProducts'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, Object?>.from(e))
              .toList() ??
          const [],
      endOfDayCompletedCount:
          (data['endOfDayCompletedCount'] as num?)?.toInt() ?? 0,
      endOfDayMissingCount:
          (data['endOfDayMissingCount'] as num?)?.toInt() ?? 0,
      cashShortageMinor: (data['cashShortageMinor'] as num?)?.toInt() ?? 0,
      cashSurplusMinor: (data['cashSurplusMinor'] as num?)?.toInt() ?? 0,
      approvalCount: (data['approvalCount'] as num?)?.toInt() ?? 0,
      staffActivityHighlights: (data['staffActivityHighlights'] as List?)
              ?.map((e) => '$e')
              .toList() ??
          const [],
      generatedAt: data['generatedAt'] is Timestamp
          ? (data['generatedAt'] as Timestamp).toDate()
          : null,
      calculationVersion: (data['calculationVersion'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, Object?> toMap() => {
        'businessId': businessId,
        'weekKey': weekKey,
        'timezone': timezone,
        'periodStart': Timestamp.fromDate(periodStart),
        'periodEnd': Timestamp.fromDate(periodEnd),
        'status': 'ready',
        'grossSalesMinor': grossSalesMinor,
        'netSalesMinor': netSalesMinor,
        'salesCount': salesCount,
        'previousWeekSalesMinor': previousWeekSalesMinor,
        'salesChangePercentage': salesChangePercentage,
        'expenseMinor': expenseMinor,
        'previousWeekExpenseMinor': previousWeekExpenseMinor,
        'expenseChangePercentage': expenseChangePercentage,
        'costOfGoodsSoldMinor': costOfGoodsSoldMinor,
        'grossProfitMinor': grossProfitMinor,
        'netProfitMinor': netProfitMinor,
        'profitIsEstimated': profitIsEstimated,
        'newCustomers': newCustomers,
        'customerPaymentsMinor': customerPaymentsMinor,
        'customerOutstandingMinor': customerOutstandingMinor,
        'supplierPaymentsMinor': supplierPaymentsMinor,
        'supplierOutstandingMinor': supplierOutstandingMinor,
        'topProducts': topProducts,
        'lowPerformingProducts': lowPerformingProducts,
        'lowStockProducts': lowStockProducts,
        'outOfStockProducts': outOfStockProducts,
        'endOfDayCompletedCount': endOfDayCompletedCount,
        'endOfDayMissingCount': endOfDayMissingCount,
        'cashShortageMinor': cashShortageMinor,
        'cashSurplusMinor': cashSurplusMinor,
        'approvalCount': approvalCount,
        'staffActivityHighlights': staffActivityHighlights,
        'generatedAt': FieldValue.serverTimestamp(),
        'calculationVersion': calculationVersion,
      };
}

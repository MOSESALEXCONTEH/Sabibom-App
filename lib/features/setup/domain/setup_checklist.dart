import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SetupStepId {
  businessProfile,
  firstProduct,
  firstCustomer,
  firstSale,
  customizeReceipt,
  trySabi,
  notificationPrefs,
  firstBackup,
}

class SetupChecklistStep {
  const SetupChecklistStep({
    required this.id,
    required this.title,
    required this.description,
    required this.routeName,
    required this.isRequired,
    required this.order,
    this.isComplete = false,
  });

  final SetupStepId id;
  final String title;
  final String description;
  final String routeName;
  final bool isRequired;
  final int order;
  final bool isComplete;

  SetupChecklistStep copyWith({bool? isComplete}) => SetupChecklistStep(
        id: id,
        title: title,
        description: description,
        routeName: routeName,
        isRequired: isRequired,
        order: order,
        isComplete: isComplete ?? this.isComplete,
      );
}

class SetupChecklistProgress {
  const SetupChecklistProgress({
    required this.steps,
    required this.dismissed,
  });

  final List<SetupChecklistStep> steps;
  final bool dismissed;

  int get completedCount => steps.where((s) => s.isComplete).length;
  int get totalCount => steps.length;
  bool get allComplete => completedCount >= totalCount;
  bool get shouldShow => !dismissed && !allComplete;
}

/// Builds checklist completion from verified Firestore data + local dismiss.
class SetupChecklistService {
  SetupChecklistService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  static const _dismissKey = 'setup_checklist_dismissed';

  static const definitions = <SetupChecklistStep>[
    SetupChecklistStep(
      id: SetupStepId.businessProfile,
      title: 'Complete business profile',
      description: 'Add your business name, phone and address.',
      routeName: 'settingsBusiness',
      isRequired: true,
      order: 1,
    ),
    SetupChecklistStep(
      id: SetupStepId.firstProduct,
      title: 'Add your first product or service',
      description: 'Create something you can sell.',
      routeName: 'newProduct',
      isRequired: true,
      order: 2,
    ),
    SetupChecklistStep(
      id: SetupStepId.firstCustomer,
      title: 'Add your first customer',
      description: 'Keep customer details ready for credit sales.',
      routeName: 'newCustomer',
      isRequired: false,
      order: 3,
    ),
    SetupChecklistStep(
      id: SetupStepId.firstSale,
      title: 'Record your first sale',
      description: 'Complete a sale and create a receipt.',
      routeName: 'newSale',
      isRequired: true,
      order: 4,
    ),
    SetupChecklistStep(
      id: SetupStepId.customizeReceipt,
      title: 'Customize your receipt',
      description: 'Set branding and receipt layout.',
      routeName: 'settingsReceipt',
      isRequired: false,
      order: 5,
    ),
    SetupChecklistStep(
      id: SetupStepId.trySabi,
      title: 'Try Sabi',
      description: 'Ask Sabi to prepare a sale draft or explain your day.',
      routeName: 'home',
      isRequired: false,
      order: 6,
    ),
    SetupChecklistStep(
      id: SetupStepId.notificationPrefs,
      title: 'Set notification preferences',
      description: 'Choose which alerts you want.',
      routeName: 'settingsNotifications',
      isRequired: false,
      order: 7,
    ),
    SetupChecklistStep(
      id: SetupStepId.firstBackup,
      title: 'Create your first backup',
      description: 'Export a JSON backup and keep it somewhere safe.',
      routeName: 'backup',
      isRequired: false,
      order: 8,
    ),
  ];

  Future<bool> isDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dismissKey) ?? false;
  }

  Future<void> dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissKey, true);
  }

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissKey, false);
  }

  Future<SetupChecklistProgress> load(String businessId) async {
    final dismissed = await isDismissed();
    if (businessId.isEmpty) {
      return SetupChecklistProgress(steps: definitions, dismissed: dismissed);
    }

    final biz = _db.collection('businesses').doc(businessId);
    final results = await Future.wait([
      biz.get(),
      biz.collection('products').limit(1).get(),
      biz.collection('customers').limit(1).get(),
      biz
          .collection('sales')
          .where('saleStatus', isEqualTo: 'completed')
          .limit(1)
          .get(),
      biz.collection('receipt_templates').limit(1).get(),
      biz.collection('settings').doc('receipt').get(),
    ]);

    final bizData = (results[0] as DocumentSnapshot<Map<String, dynamic>>).data();
    final hasProfile = (bizData?['name'] as String?)?.trim().isNotEmpty == true &&
        (bizData?['phoneNumber'] as String?)?.trim().isNotEmpty == true;
    final hasProduct =
        (results[1] as QuerySnapshot).docs.isNotEmpty;
    final hasCustomer =
        (results[2] as QuerySnapshot).docs.isNotEmpty;
    final hasSale = (results[3] as QuerySnapshot).docs.isNotEmpty;
    final hasReceipt = (results[4] as QuerySnapshot).docs.isNotEmpty ||
        (results[5] as DocumentSnapshot).exists;

    // Local preference: user opened Sabi / notifications / backup (best-effort).
    final prefs = await SharedPreferences.getInstance();
    final triedSabi = prefs.getBool('setup_tried_sabi') ?? false;
    final notifPrefs = prefs.getBool('setup_notif_prefs_saved') ?? false;
    final hasBackup = prefs.getBool('setup_first_backup_done') == true ||
        bizData?['lastBackupAt'] != null;

    final steps = definitions
        .map((step) {
          final done = switch (step.id) {
            SetupStepId.businessProfile => hasProfile,
            SetupStepId.firstProduct => hasProduct,
            SetupStepId.firstCustomer => hasCustomer,
            SetupStepId.firstSale => hasSale,
            SetupStepId.customizeReceipt => hasReceipt,
            SetupStepId.trySabi => triedSabi,
            SetupStepId.notificationPrefs => notifPrefs,
            SetupStepId.firstBackup => hasBackup,
          };
          return step.copyWith(isComplete: done);
        })
        .toList(growable: false);

    return SetupChecklistProgress(steps: steps, dismissed: dismissed);
  }

  Future<void> markTriedSabi() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setup_tried_sabi', true);
  }

  Future<void> markNotificationPrefsSaved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setup_notif_prefs_saved', true);
  }

  Future<void> markFirstBackupDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setup_first_backup_done', true);
  }
}

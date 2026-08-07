import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sabibom/features/sabi/data/sabi_learning_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('remembers verified asks and suggests similar kinds', () async {
    final store = SabiLearningStore();
    await store.rememberVerifiedAsk(
      businessId: 'biz1',
      question: 'How much did I sell today?',
      metric: 'sales_total',
    );

    final kind = await store.suggestKind(
      businessId: 'biz1',
      question: 'how much sales today please',
    );
    expect(kind, 'sales');
  });
}

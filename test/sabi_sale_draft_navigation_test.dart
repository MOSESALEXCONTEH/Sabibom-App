import 'package:flutter_test/flutter_test.dart';

import 'package:sabibom/app/router.dart';

void main() {
  test('sabi sale draft lives under the sales shell path', () {
    expect(AppRoutes.sabiSaleDraft, '/sales/sabi-draft');
    expect(AppRouteNames.sabiSaleDraft, 'sabiSaleDraft');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/sabi/domain/sabi_command.dart';

void main() {
  test('agent response carries a reviewable customer draft', () {
    final response = SabiBusinessAnswer.fromMap({
      'verified': false,
      'answer': 'I prepared this customer.',
      'sabiAction': {
        'intent': 'add_customer',
        'confidence': 1,
        'reply': 'Review and confirm.',
        'requiresConfirmation': true,
        'clarifyingQuestion': null,
        'warnings': <String>[],
        'customer': {
          'name': 'James',
          'phone': '07892537',
          'email': null,
          'address': null,
          'notes': null,
        },
        'product': null,
        'expense': null,
        'supplier': null,
      },
    });

    expect(response.sabiAction?.isAddCustomer, isTrue);
    expect(response.sabiAction?.customer?.name, 'James');
    expect(response.sabiAction?.customer?.phone, '07892537');
    expect(response.sabiAction?.requiresConfirmation, isTrue);
  });
}

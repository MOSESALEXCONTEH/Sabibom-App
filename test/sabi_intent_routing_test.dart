import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/sabi/domain/sabi_intent.dart';

void main() {
  group('normalizeSabiInput', () {
    test('corrects misspelled business words', () {
      expect(
        normalizeSabiInput(
          'shwo my custmers with balnce and low stok prodcuts',
        ),
        'shwo my customers with balance and low stock products',
      );
    });

    test('preserves merchant data', () {
      expect(
        normalizeSabiInput('Add Aminata Kargbo, phone 076123456'),
        'Add Aminata Kargbo, phone 076123456',
      );
    });

    test('routes misspelled business questions', () {
      expect(
        sabiLooksLikeMetricQuestion('show my custmers with balnce'),
        isTrue,
      );
      expect(
        sabiLooksLikeMetricQuestion('which prodcuts have low stok'),
        isTrue,
      );
    });
  });

  group('sabiClarificationFor', () {
    test('asks for missing customer details', () {
      final result = sabiClarificationFor('add cutomer only');
      expect(result?.intent, 'add_customer');
      expect(result?.question, contains('customer name'));
      expect(
        sabiCommandWithClarificationContext(
          intent: result!.intent,
          answer: 'Aminata, phone 076123456',
        ),
        'Add customer: Aminata, phone 076123456',
      );
    });

    test('understands client and vendor synonyms', () {
      expect(sabiClarificationFor('create client')?.intent, 'add_customer');
      expect(sabiClarificationFor('add vendor')?.intent, 'create_supplier');
    });

    test('asks targeted questions for every creation flow', () {
      expect(sabiClarificationFor('add supplier')?.intent, 'create_supplier');
      expect(sabiClarificationFor('add product')?.intent, 'add_product');
      expect(sabiClarificationFor('record expense')?.intent, 'create_expense');
      expect(sabiClarificationFor('add purchase')?.intent, 'create_purchase');
      expect(sabiClarificationFor('add sale')?.intent, 'create_receipt');
    });

    test('does not interrupt a complete command', () {
      expect(
        sabiClarificationFor('Add customer Aminata phone 076123456'),
        isNull,
      );
      expect(sabiClarificationFor('Sold 2 rice at 50 Le'), isNull);
    });

    test('identifies a new task while another clarification is pending', () {
      expect(
        sabiCreationIntentFor('Add supplier Mohamed Trading'),
        'create_supplier',
      );
      expect(
        sabiCreationIntentFor('Record 200 transport expense'),
        'create_expense',
      );
    });
  });

  group('parseSabiContactInput', () {
    test('extracts a customer name and phone from a natural reply', () {
      final result = parseSabiContactInput('james phone number 07892537');
      expect(result?.name, 'james');
      expect(result?.phone, '07892537');
    });

    test('extracts optional email without damaging the name', () {
      final result = parseSabiContactInput(
        'name is Aminata, email aminata@example.com',
      );
      expect(result?.name, 'Aminata');
      expect(result?.email, 'aminata@example.com');
    });
  });

  group('resolveSabiFollowUp', () {
    test('uses the recent customer subject for a names follow-up', () {
      expect(
        resolveSabiFollowUp('Give me their names', const [
          'How many customers do I have?',
        ]),
        'List my customers and give me their names',
      );
    });

    test('does not rewrite an unrelated question', () {
      expect(
        resolveSabiFollowUp('How much did I sell today?', const [
          'How many customers do I have?',
        ]),
        'How much did I sell today?',
      );
    });
  });

  group('sabiLooksLikeMetricQuestion', () {
    test('expiry and debt asks are metrics', () {
      expect(sabiLooksLikeMetricQuestion('Look for expiry'), isTrue);
      expect(sabiLooksLikeMetricQuestion('Who owes me money?'), isTrue);
      expect(sabiLooksLikeMetricQuestion('How much did I sell today?'), isTrue);
      expect(
        sabiLooksLikeMetricQuestion('How much did I spend this week?'),
        isTrue,
      );
    });
  });

  group('sabiLooksLikeSaleDraft', () {
    test('sell/sold/receipt open sale draft', () {
      expect(sabiLooksLikeSaleDraft('Sold 2 rice at 50 Le'), isTrue);
      expect(sabiLooksLikeSaleDraft('Make a receipt for oil'), isTrue);
      expect(sabiLooksLikeSaleDraft('Add sale for 2 rice'), isTrue);
    });

    test('bare buy is not a sale', () {
      expect(sabiLooksLikeSaleDraft('Buy something'), isFalse);
      expect(sabiLooksLikeSaleDraft('I bought rice'), isFalse);
    });

    test('metric sell questions are not sale drafts', () {
      expect(sabiLooksLikeSaleDraft('How much did I sell today?'), isFalse);
    });
  });

  group('sabiLooksLikePurchaseDraft', () {
    test('buy stock / purchase / from supplier is purchase', () {
      expect(sabiLooksLikePurchaseDraft('Buy stock from supplier'), isTrue);
      expect(sabiLooksLikePurchaseDraft('Purchase rice from Mohamed'), isTrue);
      expect(
        sabiLooksLikePurchaseDraft('Buy inventory from ABC Trading'),
        isTrue,
      );
    });

    test('bare buy without stock context is not purchase', () {
      expect(sabiLooksLikePurchaseDraft('Buy something'), isFalse);
    });
  });

  group('sabiLooksLikeDataAction', () {
    test('add customer / record expense / add supplier', () {
      expect(sabiLooksLikeDataAction('Add customer Aminata'), isTrue);
      expect(sabiLooksLikeDataAction('Record expense 200 transport'), isTrue);
      expect(
        sabiLooksLikeDataAction('Add Mohamed Trading as a supplier'),
        isTrue,
      );
    });

    test('purchase wording is a data action', () {
      expect(sabiLooksLikeDataAction('Buy stock from supplier'), isTrue);
    });
  });
}

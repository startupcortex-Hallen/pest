import 'package:flutter_test/flutter_test.dart';
import 'package:o_pest_shop/services/checkout_service.dart';

void main() {
  test('novoIdempotencyKey gera UUID v4 válido e único', () {
    final regex = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final primeira = CheckoutService.novoIdempotencyKey();
    final segunda = CheckoutService.novoIdempotencyKey();

    expect(regex.hasMatch(primeira), isTrue);
    expect(regex.hasMatch(segunda), isTrue);
    expect(primeira, isNot(segunda));
  });
}

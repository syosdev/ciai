import 'package:perpul/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('money formats rupiah with dot thousands', () {
    expect(money(1000000), 'Rp 1.000.000');
    expect(money(1234.6), 'Rp 1.235');
    expect(money(-1234.6), '-Rp 1.235');
    expect(money(0), 'Rp 0');
  });

  test('amountText groups digits without prefix', () {
    expect(amountText(1500000), '1.500.000');
  });

  test('formatter groups digits while typing', () {
    final f = RupiahInputFormatter();
    final first = f.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: '1500000'),
    );
    expect(first.text, '1.500.000');
    final second = f.formatEditUpdate(
      first,
      const TextEditingValue(text: '1.500.0000'),
    );
    expect(second.text, '15.000.000');
  });

  test('percent reads as naik/turun with comma decimals', () {
    expect(percent(-37.5), 'turun 37,5%');
    expect(percent(10), 'naik 10,0%');
    expect(percent(0), 'tetap');
  });

  test('parseAmount ignores currency symbols and separators', () {
    expect(parseAmount('Rp 1.000.000'), 1000000);
    expect(parseAmount(''), 0);
  });
}

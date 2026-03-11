import 'package:test/test.dart';

Matcher closeToList(List<num> expected, double epsilon) {
  return predicate<Object?>((value) {
    if (value is! List || value.length != expected.length) return false;
    for (var i = 0; i < expected.length; i++) {
      final actual = value[i];
      if (actual is! num) return false;
      if ((actual - expected[i]).abs() > epsilon) return false;
    }
    return true;
  }, 'list close to $expected');
}

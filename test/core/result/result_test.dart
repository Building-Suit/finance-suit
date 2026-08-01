import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:work_tracker/core/errors/app_failure.dart';
import 'package:work_tracker/core/result/result.dart';

void main() {
  test('guard maps never-completing operations to timeout failures', () async {
    final result = await guard<void>(
      () => Completer<void>().future,
      timeout: const Duration(milliseconds: 1),
    );

    expect(result, isA<Err<void>>());
    expect(result.failureOrNull, isA<TimeoutFailure>());
  });
}

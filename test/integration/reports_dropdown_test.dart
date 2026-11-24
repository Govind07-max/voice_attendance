import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_attendance/features/reports/reports_screen.dart';
import 'package:voice_attendance/models/class_subject.dart';
import 'package:voice_attendance/providers/classes_provider.dart';

List<ClassSubjectModel> buildCs(String id) => [
      ClassSubjectModel(
        id: id,
        teacherId: 't1',
        classId: 'c1',
        subjectId: 's1',
        googleFormUrl: '',
        thresholdPercent: 75,
      ),
    ];

/// Regression test: the class + subject dropdown must stay valid when the
/// provider refetches and returns NEW model instances for the same rows.
///
/// Before the fix the dropdown used the model object as its value, so the
/// stale selection matched no item and Flutter threw:
///   "There should be exactly one item with [DropdownButtonFormField]'s
///    value ... Either zero or 2 or more [DropdownMenuItem]s were detected"
void main() {
  testWidgets('the reports dropdown survives a provider refetch',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var current = buildCs('cs1');

    final container = ProviderContainer(
      overrides: [
        classSubjectsProvider.overrideWith((ref) => current),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ReportsScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);

    // A refetch returns new instances with the same id.
    current = buildCs('cs1');
    container.invalidate(classSubjectsProvider);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull,
        reason: 'the dropdown must not crash when the list is refetched');
  });
}

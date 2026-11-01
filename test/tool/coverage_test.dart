import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/coverage.dart';

void main() {
  test('gates hand-written data and view model files only', () {
    expect(gated('lib/data/services/binary_service.dart'), isTrue);
    expect(gated('lib/ui/home/view_model/home_view_model.dart'), isTrue);
    expect(gated(r'lib\data\repositories\x.dart'), isTrue);
    expect(gated('lib/ui/home/widgets/home_view.dart'), isFalse);
    expect(gated('lib/domain/models/job.dart'), isFalse);
    expect(gated('lib/ui/home/view_model/home_view_model.g.dart'), isFalse);
    expect(gated('lib/data/x.freezed.dart'), isFalse);
  });

  test('counts found and hit lines of gated files', () {
    const lcov = '''
SF:lib/data/a.dart
DA:1,3
DA:2,0
DA:3,1
end_of_record
SF:lib/ui/home/widgets/home_view.dart
DA:1,0
end_of_record
SF:lib/ui/queue/view_model/queue_view_model.dart
DA:5,0
end_of_record
''';
    expect(gatedLines(lcov), (found: 4, hit: 2));
    expect(gatedLines(''), (found: 0, hit: 0));
  });
}

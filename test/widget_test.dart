import 'package:flutter_test/flutter_test.dart';
import 'package:audio_splitter/main.dart';

void main() {
  testWidgets('AudioSplitterApp renders correctly with Overlap settings and empty drop zone', (WidgetTester tester) async {
    await tester.pumpWidget(const AudioSplitterApp());

    // Verify header branding
    expect(find.text('AudioSplitter'), findsOneWidget);
    expect(find.text('macOS M4A Edition'), findsOneWidget);

    // Verify Overlap section
    expect(find.text('Audio Overlap:'), findsOneWidget);
    expect(find.text('Off (0s)'), findsOneWidget);
    expect(find.text('5s'), findsOneWidget);
    expect(find.text('10s'), findsOneWidget);
    expect(find.text('15s'), findsOneWidget);

    // Verify empty drop zone texts (no preview shown when empty)
    expect(find.text('Drop .m4a files here'), findsOneWidget);
    expect(find.text('or click "Add Files..." above to browse'), findsOneWidget);

    // Verify Start action button
    expect(find.text('Start Splitting'), findsOneWidget);
  });
}

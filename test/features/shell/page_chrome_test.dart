import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/shell/page_chrome.dart';

/// Pages publish their chrome to the shell after the frame, so whatever the
/// controller answers before that is what the user sees first. For the title
/// that means a fallback; for the body width it means a layout, which is why
/// the default has to be the ordinary one.
void main() {
  late PageChromeController controller;

  setUp(() => controller = PageChromeController());

  test('a page that has published nothing is not full width', () {
    // Anything else would lay every board out wide for one frame and then snap
    // it back — a visible jump on a page that was never meant to be wide.
    expect(controller.fullWidthFor('/boards/7'), isFalse);
  });

  test('honours full width only for the route that asked for it', () {
    controller.publish(
      const PageChromeData(location: '/boards/7', fullWidth: true),
    );

    expect(controller.fullWidthFor('/boards/7'), isTrue);
    // Chrome from a page being torn down must not widen the one replacing it.
    expect(controller.fullWidthFor('/boards/8'), isFalse);
    expect(controller.fullWidthFor('/issues'), isFalse);
  });

  test('notifies when only the width changed', () {
    var notified = 0;
    controller.addListener(() => notified++);

    const before = PageChromeData(location: '/boards/7', title: 'Board');
    controller.publish(before);
    expect(notified, 1);

    // Same title, same route — the board simply gained a column. Without this
    // the shell would keep the old width.
    controller.publish(
      const PageChromeData(
        location: '/boards/7',
        title: 'Board',
        fullWidth: true,
      ),
    );
    expect(notified, 2);

    // Republishing the same data stays silent, so a page rebuilding freely
    // doesn't churn the shell.
    controller.publish(
      const PageChromeData(
        location: '/boards/7',
        title: 'Board',
        fullWidth: true,
      ),
    );
    expect(notified, 2);
  });
}

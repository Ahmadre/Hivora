import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/shell/page_chrome.dart';

/// Pages publish their chrome to the shell after the frame, so whatever the
/// controller answers before that is what the user sees first. For the title
/// that means a fallback; for the body width it means a layout, which is why
/// the default has to be the ordinary one.
void main() {
  late PageChromeController controller;
  final page = Object();

  setUp(() => controller = PageChromeController());

  test('a page that has published nothing is not full width', () {
    // Anything else would lay every board out wide for one frame and then snap
    // it back — a visible jump on a page that was never meant to be wide.
    expect(controller.fullWidthFor('/boards/7'), isFalse);
  });

  test('honours full width only for the route that asked for it', () {
    controller.publish(
      page,
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
    controller.publish(page, before);
    expect(notified, 1);

    // Same title, same route — the board simply gained a column. Without this
    // the shell would keep the old width.
    controller.publish(
      page,
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
      page,
      const PageChromeData(
        location: '/boards/7',
        title: 'Board',
        fullWidth: true,
      ),
    );
    expect(notified, 2);
  });

  group('a page still mounted under a pushed route', () {
    // `/admin` stays alive and keeps rebuilding while `/admin/users` is pushed
    // over it, so it re-publishes its own chrome at unpredictable moments — the
    // one under a LayoutBuilder even publishes after the pages that aren't.
    // Whoever lands last must not be able to blank the visible page's bar.
    const invite = PageAction(icon: Icons.add, label: 'Benutzer einladen');
    final toolbar = Container();

    final users = Object();
    final admin = Object();

    void publishUsers() => controller.publish(
      users,
      PageChromeData(
        location: '/admin/users',
        title: 'Benutzer',
        actions: const [invite],
        bottom: toolbar,
        bottomHeight: 88,
      ),
    );

    void publishAdmin() => controller.publish(
      admin,
      const PageChromeData(location: '/admin', title: 'Allgemein'),
    );

    void expectUsersChromeIntact() {
      expect(controller.titleFor('/admin/users'), 'Benutzer');
      expect(controller.actionsFor('/admin/users'), [invite]);
      expect(controller.bottomFor('/admin/users'), same(toolbar));
      expect(controller.bottomHeightFor('/admin/users'), 88);
    }

    test('cannot displace the visible page by publishing after it', () {
      publishUsers();
      publishAdmin();

      expectUsersChromeIntact();
      expect(controller.titleFor('/admin'), 'Allgemein');
    });

    test('cannot displace the visible page by publishing before it', () {
      publishAdmin();
      publishUsers();

      expectUsersChromeIntact();
      expect(controller.titleFor('/admin'), 'Allgemein');
    });

    test('re-publishing on every rebuild leaves the visible page alone', () {
      publishUsers();
      for (var i = 0; i < 5; i++) {
        publishAdmin();
      }

      expectUsersChromeIntact();
    });
  });

  test('a disposed page takes its chrome with it', () {
    // Otherwise the actions of a page that no longer exists would be rendered
    // for a frame when its route is entered again — with callbacks closing over
    // a dead State.
    controller.publish(
      page,
      const PageChromeData(location: '/admin/users', title: 'Benutzer'),
    );
    controller.retract(page);

    expect(controller.titleFor('/admin/users'), isNull);
    expect(controller.actionsFor('/admin/users'), isEmpty);
  });

  test('a page only retracts chrome it published itself', () {
    // The replacement publishes before the page it replaced is disposed, so a
    // blind removal would strip the bar of the page that is actually on screen.
    final outgoing = Object();
    final incoming = Object();

    controller.publish(
      outgoing,
      const PageChromeData(location: '/admin', title: 'Sicherheit'),
    );
    controller.publish(
      incoming,
      const PageChromeData(location: '/admin', title: 'Audit-Log'),
    );
    controller.retract(outgoing);

    expect(controller.titleFor('/admin'), 'Audit-Log');
  });

  test('a page that moves route does not leave chrome behind', () {
    controller.publish(
      page,
      const PageChromeData(location: '/boards/7', title: 'Board 7'),
    );
    controller.publish(
      page,
      const PageChromeData(location: '/boards/8', title: 'Board 8'),
    );

    expect(controller.titleFor('/boards/8'), 'Board 8');
    expect(controller.titleFor('/boards/7'), isNull);
  });
}

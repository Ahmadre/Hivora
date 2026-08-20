@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/util/file_download_io.dart';

/// Where a download lands on Linux.
///
/// The interesting case is the snap, where the folder cannot be looked up: HOME
/// points at the sandbox's own data directory and the `home` interface hides
/// the dotfile that names the real Downloads folder, so `xdg-user-dir DOWNLOAD`
/// answers with something plausible and wrong. These pin the rule that
/// replaces it — and pin just as hard that an *unconfined* app which merely
/// inherited a snap's variables (anything started from a terminal inside the
/// VS Code snap) keeps the XDG answer.
void main() {
  group('downloadDirectories', () {
    test('unconfined: the XDG folder, whatever it is called', () {
      expect(
        downloadDirectories(
          environment: const {'HOME': '/home/u'},
          xdgDownloads: '/home/u/Downloads-de',
        ),
        ['/home/u/Downloads-de'],
      );
    });

    test('unconfined without an XDG answer: ~/Downloads', () {
      expect(
        downloadDirectories(environment: const {'HOME': '/home/u'}),
        ['/home/u/Downloads'],
      );
    });

    test('no HOME at all still names a folder', () {
      // A file the user can find beats a failure; the working directory is
      // somewhere, and a download that threw is nowhere.
      expect(downloadDirectories(environment: const {}), ['./Downloads']);
    });

    test('snap: the real home first, the confined one as a fallback', () {
      // The XDG value is what `xdg-user-dir DOWNLOAD` would answer inside the
      // sandbox — the snap's own HOME — and it is deliberately ignored.
      expect(
        downloadDirectories(
          environment: const {
            'SNAP': '/snap/hinata/42',
            'SNAP_REAL_HOME': '/home/u',
            'HOME': '/home/u/snap/hinata/42',
          },
          xdgDownloads: '/home/u/snap/hinata/42',
        ),
        ['/home/u/Downloads', '/home/u/snap/hinata/42/Downloads'],
      );
    });

    test('a snap variable inherited by an unconfined app changes nothing', () {
      // Started from a terminal inside some other snap: both variables are set
      // and HOME is already the real home, so there is nothing to correct.
      expect(
        downloadDirectories(
          environment: const {
            'SNAP': '/snap/code/175',
            'SNAP_REAL_HOME': '/home/u',
            'HOME': '/home/u',
          },
          xdgDownloads: '/home/u/Downloads-de',
        ),
        ['/home/u/Downloads-de'],
      );
    });

    test('a relative SNAP_REAL_HOME is not a home directory', () {
      expect(
        downloadDirectories(
          environment: const {'SNAP_REAL_HOME': 'home', 'HOME': '/home/u'},
          xdgDownloads: '/home/u/Downloads',
        ),
        ['/home/u/Downloads'],
      );
    });
  });
}

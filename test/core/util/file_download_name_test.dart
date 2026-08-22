@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/util/file_download_io.dart';

/// The name a downloaded file lands under.
///
/// It comes from the server, so it is the one part of a download somebody else
/// writes: it decides what is created in the user's Downloads folder and what
/// the confirmation toast reads back to them. The invisible characters below
/// are written as escapes on purpose — a test about text that hides itself
/// should not itself contain text that hides itself.
void main() {
  group('safeDownloadName', () {
    test('leaves an ordinary name alone', () {
      expect(safeDownloadName('Sprint 24 report.pdf'), 'Sprint 24 report.pdf');
      expect(safeDownloadName('Übersicht — Q3.xlsx'), 'Übersicht — Q3.xlsx');
    });

    test('cannot name a path', () {
      // Neither separator survives, so nothing addresses a directory — and
      // `..` is not a file name, it is an instruction.
      expect(safeDownloadName('../../etc/passwd'), isNot(contains('/')));
      expect(
        safeDownloadName(r'..\..\windows\system32'),
        isNot(contains(r'\')),
      );
      expect(safeDownloadName('..'), 'download');
      expect(safeDownloadName('....'), 'download');
      // A separator becomes an underscore rather than the fallback name: it
      // is still a name, it just cannot be a path any more.
      expect(safeDownloadName('/'), '_');
    });

    test('strips the characters that make a name lie about itself', () {
      // U+202E reverses everything after it, so this reads as "invoiceexe.png"
      // in the toast and in the file manager while being an .exe on disk.
      final spoofed = safeDownloadName('invoice\u202Egnp.exe');
      expect(spoofed, isNot(contains('\u202E')));
      expect(spoofed, endsWith('.exe'));

      for (final control in ['\n', '\r', '\u0007', '\u200E', '\u2069']) {
        expect(
          safeDownloadName('report${control}x.pdf'),
          isNot(contains(control)),
          reason: 'kept U+${control.runes.first.toRadixString(16)}',
        );
      }
    });

    test('never produces an empty name', () {
      for (final raw in ['', '   ', '\u202E', '.', r'\']) {
        expect(
          safeDownloadName(raw),
          isNotEmpty,
          reason: 'for ${json.encode(raw)}',
        );
      }
    });

    test('fits the filesystem, keeping the extension and whole characters', () {
      final safe = safeDownloadName('${'ä' * 400}.pdf');

      expect(utf8.encode(safe).length, lessThanOrEqualTo(200));
      expect(safe, endsWith('.pdf'));
      // Cut on a rune boundary: half of a two-byte character is not a name.
      expect(() => utf8.decode(utf8.encode(safe)), returnsNormally);
      expect(safe, startsWith('ää'));
    });

    test('does not mistake a dotted sentence for an extension', () {
      // A dot far from the end is part of the text, and truncating there would
      // throw almost the whole name away.
      final safe = safeDownloadName('${'a' * 300}. and then some more words');
      expect(utf8.encode(safe).length, lessThanOrEqualTo(200));
      expect(safe, startsWith('aaa'));
    });
  });
}

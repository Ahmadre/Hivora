import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/admin/moderation/moderation_models.dart';

/// The image tier is the one place the admin panel could lie to an operator.
/// Image moderation is enabled by default, Hinata ships no classifier, and the
/// switch reads "on" either way — so these tests are mostly about the states
/// that must NOT be reported as working.
void main() {
  group('ImageTierState wire mapping', () {
    test('round-trips every state the server can send', () {
      for (final state in ImageTierState.values) {
        if (state == ImageTierState.unknown) continue;
        expect(ImageTierState.fromWire(state.wire), state);
      }
    });

    /// A newer server teaching us a state we cannot read must not degrade into
    /// "everything is fine" — that is the original bug wearing a new hat.
    test('an unrecognised or missing value becomes unknown, never active', () {
      expect(ImageTierState.fromWire('SOMETHING_NEW'), ImageTierState.unknown);
      expect(ImageTierState.fromWire(null), ImageTierState.unknown);
      expect(ImageTierState.fromWire(''), ImageTierState.unknown);
    });
  });

  group('what the operator is nudged about', () {
    test('the two states with an action attached warrant attention', () {
      expect(ImageTierState.notConfigured.warrantsAttention, isTrue);
      expect(ImageTierState.configuredUnavailable.warrantsAttention, isTrue);
    });

    test('an unreadable state warrants attention rather than silence', () {
      expect(ImageTierState.unknown.warrantsAttention, isTrue);
    });

    test('a working or deliberately disabled tier stays quiet', () {
      expect(ImageTierState.active.warrantsAttention, isFalse);
      // The operator chose this and does not need reminding on every visit.
      expect(ImageTierState.disabledByPolicy.warrantsAttention, isFalse);
    });

    test('every state has its own i18n key', () {
      final keys = ImageTierState.values.map((s) => s.labelKey).toSet();
      expect(keys, hasLength(ImageTierState.values.length));
      expect(
        keys.every((k) => k.startsWith('moderation.policy.imageTier.')),
        isTrue,
      );
    });
  });

  group('ModerationSummary', () {
    test('parses the admin summary payload', () {
      final summary = ModerationSummary.fromJson(const {
        'openRecords': 12,
        'openReports': 3,
        'open': 15,
        'imageTier': 'NOT_CONFIGURED',
      });

      expect(summary.openRecords, 12);
      expect(summary.openReports, 3);
      expect(summary.open, 15);
      expect(summary.imageTier, ImageTierState.notConfigured);
    });

    /// An older server that does not send the field yet must not read as a
    /// working classifier.
    test('a payload without the field reports unknown, not active', () {
      final summary = ModerationSummary.fromJson(const {'open': 0});

      expect(summary.imageTier, ImageTierState.unknown);
      expect(summary.imageTier.warrantsAttention, isTrue);
    });

    test('tolerates a completely empty payload', () {
      final summary = ModerationSummary.fromJson(const {});

      expect(summary.open, 0);
      expect(summary.imageTier, ImageTierState.unknown);
    });
  });
}

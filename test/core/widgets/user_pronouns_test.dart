import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/widgets/hive_widgets.dart';
import 'package:hinata/core/widgets/user_pronouns.dart';

/// Pronouns are shown in two mutually exclusive ways — spelled out next to a
/// name, or in the avatar's tooltip where there is only a face. What these
/// tests pin down is the "or": nobody should ever read them twice, and someone
/// who has not filled the field in must render exactly as they did before.
void main() {
  group('normalizePronouns', () {
    test('nothing said stays nothing', () {
      expect(normalizePronouns(null), isNull);
      expect(normalizePronouns(''), isNull);
      expect(normalizePronouns('   '), isNull);
    });

    test('trims what was said', () {
      expect(normalizePronouns('  they/them  '), 'they/them');
    });
  });

  group('personTooltip', () {
    test('is the name alone when there are no pronouns', () {
      expect(personTooltip(name: 'Alex Rivera'), 'Alex Rivera');
    });

    test('joins name and pronouns when there are', () {
      expect(
        personTooltip(name: 'Alex Rivera', pronouns: 'they/them'),
        'Alex Rivera · they/them',
      );
    });

    test('is empty when there is nothing at all to say', () {
      expect(personTooltip(name: '   '), isEmpty);
    });

    test('is the pronouns alone when the name is not known', () {
      expect(personTooltip(name: '', pronouns: 'she/her'), 'she/her');
    });
  });

  group('pronounsById', () {
    test('indexes only the people who have said', () {
      const users = [
        DirectoryUser(id: 'a', username: 'a', displayName: 'A', pronouns: ' '),
        DirectoryUser(id: 'b', username: 'b', displayName: 'B'),
        DirectoryUser(
          id: 'c',
          username: 'c',
          displayName: 'C',
          pronouns: ' they/them ',
        ),
      ];
      expect(pronounsById(users), {'c': 'they/them'});
    });
  });

  group('PronounsLabel', () {
    testWidgets('renders nothing at all when unset', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PronounsLabel(pronouns: '  ')),
        ),
      );
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('renders the trimmed value when set', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PronounsLabel(pronouns: ' she/her ')),
        ),
      );
      expect(find.text('she/her'), findsOneWidget);
    });
  });

  group('HiveAvatar', () {
    testWidgets('wraps in a tooltip only once pronouns are known', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: HiveAvatar(name: 'Alex')),
        ),
      );
      // No pronouns → no tooltip, so an avatar that already sits inside one
      // (board people strip, sprint card) can never end up with two.
      expect(find.byType(Tooltip), findsNothing);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HiveAvatar(name: 'Alex', pronouns: 'they/them'),
          ),
        ),
      );
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, 'Alex · they/them');
    });
  });
}

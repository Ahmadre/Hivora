/// What a reader can actually make out on the glass.
///
/// Glass is only ever as legible as what it floats over, and the surfaces that
/// float *without* a scrim behind them — the anchored dropdown, the popup menu
/// — land wherever their field happens to be: over the dashboard's dark hero
/// card, over an image, over a coloured chip. So the panel has to carry its own
/// base, and the base has to hold up against the two extremes any page can put
/// behind it.
///
/// These are the numbers, not the widget: a fill quietly lowered again is the
/// exact regression this pins, and it shows up here before anyone squints at a
/// screenshot.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/search/search_tokens.dart';

/// [over] seen through [layer], both opaque-channel sRGB.
Color _composite(Color layer, Color over) {
  final a = layer.a;
  return Color.fromARGB(
    255,
    ((layer.r * a + over.r * (1 - a)) * 255).round(),
    ((layer.g * a + over.g * (1 - a)) * 255).round(),
    ((layer.b * a + over.b * (1 - a)) * 255).round(),
  );
}

double _channel(double value) => value <= 0.03928
    ? value / 12.92
    : math.pow((value + 0.055) / 1.055, 2.4).toDouble();

/// WCAG 2.1 relative luminance.
double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

/// WCAG 2.1 contrast ratio, 1..21.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// The surface a scrimless glass panel actually presents: the page, then the
/// lens fill, then the panel's own base tint.
Color _panelSurface(SearchTokens tokens, Color behind) =>
    _composite(tokens.tint, _composite(tokens.glassFill, behind));

void main() {
  // Anything a page can put behind a dropdown lies between these two.
  const darkest = Color(0xFF000000);
  const brightest = Color(0xFFFFFFFF);

  group('a scrimless glass panel', () {
    for (final (name, tokens) in [
      ('light', SearchTokens.light),
      ('dark', SearchTokens.dark),
    ]) {
      test('reads its own text on $name glass, over anything', () {
        for (final behind in [darkest, brightest]) {
          final surface = _panelSurface(tokens, behind);
          expect(
            _contrast(tokens.ink, surface),
            greaterThanOrEqualTo(4.5),
            reason: 'primary ink on $name glass over $behind is below WCAG AA',
          );
        }
      });

      test('reads its secondary text on $name glass, over anything', () {
        for (final behind in [darkest, brightest]) {
          final surface = _panelSurface(tokens, behind);
          // AA for large/secondary text. The subtitle under a picker's title
          // is the line this is about, and it is the first to go.
          expect(
            _contrast(tokens.inkSoft, surface),
            greaterThanOrEqualTo(3.0),
            reason:
                'secondary ink on $name glass over $behind is below WCAG AA',
          );
        }
      });

      test('lets at most a quarter of the page through on $name glass', () {
        // The other half of the complaint: the panel took on whatever it was
        // over, so the same list did not read as one surface. Glass is meant
        // to carry its backdrop — a quarter of it, not most of it.
        final through = (1 - tokens.glassFill.a) * (1 - tokens.tint.a);
        expect(
          through,
          lessThanOrEqualTo(0.25),
          reason: '$name glass shows too much of what is behind it',
        );
        // And not none of it: an opaque card is not this material.
        expect(through, greaterThan(0.10));
      });
    }

    test('the dropdown scrim stays lighter than the modal one', () {
      // A dropdown is an inline editor. Dimming the page like a modal would
      // say the rest of the screen is gone, which it is not.
      for (final tokens in [SearchTokens.light, SearchTokens.dark]) {
        expect(tokens.popoverScrim.a, lessThan(tokens.scrim.a));
        expect(tokens.popoverScrim.a, greaterThan(0));
      }
    });
  });
}

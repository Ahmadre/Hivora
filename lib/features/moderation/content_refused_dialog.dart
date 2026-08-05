import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../legal/legal_links.dart';
import '../sprint/modals/glass_modal.dart';

/// HTTP status the server answers with when it refuses content.
///
/// 422 and not 400: the request was well-formed and understood — it was the
/// *content* that was refused. That distinction is the whole reason this file
/// exists, because it is what lets the client tell a policy decision apart from
/// a malformed field and answer each with the right surface.
const int kContentRefusedStatus = 422;

/// Panel width below which the dialog's two actions stack instead of sitting
/// side by side.
///
/// Sized from the German labels rather than from a device class, because those
/// are what actually run out of room: "Kontakt aufnehmen" and "Inhalt
/// bearbeiten", each with a leading icon, need roughly 300pt together, and a
/// modal on a 280pt-wide screen offers about 200pt between its paddings.
const double _kStackedActionsWidth = 360;

/// Whether [failure] is a content refusal rather than an ordinary error.
bool isContentRefusal(ApiFailure failure) =>
    failure.statusCode == kContentRefusedStatus;

/// Shows the refusal dialog for [failure] and reports whether it did.
///
/// The intended call shape at every content-submitting site:
///
/// ```dart
/// on ApiFailure catch (failure) {
///   if (handleContentRefusal(context, failure)) return;
///   _toast(failure.message);
/// }
/// ```
///
/// Returning a `bool` synchronously (rather than awaiting the dialog) is
/// deliberate: the caller's only remaining job is to *not* also fire its generic
/// error path, and making it await a dialog the user may leave open for a minute
/// would keep a save button spinning that whole time.
///
/// The caller must not clear its draft on this path. That is the single most
/// important rule around a refusal — someone who spent ten minutes writing a
/// defect report and is told "not allowed" does not retype it, they give up, or
/// they move the conversation somewhere nobody can moderate it at all.
bool handleContentRefusal(BuildContext context, ApiFailure failure) {
  if (!isContentRefusal(failure)) return false;
  unawaited(showContentRefusedDialog(context, failure.message));
  return true;
}

/// Opens the "Content refused" dialog.
///
/// [message] is the server's own statement of reasons. It arrives already
/// localized — `ApiClient` sends `Accept-Language` on every request and the
/// backend resolves the message against its own bundles — and it already names
/// the policy category, so it is rendered **verbatim** rather than mapped onto a
/// client-side string. Passing it through `context.t` anyway is safe (a lookup
/// miss returns the input unchanged) and covers the transport-failure fallbacks
/// that share the same field.
///
/// Beyond the reason, the dialog says two things the reason alone does not, both
/// of which a refusal owes the person on the other end: that the decision came
/// from an automated check, and where to take it if they think it is wrong.
Future<void> showContentRefusedDialog(
  BuildContext context,
  String message,
) => showGlassModal<void>(
  context,
  width: 460,
  builder: (_) => _ContentRefusedBody(message: message),
);

class _ContentRefusedBody extends StatelessWidget {
  const _ContentRefusedBody({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  LucideIcons.shieldAlert,
                  size: 20,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    context.t('moderation.refused.title'),
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBrand,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: context.t('common.close'),
                onPressed: () => Navigator.of(context).maybePop(),
                visualDensity: VisualDensity.compact,
                icon: Icon(LucideIcons.x, size: 20, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The statement of reasons, given its own tinted block so it
                // reads as the server speaking rather than as app copy.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Text(
                    context.t(message),
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _Note(
                  icon: LucideIcons.cpu,
                  text: context.t('moderation.refused.automated'),
                ),
                const SizedBox(height: 10),
                _Note(
                  icon: LucideIcons.pencil,
                  text: context.t('moderation.refused.draftKept'),
                ),
                const SizedBox(height: 10),
                _Note(
                  icon: LucideIcons.lifeBuoy,
                  text: context.t('moderation.refused.appeal'),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.hairline.withValues(alpha: 0.6)),
            ),
          ),
          child: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final contact = TextButton.icon(
                  onPressed: () => openTermsOfService(context),
                  icon: const Icon(LucideIcons.externalLink, size: 15),
                  label: Text(
                    context.t('moderation.refused.contact'),
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.inkSoft,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
                final dismiss = FilledButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusControl,
                      ),
                    ),
                  ),
                  icon: const Icon(LucideIcons.pencil, size: 15),
                  label: Text(
                    context.t('moderation.refused.editContent'),
                    overflow: TextOverflow.ellipsis,
                  ),
                );

                // Two labelled buttons side by side do not fit a phone-width
                // modal in German — "Kontakt aufnehmen" and "Inhalt bearbeiten"
                // together need roughly 300pt of the ~200pt available inside a
                // 280pt-wide screen. Below the threshold they stack, primary
                // action first, which is the ordinary mobile dialog shape
                // anyway. Above it the original row is unchanged.
                if (constraints.maxWidth < _kStackedActionsWidth) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      dismiss,
                      const SizedBox(height: 4),
                      contact,
                    ],
                  );
                }
                // Both sides flex, not just the secondary one: the primary label
                // is a translation too, and a language that renders it long
                // should ellipsize rather than overflow the panel.
                return Row(
                  children: [
                    Flexible(child: contact),
                    const SizedBox(width: 8),
                    const Spacer(),
                    Flexible(child: dismiss),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// An icon + one line of explanation in the refusal body.
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: AppColors.inkFaint),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.inkSoft,
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/branding/org_logo.dart';
import '../../../core/i18n/i18n.dart';
import '../admin_form_helpers.dart';
import 'ingest_connections_card.dart';

/// Email settings: outbound SMTP + inbound email-to-ticket (IMAP).
class AdminEmailSection extends StatefulWidget {
  const AdminEmailSection({super.key, required this.settings});

  final Map<String, dynamic> settings;

  @override
  State<AdminEmailSection> createState() => _AdminEmailSectionState();
}

class _AdminEmailSectionState extends State<AdminEmailSection> {
  Map<String, dynamic> get _smtp =>
      (widget.settings['smtp'] ??= <String, dynamic>{}) as Map<String, dynamic>;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Outbound SMTP ───────────────────────────────────────
        AdminSectionCard(
          icon: LucideIcons.send,
          title: context.t('admin.smtpTitle'),
          subtitle: context.t('admin.smtpHint'),
          children: [
            AdminToggle(
              label: context.t('admin.smtpEnabled'),
              value: _smtp['enabled'] == true,
              onChanged: (v) => setState(() => _smtp['enabled'] = v),
            ),
            if (_smtp['enabled'] == true) ...[
              const SizedBox(height: 8),
              AdminField(
                label: context.t('admin.smtpHost'),
                initialValue: (_smtp['host'] as String?) ?? '',
                onChanged: (v) => _smtp['host'] = v,
                hint: 'mail.example.com',
              ),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: AdminNumberField(
                      label: context.t('admin.smtpPort'),
                      value: (_smtp['port'] as int?) ?? 587,
                      min: 1,
                      max: 65535,
                      onChanged: (v) => _smtp['port'] = v,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: AdminToggle(
                      label: context.t('admin.smtpStartTls'),
                      value: (_smtp['starttls'] as bool?) ?? true,
                      onChanged: (v) => setState(() => _smtp['starttls'] = v),
                    ),
                  ),
                ],
              ),
              AdminField(
                label: context.t('admin.smtpUsername'),
                initialValue: (_smtp['username'] as String?) ?? '',
                onChanged: (v) => _smtp['username'] = v,
              ),
              AdminField(
                label: context.t('admin.smtpPassword'),
                initialValue: '',
                isSecret: true,
                onChanged: (v) => _smtp['password'] = v,
              ),
              AdminField(
                label: context.t('admin.smtpFromAddress'),
                initialValue:
                    (_smtp['fromAddress'] as String?) ?? 'hinata@localhost',
                onChanged: (v) => _smtp['fromAddress'] = v,
                keyboardType: TextInputType.emailAddress,
              ),
              AdminField(
                label: context.t('admin.smtpFromName'),
                // Seeded from the organization, not from the product: a fresh
                // instance should mail as whoever runs it. Left blank on the
                // server, this is exactly what SmtpMailSenderProvider falls
                // back to anyway — the field just shows what will happen.
                initialValue:
                    (_smtp['fromName'] as String?) ?? orgOrProductName(context),
                onChanged: (v) => _smtp['fromName'] = v,
              ),
            ],
          ],
        ),

        const SizedBox(height: 16),

        // ─── Email-to-Ticket (IMAP ingest) ───────────────────────
        // Self-contained connection management: own endpoints, saves
        // immediately — independent of the section-level settings save.
        const IngestConnectionsCard(),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../notes/email_drafter.dart';
import 'app_theme.dart';

class EmailDraftSheet extends StatefulWidget {
  const EmailDraftSheet({
    super.key,
    required this.draftFuture,
    this.title = 'Draft Follow-up Email',
  });

  final Future<EmailDraft> draftFuture;
  final String title;

  static Future<void> showActionDraft(
    BuildContext context, {
    required String task,
    String? meetingTitle,
    String? owner,
    String? deadline,
  }) {
    final drafter = EmailDrafter();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EmailDraftSheet(
        title: 'Action Item Follow-up',
        draftFuture: drafter.draftActionItem(
          task: task,
          meetingTitle: meetingTitle,
          owner: owner,
          deadline: deadline,
        ),
      ),
    );
  }

  static Future<void> showRecapDraft(
    BuildContext context, {
    required String meetingTitle,
    required String recapHeadline,
    List<String> decisions = const [],
    List<String> actionItems = const [],
  }) {
    final drafter = EmailDrafter();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EmailDraftSheet(
        title: 'Meeting Follow-up Email',
        draftFuture: drafter.draftMeetingRecap(
          meetingTitle: meetingTitle,
          recapHeadline: recapHeadline,
          decisions: decisions,
          actionItems: actionItems,
        ),
      ),
    );
  }

  @override
  State<EmailDraftSheet> createState() => _EmailDraftSheetState();
}

class _EmailDraftSheetState extends State<EmailDraftSheet> {
  final _toController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  Future<void> _loadDraft() async {
    try {
      final draft = await widget.draftFuture;
      if (!mounted) return;
      setState(() {
        _toController.text = draft.suggestedTo;
        _subjectController.text = draft.subject;
        _bodyController.text = draft.body;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to generate draft: $e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _toController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final ok = await EmailDrafter.openEmailClient(
      to: _toController.text,
      subject: _subjectController.text,
      body: _bodyController.text,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open email client. Text copied to clipboard.'),
        ),
      );
      await _copy();
    }
  }

  Future<void> _copy() async {
    final full = 'Subject: ${_subjectController.text}\n\n${_bodyController.text}';
    await Clipboard.setData(ClipboardData(text: full));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Draft copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: EdgeInsets.only(top: 40, bottom: bottomInset),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppColors.lineStrong, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.mail, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontFamily: AppFonts.sans,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x, size: 18, color: AppColors.muted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                  SizedBox(height: 16),
                  Text(
                    'Drafting email with Groq...',
                    style: TextStyle(
                      fontFamily: AppFonts.sans,
                      fontSize: 13,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            )
          else ...[
            TextField(
              controller: _toController,
              style: const TextStyle(color: AppColors.ink, fontSize: 13.5),
              decoration: const InputDecoration(
                labelText: 'To (Recipient email or name)',
                labelStyle: TextStyle(color: AppColors.muted, fontSize: 13),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _subjectController,
              style: const TextStyle(color: AppColors.ink, fontSize: 13.5),
              decoration: const InputDecoration(
                labelText: 'Subject',
                labelStyle: TextStyle(color: AppColors.muted, fontSize: 13),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _bodyController,
              maxLines: 7,
              minLines: 4,
              style: const TextStyle(color: AppColors.ink, fontSize: 13.5, height: 1.4),
              decoration: const InputDecoration(
                labelText: 'Body',
                labelStyle: TextStyle(color: AppColors.muted, fontSize: 13),
                contentPadding: EdgeInsets.all(12),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _copy,
                  icon: const Icon(LucideIcons.copy, size: 14),
                  label: const Text('Copy'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    side: const BorderSide(color: AppColors.lineStrong),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _send,
                    icon: const Icon(LucideIcons.send, size: 14),
                    label: const Text('Open in Gmail / Mail'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

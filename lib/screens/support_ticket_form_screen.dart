import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_client.dart';
import '../core/retailer_service.dart';
import '../core/support_models.dart';
import '../widgets/app_widgets.dart';

/// New support ticket. Pops with `true` on success.
/// API: POST v1/retailer/support-tickets action=submit_ticket.
class SupportTicketFormScreen extends StatefulWidget {
  const SupportTicketFormScreen({super.key});

  @override
  State<SupportTicketFormScreen> createState() =>
      _SupportTicketFormScreenState();
}

class _SupportTicketFormScreenState extends State<SupportTicketFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _orderCtrl = TextEditingController();
  final _picker = ImagePicker();

  String? _type;
  Uint8List? _imageBytes;
  bool _submitting = false;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _descCtrl.dispose();
    _orderCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 70,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      setState(() => _imageBytes = bytes);
    } catch (_) {
      if (!mounted) return;
      showStatus(context, 'Could not pick image.', error: true);
    }
  }

  void _chooseSource() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pick(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pick(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      final r = await RetailerService.submitSupportTicket(
        ticketType: _type!,
        subject: _subjectCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        orderId: _orderCtrl.text.trim(),
        attachmentBase64:
            _imageBytes == null ? null : base64Encode(_imageBytes!),
      );
      if (!mounted) return;
      showStatus(
        context,
        r.ticketNumber.isEmpty
            ? 'Ticket submitted.'
            : 'Ticket ${r.ticketNumber} submitted.',
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showStatus(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('New Ticket'),
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Back',
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedChevronLeft,
            color: AppColors.text,
            strokeWidth: 1.5,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LabeledDropdown(
                      label: 'Ticket type *',
                      hint: 'Select type',
                      items: kSupportTicketTypes,
                      value: _type,
                      onChanged: (v) => setState(() => _type = v),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Select a type' : null,
                    ),
                    const SizedBox(height: 14),
                    LabeledField(
                      label: 'Order / Invoice No (optional)',
                      controller: _orderCtrl,
                      hint: 'e.g. INV-1001',
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    LabeledField(
                      label: 'Subject *',
                      controller: _subjectCtrl,
                      hint: 'Short title of the issue',
                      textInputAction: TextInputAction.next,
                      validator: requiredValidator,
                    ),
                    const SizedBox(height: 14),
                    const Text('Description *',
                        style: TextStyle(fontSize: 12, color: AppColors.text)),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _descCtrl,
                      minLines: 4,
                      maxLines: 8,
                      validator: requiredValidator,
                      style:
                          const TextStyle(fontSize: 14, color: AppColors.text),
                      decoration:
                          inputDecoration(hint: 'Explain the problem in detail'),
                    ),
                    const SizedBox(height: 14),
                    const Text('Attachment (optional)',
                        style: TextStyle(fontSize: 12, color: AppColors.text)),
                    const SizedBox(height: 6),
                    if (_imageBytes == null)
                      OutlinedButton.icon(
                        onPressed: _submitting ? null : _chooseSource,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Add photo'),
                      )
                    else
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              _imageBytes!,
                              height: 160,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.black54,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                iconSize: 18,
                                color: Colors.white,
                                tooltip: 'Remove',
                                icon: const Icon(Icons.close),
                                onPressed: _submitting
                                    ? null
                                    : () => setState(() => _imageBytes = null),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              GradientButton(
                label: 'Submit Ticket',
                loading: _submitting,
                onPressed: _submitting ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/retailer_service.dart';
import 'app_widgets.dart';

/// Tappable invoice number. Opens the invoice in the browser.
///
/// Flow (ozie-api):
///  1. GET v1/retailer/invoice-link?id=<invoice no>  (login required)
///     -> signed URL  ...route=v1/retailer/invoice_view&id=..&expires=..&token=..
///  2. launch that URL in the external browser (token = no login needed there).
///
/// If [url] (a signed `invoice_view_url` already sent by the server) is given
/// and still valid, step 1 is skipped. Expired/missing -> fetched fresh.
///
/// Drop-in for `Text(invoiceNumber, style: ..., overflow: ...)`.
class InvoiceLink extends StatefulWidget {
  final String invoiceId;
  final TextStyle? style;
  final TextOverflow? overflow;
  final int? maxLines;
  final String? url;

  /// Fallback lookup when the invoice number is not known.
  final int? orderId;

  const InvoiceLink(
    this.invoiceId, {
    super.key,
    this.style,
    this.overflow,
    this.maxLines,
    this.url,
    this.orderId,
  });

  @override
  State<InvoiceLink> createState() => _InvoiceLinkState();
}

class _InvoiceLinkState extends State<InvoiceLink> {
  static const Color _linkColor = Color(0xFF1565C0);
  bool _busy = false;

  /// Signed URLs carry `expires=<unix seconds>`. Treat < 60 s left as expired.
  bool _isUsable(String? url) {
    final u = (url ?? '').trim();
    if (u.isEmpty) return false;
    final exp = int.tryParse(Uri.tryParse(u)?.queryParameters['expires'] ?? '');
    if (exp == null) return true; // not a signed URL (e.g. website link)
    return exp * 1000 > DateTime.now().millisecondsSinceEpoch + 60000;
  }

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      var link = widget.url?.trim();
      if (!_isUsable(link)) {
        link = await RetailerService.getInvoiceLink(
          invoiceNumber: widget.invoiceId,
          orderId: widget.orderId,
        );
      }
      final ok = await launchUrl(
        Uri.parse(link!),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        showStatus(context, 'Could not open invoice.', error: true);
      }
    } on ApiException catch (e) {
      // e.g. 409 "Invoice is not generated yet..." / 404 not found
      if (mounted) showStatus(context, e.message, error: true);
    } catch (_) {
      if (mounted) showStatus(context, 'Could not open invoice.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.invoiceId.trim();
    if (id.isEmpty) {
      return Text(widget.invoiceId, style: widget.style, overflow: widget.overflow);
    }
    final linkStyle = (widget.style ?? const TextStyle()).copyWith(
      color: _linkColor,
      decoration: TextDecoration.underline,
      decorationColor: _linkColor,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _open,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(id,
                style: linkStyle, overflow: widget.overflow, maxLines: widget.maxLines),
          ),
          if (_busy) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: _linkColor),
            ),
          ],
        ],
      ),
    );
  }
}

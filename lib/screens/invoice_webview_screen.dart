import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/api_client.dart';
import '../widgets/invoice_link.dart';

/// Opens invoice_view URL inside the app with `Authorization: Bearer <token>`.
/// A plain browser cannot send this header, which is why the invoice showed
/// "unavailable" earlier.
class InvoiceWebViewScreen extends StatefulWidget {
  final String invoiceId;
  const InvoiceWebViewScreen({super.key, required this.invoiceId});

  @override
  State<InvoiceWebViewScreen> createState() => _InvoiceWebViewScreenState();
}

class _InvoiceWebViewScreenState extends State<InvoiceWebViewScreen> {
  late final WebViewController _c;
  bool _loading = true;
  String? _error;

  Map<String, String> get _headers {
    final t = ApiClient.instance.token;
    return {
      'Accept': 'text/html,application/pdf,application/json;q=0.9,*/*;q=0.8',
      'X-Requested-With': 'XMLHttpRequest',
      if (t != null && t.isNotEmpty) 'Authorization': 'Bearer $t',
    };
  }

  void _load() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _c.loadRequest(invoiceViewUri(widget.invoiceId.trim()), headers: _headers);
  }

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (e) {
          // Ignore failed sub-resources (images/fonts); only main page matters.
          if (e.isForMainFrame ?? true) {
            if (mounted) {
              setState(() {
                _loading = false;
                _error = 'Could not load invoice.';
              });
            }
          }
        },
      ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.invoiceId),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _c),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

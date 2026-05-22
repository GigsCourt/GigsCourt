import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PaymentWebViewScreen extends StatefulWidget {
  final String authorizationUrl;
  final String reference;
  final String callbackUrl;

  const PaymentWebViewScreen({
    super.key,
    required this.authorizationUrl,
    required this.reference,
    required this.callbackUrl,
  });

  @override
  State<PaymentWebViewScreen> createState() => _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends State<PaymentWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _paymentCompleted = false;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            setState(() => _isLoading = false);
            // Detect payment completion by checking for Paystack's redirect parameters
            final uri = Uri.tryParse(url);
            if (uri != null) {
              final hasReference = uri.queryParameters.containsKey('reference');
              final hasTrxref = uri.queryParameters.containsKey('trxref');
              if (hasReference || hasTrxref) {
                _paymentCompleted = true;
                Navigator.of(context).pop({'status': 'success', 'reference': widget.reference});
              }
            }
          },
          onNavigationRequest: (request) {
            // Allow Paystack URLs and the callback URL
            if (request.url.contains('paystack') ||
                request.url.contains(widget.callbackUrl)) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authorizationUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () {
            Navigator.of(context).pop({
              'status': _paymentCompleted ? 'success' : 'cancelled',
              'reference': widget.reference,
            });
          },
        ),
        title: const Text(
          'Payment',
          style: TextStyle(color: Colors.black, fontSize: 16),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

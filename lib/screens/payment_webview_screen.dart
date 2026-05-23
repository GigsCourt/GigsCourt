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
  bool _paymentFailed = false;

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
            // Inject JavaScript to detect payment result
            _checkPaymentStatus();
          },
          onNavigationRequest: (request) {
            if (request.url.contains('paystack')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authorizationUrl));
  }

  Future<void> _checkPaymentStatus() async {
    try {
      // JavaScript to detect success or failure text on the page
      final result = await _controller.runJavaScriptReturningResult(
        "document.body.innerText.includes('Payment Successful') ? 'success' : " +
        "document.body.innerText.includes('Transaction Successful') ? 'success' : " +
        "document.body.innerText.includes('Payment Failed') ? 'failed' : " +
        "document.body.innerText.includes('insufficient') ? 'failed' : 'unknown'"
      );

      // The result is a JSON string, need to parse it
      final status = result.toString().replaceAll('"', '').trim();

      if (status == 'success' && !_paymentCompleted) {
        setState(() => _paymentCompleted = true);
        // Small delay to let user see the success message briefly
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          Navigator.of(context).pop({'status': 'success', 'reference': widget.reference});
        }
      } else if (status == 'failed' && !_paymentFailed) {
        setState(() => _paymentFailed = true);
      }
    } catch (_) {
      // JavaScript execution might fail on some pages — ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        // Only show X button after payment completes or fails
        leading: (_paymentCompleted || _paymentFailed)
            ? IconButton(
                icon: const Icon(Icons.close, color: Colors.black),
                onPressed: () {
                  Navigator.of(context).pop({
                    'status': _paymentCompleted ? 'success' : 'failed',
                    'reference': widget.reference,
                  });
                },
              )
            : const SizedBox.shrink(),
        title: Text(
          _paymentCompleted
              ? 'Payment Successful'
              : _paymentFailed
                  ? 'Payment Failed'
                  : 'Payment',
          style: TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
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

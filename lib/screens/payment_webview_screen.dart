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
      final result = await _controller.runJavaScriptReturningResult(
        "document.body.innerText.includes('Payment Successful') || document.body.innerText.includes('Transaction Successful')"
      );
      
      final resultStr = result.toString().trim().toLowerCase();
      
      if (resultStr == 'true' && !_paymentCompleted) {
        setState(() => _paymentCompleted = true);
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          Navigator.of(context).pop({'status': 'success', 'reference': widget.reference});
        }
      } else if (resultStr == 'false' && !_paymentCompleted) {
        // Check for failure
        final failedResult = await _controller.runJavaScriptReturningResult(
          "document.body.innerText.includes('failed') || document.body.innerText.includes('insufficient')"
        );
        final failedStr = failedResult.toString().trim().toLowerCase();
        if (failedStr == 'true') {
          setState(() => _paymentFailed = true);
        }
      }
    } catch (_) {}
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

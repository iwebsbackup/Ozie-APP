import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'config.dart';

/// Result of one Razorpay Checkout session.
class RazorpayOutcome {
  final bool success;
  final bool cancelled;
  final String? paymentId;
  final String? orderId;
  final String? signature;
  final String? error;

  const RazorpayOutcome._({
    required this.success,
    this.cancelled = false,
    this.paymentId,
    this.orderId,
    this.signature,
    this.error,
  });

  factory RazorpayOutcome.ok(String paymentId, {String? orderId, String? signature}) =>
      RazorpayOutcome._(
        success: true,
        paymentId: paymentId,
        orderId: orderId,
        signature: signature,
      );

  factory RazorpayOutcome.failed(String message, {bool cancelled = false}) =>
      RazorpayOutcome._(success: false, cancelled: cancelled, error: message);
}

/// Thin wrapper over razorpay_flutter. Only the PUBLIC key id lives in the app.
/// The secret stays on the server (never put it in Flutter code).
class RazorpayService {
  RazorpayService._();

  /// Opens Razorpay Checkout for [amount] (rupees). Completes once, with
  /// success / failure / cancelled.
  static Future<RazorpayOutcome> pay({
    required double amount,
    required String description,
    String? contact,
    String? email,
    String? razorpayOrderId, // optional, only if backend ever creates one
    Map<String, String>? notes,
  }) {
    assert(AppConfig.razorpayIsTest,
        'Live Razorpay key in use. Only rzp_test_ keys allowed for now.');
    final completer = Completer<RazorpayOutcome>();
    final rzp = Razorpay();

    void finish(RazorpayOutcome o) {
      if (completer.isCompleted) return;
      rzp.clear();
      completer.complete(o);
    }

    rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      final id = r.paymentId ?? '';
      if (id.isEmpty) {
        finish(RazorpayOutcome.failed('Payment id missing from Razorpay.'));
      } else {
        finish(RazorpayOutcome.ok(id, orderId: r.orderId, signature: r.signature));
      }
    });

    rzp.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      final cancelled = r.code == Razorpay.PAYMENT_CANCELLED;
      finish(RazorpayOutcome.failed(
        cancelled
            ? 'Payment cancelled.'
            : (r.message?.isNotEmpty == true ? r.message! : 'Payment failed.'),
        cancelled: cancelled,
      ));
    });

    // External wallet chosen: Razorpay still sends success/error later.
    rzp.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {});

    final options = <String, dynamic>{
      'key': AppConfig.razorpayKeyId,
      'amount': (amount * 100).round(), // paise
      'currency': 'INR',
      'name': 'Ozie',
      'description': description,
      if (razorpayOrderId != null && razorpayOrderId.isNotEmpty)
        'order_id': razorpayOrderId,
      'prefill': {
        if (contact != null && contact.isNotEmpty) 'contact': contact,
        if (email != null && email.isNotEmpty) 'email': email,
      },
      if (notes != null) 'notes': notes,
      'retry': {'enabled': true, 'max_count': 2},
      'timeout': 600, // seconds
    };

    try {
      rzp.open(options);
    } catch (e) {
      finish(RazorpayOutcome.failed('Could not open payment: $e'));
    }
    return completer.future;
  }
}

import 'api_client.dart';
import 'banner_models.dart';
import 'dispatch_models.dart';
import 'finance_models.dart';
import 'invoice_models.dart';
import 'models.dart';
import 'packing_models.dart';
import 'pending_payments_models.dart';
import 'received_models.dart';
import 'reports_models.dart';
import 'returns_models.dart';
import 'support_models.dart';

class RetailerService {
  RetailerService._();

  static final ApiClient _api = ApiClient.instance;

  static ProductsCatalog? _catalogCache;
  static String? _catalogCacheKey;
  static DateTime? _catalogCacheAt;
  static Future<ProductsCatalog>? _catalogInflight;

  static Map<String, dynamic> _dataOf(Map<String, dynamic> res) {
    final data = res['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw ApiException('Unexpected server response.');
  }

  static String _catalogKey({
    required String search,
    required int categoryId,
    required String brand,
    required bool wishlistOnly,
    required int page,
    required int limit,
  }) =>
      '$search|$categoryId|$brand|$wishlistOnly|$page|$limit';

  static ProductsCatalog? cachedProducts({
    String search = '',
    int categoryId = 0,
    String brand = '',
    bool wishlistOnly = false,
    int page = 1,
    int limit = 12,
  }) {
    final key = _catalogKey(
      search: search,
      categoryId: categoryId,
      brand: brand,
      wishlistOnly: wishlistOnly,
      page: page,
      limit: limit,
    );
    if (_catalogCache == null || _catalogCacheKey != key || _catalogCacheAt == null) {
      return null;
    }
    if (DateTime.now().difference(_catalogCacheAt!) > const Duration(minutes: 2)) {
      return null;
    }
    return _catalogCache;
  }

  static Future<ProductsCatalog> getProducts({
    String search = '',
    int categoryId = 0,
    String brand = '',
    bool wishlistOnly = false,
    int page = 1,
    int limit = 12,
    bool force = false,
  }) async {
    final key = _catalogKey(
      search: search,
      categoryId: categoryId,
      brand: brand,
      wishlistOnly: wishlistOnly,
      page: page,
      limit: limit,
    );
    if (!force) {
      final cached = cachedProducts(
        search: search,
        categoryId: categoryId,
        brand: brand,
        wishlistOnly: wishlistOnly,
        page: page,
        limit: limit,
      );
      if (cached != null) return cached;
      if (_catalogInflight != null && _catalogCacheKey == key) {
        return _catalogInflight!;
      }
    }

    final query = <String, dynamic>{
      'page': page,
      'limit': limit,
    };
    if (search.isNotEmpty) query['search'] = search;
    if (categoryId > 0) query['cat'] = categoryId;
    if (brand.isNotEmpty) query['brand'] = brand;
    if (wishlistOnly) query['wishlist_only'] = 1;

    final future = () async {
      final res = await _api.get('v1/retailer/products', query: query);
      return ProductsCatalog.fromJson(_dataOf(res));
    }();

    if (page == 1) {
      _catalogCacheKey = key;
      _catalogInflight = future;
    }

    try {
      final result = await future;
      if (page == 1) {
        _catalogCache = result;
        _catalogCacheKey = key;
        _catalogCacheAt = DateTime.now();
      }
      return result;
    } finally {
      if (identical(_catalogInflight, future)) _catalogInflight = null;
    }
  }

  static Future<WishlistResult> toggleWishlist(int productId) async {
    final res = await _api.post(
      'v1/retailer/products',
      body: {
        'action': 'toggle_wishlist',
        'product_id': productId,
      },
    );
    return WishlistResult.fromJson(_dataOf(res));
  }

  static Future<AddToCartResult> addToCart(int productId, {int quantity = 1}) async {
    final res = await _api.post(
      'v1/retailer/products',
      body: {
        'action': 'add_to_cart',
        'product_id': productId,
        'quantity': quantity,
      },
    );
    return AddToCartResult.fromJson(_dataOf(res));
  }

  static Future<OrdersPage> getOrders({
    String search = '',
    String startDate = '',
    String endDate = '',
    int page = 1,
    int limit = 15,
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'limit': limit,
    };
    if (search.isNotEmpty) query['search'] = search;
    if (startDate.isNotEmpty) query['start_date'] = startDate;
    if (endDate.isNotEmpty) query['end_date'] = endDate;
    final res = await _api.get('v1/retailer/orders', query: query);
    return OrdersPage.fromJson(_dataOf(res));
  }

  static Future<ReviewOrdersData> getReviewOrders({
    int page = 1,
    int limit = 10,
  }) async {
    final res = await _api.get(
      'v1/retailer/review-orders',
      query: {'page': page, 'limit': limit},
    );
    return ReviewOrdersData.fromJson(_dataOf(res));
  }

  static Future<String> reviewAction({
    required String action,
    required int orderId,
    String? rejectReason,
    int? detailId,
  }) async {
    final body = <String, dynamic>{
      'action': action,
      'order_id': orderId,
    };
    if (rejectReason != null && rejectReason.isNotEmpty) {
      body['reject_reason'] = rejectReason;
    }
    if (detailId != null) body['detail_id'] = detailId;
    final res = await _api.post('v1/retailer/review-orders', body: body);
    return (res['message'] as String?) ?? 'Updated.';
  }

  /// POST review-orders `delete_product`. Removes one line (and its free item)
  /// from a draft order. Stock is restored by the server.
  static Future<String> deleteDraftItem({
    required int orderId,
    required int detailId,
  }) async {
    final res = await _api.post('v1/retailer/review-orders', body: {
      'action': 'delete_product',
      'order_id': orderId,
      'detail_id': detailId,
    });
    return (res['message'] as String?) ?? 'Product removed.';
  }

  /// POST review-orders `save_changes`. [quantities] = detailId -> new qty.
  /// Server caps qty to stock and re-applies schemes / free items.
  static Future<SaveChangesResult> saveDraftQuantities({
    required int orderId,
    required Map<int, int> quantities,
  }) async {
    final res = await _api.post('v1/retailer/review-orders', body: {
      'action': 'save_changes',
      'order_id': orderId,
      'items': quantities.entries
          .map((e) => {'detail_id': e.key, 'quantity': e.value})
          .toList(),
    });
    return SaveChangesResult.fromResponse(res);
  }

  /// POST review-orders `preview_item`. Read-only scheme/line calc for [quantity].
  static Future<ItemPreview> previewDraftItem({
    required int orderId,
    required int detailId,
    required int quantity,
  }) async {
    final res = await _api.post('v1/retailer/review-orders', body: {
      'action': 'preview_item',
      'order_id': orderId,
      'detail_id': detailId,
      'quantity': quantity,
    });
    return ItemPreview.fromJson(_dataOf(res));
  }

  static NotificationsPage _parseNotifications(Map<String, dynamic> res) {
    final data = res['data'];
    if (data is List) {
      final items = data
          .whereType<Map>()
          .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return NotificationsPage(
        notifications: items,
        unreadCount: items.where((n) => !n.isRead).length,
      );
    }
    if (data is Map) {
      return NotificationsPage.fromJson(Map<String, dynamic>.from(data));
    }
    if (res['notifications'] is List) {
      return NotificationsPage.fromJson(res);
    }
    throw ApiException('Unexpected server response.');
  }

  static Future<NotificationsPage> getNotifications({
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _api.get(
      'v1/retailer/notifications',
      query: {'page': page, 'limit': limit},
    );
    return _parseNotifications(res);
  }

  static Future<void> markNotificationRead(int id) async {
    try {
      await _api.post('v1/retailer/notifications', body: {
        'action': 'mark_read',
        'notification_ids': [id],
      });
    } catch (_) {}
  }

  static Future<RetailerSchemesPage> getSchemes() async {
    final res = await _api.get('v1/retailer/schemes');
    return RetailerSchemesPage.fromJson(_dataOf(res));
  }

  static RetailerCart? _cartFrom(Map<String, dynamic> res) {
    Map<String, dynamic> data;
    try {
      data = _dataOf(res);
    } on ApiException {
      data = res;
    }
    if (data['items'] is List) return RetailerCart.fromJson(data);
    final nested = data['cart'];
    if (nested is Map) {
      final map = Map<String, dynamic>.from(nested);
      if (map['items'] is List) return RetailerCart.fromJson(map);
    }
    return null;
  }

  static Future<RetailerCart> getCart() async {
    final res = await _api.get('v1/retailer/cart');
    return RetailerCart.fromJson(_dataOf(res));
  }

  static Map<String, dynamic> _cartBody({
    required String action,
    int cartId = 0,
    required int productId,
    int? quantity,
  }) {
    final body = <String, dynamic>{
      'action': action,
      'product_id': '$productId',
    };
    if (cartId > 0) {
      body['cart_id'] = '$cartId';
      body['id'] = '$cartId';
    }
    if (quantity != null) body['quantity'] = '$quantity';
    return body;
  }

  static Future<RetailerCart?> _postCart(Map<String, dynamic> body) async {
    final res = await _api.post(
      'v1/retailer/cart',
      body: body,
      query: body,
      form: true,
    );
    return _cartFrom(res);
  }

  static Future<RetailerCart?> updateCartItem({
    required int cartId,
    required int productId,
    required int quantity,
  }) {
    return _postCart(_cartBody(
      action: 'update',
      cartId: cartId,
      productId: productId,
      quantity: quantity,
    ));
  }

  static Future<RetailerCart?> removeCartItem({
    required int cartId,
    required int productId,
  }) async {
    ApiException? last;
    for (final action in const ['remove', 'delete']) {
      try {
        return await _postCart(_cartBody(
          action: action,
          cartId: cartId,
          productId: productId,
        ));
      } on ApiException catch (e) {
        last = e;
      }
    }
    if (last != null) throw last;
    return null;
  }

  /// GET v1/retailer/checkout (action=get_summary): payable amount,
  /// available credit, billing + shipping address.
  static Future<CheckoutSummary> getCheckoutSummary() async {
    final res = await _api.get(
      'v1/retailer/checkout',
      query: {'action': 'get_summary'},
    );
    return CheckoutSummary.fromJson(_dataOf(res));
  }

  /// POST v1/retailer/checkout (action=place_order).
  /// [paymentMethod]: 'Online' | 'Credit' | 'Cash on Delivery'.
  static Future<PlaceOrderResult> placeOrder({
    required String paymentMethod,
    required String shippingName,
    required String shippingCity,
  }) async {
    final res = await _api.post(
      'v1/retailer/checkout',
      body: {
        'action': 'place_order',
        'payment_method': paymentMethod,
        'shipping_name': shippingName,
        'shipping_city': shippingCity,
      },
    );
    return PlaceOrderResult.fromJson(
      _dataOf(res),
      (res['message'] as String?) ?? 'Order placed successfully.',
    );
  }

  /// GET v1/retailer/reports (sales totals, top products, offers, 30d chart).
  static Future<ReportsData> getReports() async {
    final res = await _api.get('v1/retailer/reports');
    return ReportsData.fromJson(_dataOf(res));
  }

  /// GET v1/retailer/pending-payments (unpaid / partial / requested invoices).
  static Future<PendingPaymentsPage> getPendingPayments({
    String search = '',
    String startDate = '',
    String endDate = '',
    int page = 1,
    int limit = 15,
  }) async {
    final query = <String, dynamic>{'page': page, 'limit': limit};
    if (search.isNotEmpty) query['search'] = search;
    if (startDate.isNotEmpty) query['start_date'] = startDate;
    if (endDate.isNotEmpty) query['end_date'] = endDate;
    final res = await _api.get('v1/retailer/pending-payments', query: query);
    return PendingPaymentsPage.fromJson(_dataOf(res));
  }

  /// POST v1/retailer/pending-payments (action=send_pay_request).
  /// Asks distributor/salesman to collect payment for [orderIds].
  static Future<String> requestCollection(List<int> orderIds) async {
    final res = await _api.post(
      'v1/retailer/pending-payments',
      body: {'action': 'send_pay_request', 'order_ids': orderIds},
    );
    return (res['message'] as String?) ?? 'Collection request submitted.';
  }

  /// POST v1/retailer/pending-payments (action=verify_payment).
  /// Call AFTER Razorpay success: marks [orderIds] Paid on the server.
  static Future<String> verifyOnlinePayment({
    required List<int> orderIds,
    required String razorpayPaymentId,
  }) async {
    final res = await _api.post(
      'v1/retailer/pending-payments',
      body: {
        'action': 'verify_payment',
        'order_ids': orderIds,
        'razorpay_payment_id': razorpayPaymentId,
      },
    );
    return (res['message'] as String?) ?? 'Payment successfully updated.';
  }

  /// GET v1/retailer/invoices. [status]: all | paid | pending | ...
  /// [date]: all | today | week | month.
  static Future<InvoicesPage> getInvoices({
    String search = '',
    String status = 'all',
    String date = 'all',
    int page = 1,
    int limit = 15,
  }) async {
    final query = <String, dynamic>{'page': page, 'limit': limit};
    if (search.isNotEmpty) query['search'] = search;
    if (status.isNotEmpty && status != 'all') query['status'] = status;
    if (date.isNotEmpty && date != 'all') query['date'] = date;
    final res = await _api.get('v1/retailer/invoices', query: query);
    return InvoicesPage.fromJson(_dataOf(res));
  }

  /// GET v1/retailer/invoice-view?inv=<invoice_number>.
  static Future<InvoiceDetail> getInvoiceDetail(String invoiceNumber) async {
    final res = await _api.get(
      'v1/retailer/invoice-view',
      query: {'inv': invoiceNumber},
    );
    return InvoiceDetail.fromJson(_dataOf(res));
  }

  /// GET v1/retailer/dispatch-history. [tab]: orders | schemes.
  static Future<DispatchPage> getDispatchHistory({
    String tab = 'orders',
    String search = '',
    int page = 1,
    int limit = 15,
  }) async {
    final query = <String, dynamic>{'tab': tab, 'page': page, 'limit': limit};
    if (search.isNotEmpty) query['search'] = search;
    final res = await _api.get('v1/retailer/dispatch-history', query: query);
    return DispatchPage.fromJson(_dataOf(res));
  }

  /// POST v1/retailer/dispatch-history. Marks dispatched order as received.
  /// API needs condition_accepted=true (goods received in good condition).
  static Future<String> markDispatchReceived(
    int orderId, {
    bool conditionAccepted = true,
  }) async {
    final res = await _api.post(
      'v1/retailer/dispatch-history',
      body: {'order_id': orderId, 'condition_accepted': conditionAccepted},
    );
    return (res['message'] as String?) ?? 'Order marked as received successfully.';
  }

  /// GET v1/retailer/packing-orders (approved orders under packing / packed,
  /// not yet dispatched). Read-only.
  static Future<PackingPage> getPackingOrders({
    String search = '',
    int page = 1,
    int limit = 15,
  }) async {
    final query = <String, dynamic>{'page': page, 'limit': limit};
    if (search.isNotEmpty) query['search'] = search;
    final res = await _api.get('v1/retailer/packing-orders', query: query);
    return PackingPage.fromJson(_dataOf(res));
  }

  /// GET v1/retailer/received-history (orders already marked Received).
  /// Read-only.
  static Future<ReceivedPage> getReceivedHistory({
    String search = '',
    int page = 1,
    int limit = 15,
  }) async {
    final query = <String, dynamic>{'page': page, 'limit': limit};
    if (search.isNotEmpty) query['search'] = search;
    final res = await _api.get('v1/retailer/received-history', query: query);
    return ReceivedPage.fromJson(_dataOf(res));
  }

  /// GET v1/retailer/banners (active promo banners for this retailer).
  static Future<PromoBannersResult> getBanners() async {
    final res = await _api.get('v1/retailer/banners');
    return PromoBannersResult.fromJson(_dataOf(res));
  }

  /// POST v1/retailer/banners action=add_to_cart.
  static Future<void> addBannerToCart({
    required int productId,
    int quantity = 1,
  }) async {
    await _api.post('v1/retailer/banners', body: {
      'action': 'add_to_cart',
      'product_id': productId,
      'quantity': quantity < 1 ? 1 : quantity,
    });
  }

  /// GET v1/retailer/support-tickets (own ticket history, newest first).
  static Future<SupportTicketsResult> getSupportTickets() async {
    final res = await _api.get('v1/retailer/support-tickets');
    return SupportTicketsResult.fromJson(_dataOf(res));
  }

  /// POST v1/retailer/support-tickets action=submit_ticket.
  /// [attachmentBase64] = raw base64 of a JPEG (optional).
  static Future<SupportSubmitResult> submitSupportTicket({
    required String ticketType,
    required String subject,
    required String description,
    String orderId = '',
    String? attachmentBase64,
  }) async {
    final body = <String, dynamic>{
      'action': 'submit_ticket',
      'ticket_type': ticketType,
      'subject': subject,
      'description': description,
    };
    if (orderId.isNotEmpty) body['order_id'] = orderId;
    if (attachmentBase64 != null && attachmentBase64.isNotEmpty) {
      body['attachment_base64'] = attachmentBase64;
    }
    final res = await _api.post('v1/retailer/support-tickets', body: body);
    return SupportSubmitResult.fromJson(_dataOf(res));
  }

  /// POST v1/retailer/support-tickets action=rate_ticket.
  /// [rating]: satisfied | unsatisfied.
  static Future<void> rateSupportTicket({
    required int ticketId,
    required String rating,
  }) async {
    await _api.post('v1/retailer/support-tickets', body: {
      'action': 'rate_ticket',
      'ticket_id': ticketId,
      'rating': rating,
    });
  }

  /// GET v1/retailer/returns (return history). [status]: Pending | Approved |
  /// Claimed | Rejected. [resolution]: Credit Note | Replacement.
  static Future<ReturnsPage> getReturns({
    String status = '',
    String resolution = '',
    String search = '',
    int page = 1,
    int limit = 15,
  }) async {
    final query = <String, dynamic>{'page': page, 'limit': limit};
    if (status.isNotEmpty) query['status'] = status;
    if (resolution.isNotEmpty) query['resolution'] = resolution;
    if (search.isNotEmpty) query['search'] = search;
    final res = await _api.get('v1/retailer/returns', query: query);
    return ReturnsPage.fromJson(_dataOf(res));
  }

  /// GET v1/retailer/returns?action=search_invoices&query=...
  static Future<List<ReturnInvoiceSuggestion>> searchReturnInvoices(
      String query) async {
    final res = await _api.get(
      'v1/retailer/returns',
      query: {'action': 'search_invoices', 'query': query},
    );
    final list = _dataOf(res)['invoices'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => ReturnInvoiceSuggestion.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// GET v1/retailer/returns?action=fetch_invoice&invoice_number=...
  static Future<ReturnInvoiceDetail> fetchReturnInvoice(
      String invoiceNumber) async {
    final res = await _api.get(
      'v1/retailer/returns',
      query: {'action': 'fetch_invoice', 'invoice_number': invoiceNumber},
    );
    return ReturnInvoiceDetail.fromJson(_dataOf(res));
  }

  /// POST v1/retailer/returns action=submit_return.
  /// [items] each: product_id, product_name, return_quantity, original_price.
  static Future<String> submitReturn({
    required String invoiceNumber,
    required String reason,
    required String resolutionType,
    required double creditAmount,
    required List<Map<String, dynamic>> items,
    String description = '',
  }) async {
    final res = await _api.post(
      'v1/retailer/returns',
      body: {
        'action': 'submit_return',
        'invoice_number': invoiceNumber,
        'return_reason': reason,
        'description': description,
        'resolution_type': resolutionType,
        'credit_amount': creditAmount,
        'selected_items': items,
      },
    );
    return (res['message'] as String?) ?? 'Return request submitted successfully.';
  }

  /// POST v1/retailer/returns action=claim_return (Approved returns only).
  /// Credit Note -> added to credit limit. Replacement -> items added to cart.
  static Future<ReturnClaimResult> claimReturn(int returnId) async {
    final res = await _api.post(
      'v1/retailer/returns',
      body: {'action': 'claim_return', 'return_id': returnId},
    );
    final data = res['data'] is Map
        ? Map<String, dynamic>.from(res['data'] as Map)
        : const <String, dynamic>{};
    return ReturnClaimResult(
      message: (res['message'] as String?) ?? 'Return claimed.',
      resolutionType: (data['resolution_type'] ?? '').toString(),
      goToCart: (data['next_screen'] ?? '').toString() == 'cart',
    );
  }

  /// GET v1/retailer/loan-applications (profile auto-fill, options, pending + completed).
  static Future<LoanData> getLoanApplications() async {
    final res = await _api.get('v1/retailer/loan-applications');
    return LoanData.fromJson(_dataOf(res));
  }

  /// POST v1/retailer/loan-applications. [fields] keys: bank_name, company_name,
  /// contact_person_name, entity_type, year_established, pan_number, gst_number,
  /// sales_turnover, loan_requirement, phone_number, location, city, state,
  /// pincode, registered_address.
  static Future<LoanSubmitResult> submitLoanApplication(
      Map<String, dynamic> fields) async {
    final res = await _api.post(
      'v1/retailer/loan-applications',
      body: {...fields, 'terms_acceptance': true},
    );
    return LoanSubmitResult.fromJson(_dataOf(res));
  }
}
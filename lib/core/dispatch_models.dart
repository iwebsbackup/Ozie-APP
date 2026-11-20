int _dpInt(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

double _dpDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

bool _dpBool(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';

String? _dpStr(dynamic v) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? null : s;
}

/// One row of GET v1/retailer/dispatch-history -> data.items[].
/// [type] is `order` (tab=orders) or `scheme` (tab=schemes).
class DispatchItem {
  final int orderId;
  final String type;
  final String invoiceNumber;
  final String customerName;
  final String city;
  final double totalAmount;
  final String paymentStatus;
  final int giftCount;
  final String? dispatchDate; // already formatted by API ("12 Nov 2026")
  final String dispatchStatus; // Dispatched | Received
  final bool isReceived;
  final bool canReceive;
  final String? invoicePdfUrl;
  final String? trackingInfo;

  const DispatchItem({
    required this.orderId,
    this.type = 'order',
    required this.invoiceNumber,
    this.customerName = '',
    this.city = '',
    this.totalAmount = 0,
    this.paymentStatus = '',
    this.giftCount = 0,
    this.dispatchDate,
    this.dispatchStatus = 'Dispatched',
    this.isReceived = false,
    this.canReceive = true,
    this.invoicePdfUrl,
    this.trackingInfo,
  });

  factory DispatchItem.fromJson(Map<String, dynamic> j) {
    final received = _dpBool(j['is_received']);
    return DispatchItem(
      orderId: _dpInt(j['order_id']),
      type: (j['type'] ?? 'order').toString(),
      invoiceNumber: (j['invoice_number'] ?? '').toString(),
      customerName: (j['customer_name'] ?? '').toString(),
      city: (j['city'] ?? '').toString(),
      totalAmount: _dpDouble(j['total_amount']),
      paymentStatus: (j['payment_status'] ?? '').toString(),
      giftCount: _dpInt(j['gift_count']),
      dispatchDate: _dpStr(j['dispatch_date']),
      dispatchStatus: (j['dispatch_status'] ?? (received ? 'Received' : 'Dispatched')).toString(),
      isReceived: received,
      canReceive: j.containsKey('can_receive') ? _dpBool(j['can_receive']) : !received,
      invoicePdfUrl: _dpStr(j['invoice_pdf_url']),
      trackingInfo: _dpStr(j['tracking_info']),
    );
  }

  bool get isScheme => type == 'scheme';

  DispatchItem copyAsReceived() => DispatchItem(
        orderId: orderId,
        type: type,
        invoiceNumber: invoiceNumber,
        customerName: customerName,
        city: city,
        totalAmount: totalAmount,
        paymentStatus: paymentStatus,
        giftCount: giftCount,
        dispatchDate: dispatchDate,
        dispatchStatus: 'Received',
        isReceived: true,
        canReceive: false,
        invoicePdfUrl: invoicePdfUrl,
        trackingInfo: trackingInfo,
      );
}

/// GET v1/retailer/dispatch-history -> data.
class DispatchPage {
  final String tab; // orders | schemes
  final int totalOrdersGlobal;
  final int totalSchemesGlobal;
  final int page;
  final int totalPages;
  final int totalItems;
  final bool hasNext;
  final List<DispatchItem> items;

  const DispatchPage({
    this.tab = 'orders',
    this.totalOrdersGlobal = 0,
    this.totalSchemesGlobal = 0,
    this.page = 1,
    this.totalPages = 1,
    this.totalItems = 0,
    this.hasNext = false,
    this.items = const [],
  });

  factory DispatchPage.fromJson(Map<String, dynamic> j) {
    final pg = j['pagination'] is Map
        ? Map<String, dynamic>.from(j['pagination'] as Map)
        : const <String, dynamic>{};
    final list = j['items'] is List ? j['items'] as List : const [];
    final page = _dpInt(pg['current_page']);
    final pages = _dpInt(pg['total_pages']);
    return DispatchPage(
      tab: (j['tab'] ?? 'orders').toString(),
      totalOrdersGlobal: _dpInt(j['total_orders_global']),
      totalSchemesGlobal: _dpInt(j['total_schemes_global']),
      page: page == 0 ? 1 : page,
      totalPages: pages == 0 ? 1 : pages,
      totalItems: _dpInt(pg['total_items']),
      hasNext: _dpBool(pg['has_next']),
      items: list
          .whereType<Map>()
          .map((e) => DispatchItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
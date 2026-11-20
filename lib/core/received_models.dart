int _rcInt(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

double _rcDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

String _rcStr(dynamic v) => (v ?? '').toString().trim();

/// data.orders[].tracking
class ReceivedTracking {
  final String carrier;
  final String trackingNo;
  final String warehouse;

  const ReceivedTracking({
    this.carrier = '',
    this.trackingNo = '',
    this.warehouse = '',
  });

  factory ReceivedTracking.fromJson(Map<String, dynamic> j) => ReceivedTracking(
        carrier: _rcStr(j['carrier']),
        trackingNo: _rcStr(j['tracking_no']),
        warehouse: _rcStr(j['warehouse']),
      );
}

/// One row of GET v1/retailer/received-history -> data.orders[].
class ReceivedOrder {
  final int orderId;
  final String invoiceNumber;
  final String customerName;
  final String city;
  final double totalAmount;
  final String paymentMethod;
  final String receivedDate; // already formatted by API
  final String dispatchedDate;
  final String orderDate;
  final String status;
  final ReceivedTracking tracking;
  final String invoicePdfUrl;

  const ReceivedOrder({
    required this.orderId,
    required this.invoiceNumber,
    this.customerName = '',
    this.city = '',
    this.totalAmount = 0,
    this.paymentMethod = '',
    this.receivedDate = '',
    this.dispatchedDate = '',
    this.orderDate = '',
    this.status = 'Received',
    this.tracking = const ReceivedTracking(),
    this.invoicePdfUrl = '',
  });

  factory ReceivedOrder.fromJson(Map<String, dynamic> j) => ReceivedOrder(
        orderId: _rcInt(j['order_id']),
        invoiceNumber: _rcStr(j['invoice_number']),
        customerName: _rcStr(j['customer_name']),
        city: _rcStr(j['city']),
        totalAmount: _rcDouble(j['total_amount']),
        paymentMethod: _rcStr(j['payment_method']),
        receivedDate: _rcStr(j['received_date']),
        dispatchedDate: _rcStr(j['dispatched_date']),
        orderDate: _rcStr(j['order_date']),
        status: _rcStr(j['status']).isEmpty ? 'Received' : _rcStr(j['status']),
        tracking: j['tracking'] is Map
            ? ReceivedTracking.fromJson(
                Map<String, dynamic>.from(j['tracking'] as Map))
            : const ReceivedTracking(),
        invoicePdfUrl: _rcStr(j['invoice_pdf_url']),
      );
}

/// GET v1/retailer/received-history -> data.
class ReceivedPage {
  final int totalOrders;
  final int page;
  final int totalPages;
  final List<ReceivedOrder> orders;

  const ReceivedPage({
    this.totalOrders = 0,
    this.page = 1,
    this.totalPages = 1,
    this.orders = const [],
  });

  factory ReceivedPage.fromJson(Map<String, dynamic> j) {
    final pg = j['pagination'] is Map
        ? Map<String, dynamic>.from(j['pagination'] as Map)
        : const <String, dynamic>{};
    final list = j['orders'] is List ? j['orders'] as List : const [];
    final page = _rcInt(pg['current_page']);
    final pages = _rcInt(pg['total_pages']);
    return ReceivedPage(
      totalOrders: _rcInt(j['total_received_orders']),
      page: page == 0 ? 1 : page,
      totalPages: pages == 0 ? 1 : pages,
      orders: list
          .whereType<Map>()
          .map((e) => ReceivedOrder.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

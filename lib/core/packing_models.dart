int _pkInt(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

double _pkDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

bool _pkBool(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';

String _pkStr(dynamic v) => (v ?? '').toString().trim();

/// data.orders[].shipping_details
class PackingShipping {
  final String name;
  final String address;
  final String city;
  final String state;
  final String pincode;
  final String contact;

  const PackingShipping({
    this.name = '',
    this.address = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.contact = '',
  });

  factory PackingShipping.fromJson(Map<String, dynamic> j) => PackingShipping(
        name: _pkStr(j['name']),
        address: _pkStr(j['address']),
        city: _pkStr(j['city']),
        state: _pkStr(j['state']),
        pincode: _pkStr(j['pincode']),
        contact: _pkStr(j['contact']),
      );

  /// "addr, city, state - pincode" (skips empty / N/A parts).
  String get fullAddress {
    bool ok(String s) => s.isNotEmpty && s != 'N/A';
    final parts = [address, city, state].where(ok).join(', ');
    return ok(pincode) ? (parts.isEmpty ? pincode : '$parts - $pincode') : parts;
  }

  bool get hasContact => contact.isNotEmpty && contact != 'N/A';
}

/// data.orders[].logistics
class PackingLogistics {
  final String warehouse;
  final String carrier;
  final String trackingNo;

  const PackingLogistics({
    this.warehouse = '',
    this.carrier = '',
    this.trackingNo = '',
  });

  factory PackingLogistics.fromJson(Map<String, dynamic> j) => PackingLogistics(
        warehouse: _pkStr(j['warehouse']),
        carrier: _pkStr(j['carrier']),
        trackingNo: _pkStr(j['tracking_no']),
      );
}

/// One row of GET v1/retailer/packing-orders -> data.orders[].
class PackingOrder {
  final int orderId;
  final String invoiceNumber;
  final String customerName;
  final String city;
  final double totalAmount;
  final String paymentStatus;
  final String paymentMethod;
  final bool isCod;
  final bool isPacked;
  final String packingStatus; // Under Packing | Packed & Ready
  final int progressStep; // 1 packing, 2 packed, 3 dispatched
  final String formattedDate; // already formatted by API
  final PackingShipping shipping;
  final PackingLogistics logistics;

  const PackingOrder({
    required this.orderId,
    required this.invoiceNumber,
    this.customerName = '',
    this.city = '',
    this.totalAmount = 0,
    this.paymentStatus = '',
    this.paymentMethod = '',
    this.isCod = false,
    this.isPacked = false,
    this.packingStatus = 'Under Packing',
    this.progressStep = 1,
    this.formattedDate = '',
    this.shipping = const PackingShipping(),
    this.logistics = const PackingLogistics(),
  });

  factory PackingOrder.fromJson(Map<String, dynamic> j) {
    final packed = _pkBool(j['is_packed']);
    final step = _pkInt(j['progress_step']);
    return PackingOrder(
      orderId: _pkInt(j['order_id']),
      invoiceNumber: _pkStr(j['invoice_number']),
      customerName: _pkStr(j['customer_name']),
      city: _pkStr(j['city']),
      totalAmount: _pkDouble(j['total_amount']),
      paymentStatus: _pkStr(j['payment_status']),
      paymentMethod: _pkStr(j['payment_method']),
      isCod: _pkBool(j['is_cod']),
      isPacked: packed,
      packingStatus: _pkStr(j['packing_status']).isEmpty
          ? (packed ? 'Packed & Ready' : 'Under Packing')
          : _pkStr(j['packing_status']),
      progressStep: step == 0 ? (packed ? 2 : 1) : step,
      formattedDate: _pkStr(j['formatted_date']),
      shipping: j['shipping_details'] is Map
          ? PackingShipping.fromJson(
              Map<String, dynamic>.from(j['shipping_details'] as Map))
          : const PackingShipping(),
      logistics: j['logistics'] is Map
          ? PackingLogistics.fromJson(
              Map<String, dynamic>.from(j['logistics'] as Map))
          : const PackingLogistics(),
    );
  }
}

/// GET v1/retailer/packing-orders -> data.
class PackingPage {
  final int totalOrders;
  final int page;
  final int totalPages;
  final List<PackingOrder> orders;

  const PackingPage({
    this.totalOrders = 0,
    this.page = 1,
    this.totalPages = 1,
    this.orders = const [],
  });

  factory PackingPage.fromJson(Map<String, dynamic> j) {
    final pg = j['pagination'] is Map
        ? Map<String, dynamic>.from(j['pagination'] as Map)
        : const <String, dynamic>{};
    final list = j['orders'] is List ? j['orders'] as List : const [];
    final page = _pkInt(pg['current_page']);
    final pages = _pkInt(pg['total_pages']);
    return PackingPage(
      totalOrders: _pkInt(j['total_orders']),
      page: page == 0 ? 1 : page,
      totalPages: pages == 0 ? 1 : pages,
      orders: list
          .whereType<Map>()
          .map((e) => PackingOrder.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
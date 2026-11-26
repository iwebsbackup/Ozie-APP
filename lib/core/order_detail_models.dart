/// Order Details data, parsed from one entry of GET v1/retailer/orders
/// (data.orders[i]). That entry already carries items, addresses, payment,
/// logistics, pricing and a signed invoice_view_url, so no 2nd request needed.

String? _s(dynamic v) {
  if (v == null) return null;
  final t = v.toString().trim();
  return t.isEmpty || t.toLowerCase() == 'null' ? null : t;
}

double _d(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '').trim()) ?? 0;
  return 0;
}

int _i(dynamic v) => _d(v).toInt();

Map<String, dynamic> _m(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class OrderParty {
  final String? name;
  final String? address;
  final String? city;
  final String? state;
  final String? pincode;
  final String? contact;
  final String? gst;

  const OrderParty({
    this.name,
    this.address,
    this.city,
    this.state,
    this.pincode,
    this.contact,
    this.gst,
  });

  factory OrderParty.fromJson(Map<String, dynamic> j) => OrderParty(
        name: _s(j['name']),
        address: _s(j['address']),
        city: _s(j['city']),
        state: _s(j['state']),
        pincode: _s(j['pincode']),
        contact: _s(j['contact']),
        gst: _s(j['gst']),
      );

  /// Address already contains city/state/pincode in most rows, so only add
  /// the parts that are not already inside it.
  String get fullAddress {
    final base = address ?? '';
    final extra = <String>[
      for (final p in [city, state])
        if (p != null && !base.toLowerCase().contains(p.toLowerCase())) p,
    ];
    final line = [if (base.isNotEmpty) base, ...extra].join(', ');
    if (pincode == null || line.contains(pincode!)) return line;
    return line.isEmpty ? pincode! : '$line - $pincode';
  }

  bool get isEmpty =>
      name == null && fullAddress.isEmpty && contact == null && gst == null;
}

class OrderLine {
  final int productId;
  final String name;
  final String? brand;
  final String? category;
  final String? photoUrl;
  final String? unitSize;
  final int units;
  final String? packingType;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  const OrderLine({
    required this.productId,
    required this.name,
    this.brand,
    this.category,
    this.photoUrl,
    this.unitSize,
    this.units = 0,
    this.packingType,
    this.quantity = 0,
    this.unitPrice = 0,
    this.lineTotal = 0,
  });

  factory OrderLine.fromJson(Map<String, dynamic> j) {
    final qty = _i(j['quantity'] ?? j['product_quantity']);
    final price = _d(j['unit_price'] ?? j['product_price']);
    final total = j['line_total'] ?? j['product_totalprice'];
    return OrderLine(
      productId: _i(j['product_id']),
      name: _s(j['product_name'] ?? j['name']) ?? 'Product',
      brand: _s(j['brand']),
      category: _s(j['category']),
      photoUrl: _s(j['photo_url']),
      unitSize: _s(j['unit_size']),
      units: _i(j['units']),
      packingType: _s(j['packing_type']),
      quantity: qty,
      unitPrice: price,
      lineTotal: total == null ? qty * price : _d(total),
    );
  }
}

class OrderDetailData {
  final int id;
  final String orderNumber;
  final String? poNumber;
  final String orderStatus;
  final String invoiceStatus;
  final String? invoiceNumber;
  final String? invoiceViewUrl;
  final String? invoicePdfUrl;
  final String? createdAt;
  final String? formattedDate;
  final double total;

  final OrderParty shipping;
  final OrderParty billing;
  final List<OrderLine> items;

  final String paymentMethod;
  final String paymentStatus;
  final String paymentBadge;
  final String? paymentDate;
  final String? dueDate;
  final double paidAmount;
  final double dueAmount;

  final String packingStatus;
  final String dispatchStatus;
  final String? warehouse;
  final String? carrier;
  final String? trackingNo;
  final String? eta;
  final String? dispatchedAt;
  final String? receivedAt;

  final double itemsSubtotal;
  final String? couponCode;
  final double couponDiscount;
  final int totalQuantity;

  const OrderDetailData({
    required this.id,
    required this.orderNumber,
    this.poNumber,
    this.orderStatus = '',
    this.invoiceStatus = '',
    this.invoiceNumber,
    this.invoiceViewUrl,
    this.invoicePdfUrl,
    this.createdAt,
    this.formattedDate,
    this.total = 0,
    this.shipping = const OrderParty(),
    this.billing = const OrderParty(),
    this.items = const [],
    this.paymentMethod = '',
    this.paymentStatus = '',
    this.paymentBadge = '',
    this.paymentDate,
    this.dueDate,
    this.paidAmount = 0,
    this.dueAmount = 0,
    this.packingStatus = '',
    this.dispatchStatus = '',
    this.warehouse,
    this.carrier,
    this.trackingNo,
    this.eta,
    this.dispatchedAt,
    this.receivedAt,
    this.itemsSubtotal = 0,
    this.couponCode,
    this.couponDiscount = 0,
    this.totalQuantity = 0,
  });

  factory OrderDetailData.fromJson(Map<String, dynamic> j) {
    final ship = _m(j['shipping_details']);
    final bill = _m(j['billing_details']);
    final pay = _m(j['payment_details']);
    final log = _m(j['logistics_details']);
    final price = _m(j['pricing']);
    final rawItems = j['items'] is List && (j['items'] as List).isNotEmpty
        ? j['items'] as List
        : (j['order_items'] is List ? j['order_items'] as List : const []);

    return OrderDetailData(
      id: _i(j['id'] ?? j['order_id']),
      orderNumber: _s(j['order_number']) ?? 'ORD-${_i(j['id'])}',
      poNumber: _s(j['po_number']),
      orderStatus: _s(j['order_status']) ?? '',
      invoiceStatus: _s(j['invoice_status']) ?? '',
      invoiceNumber: _s(j['invoice_number']),
      invoiceViewUrl: _s(j['invoice_view_url']),
      invoicePdfUrl: _s(j['invoice_pdf_url']),
      createdAt: _s(j['created_at']),
      formattedDate: _s(j['formatted_date']),
      total: _d(j['total']),
      shipping: OrderParty.fromJson({
        'name': ship['name'] ?? j['shipping_name'],
        'address': ship['address'] ?? j['shipping_address'],
        'city': ship['city'] ?? j['shipping_city'],
        'state': ship['state'] ?? j['shipping_state'],
        'pincode': ship['pincode'] ?? j['shipping_pincode'],
        'contact': ship['contact'] ?? j['shipping_contact'],
      }),
      billing: OrderParty.fromJson({
        'address': bill['address'] ?? j['bill_address'],
        'city': bill['city'] ?? j['bill_city'],
        'state': bill['state'] ?? j['bill_state'],
        'pincode': bill['pincode'] ?? j['bill_pincode'],
        'contact': bill['contact'] ?? j['bill_contactnumber'],
        'gst': bill['gst'] ?? j['bill_gst'],
      }),
      items: rawItems
          .whereType<Map>()
          .map((e) => OrderLine.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      paymentMethod: _s(pay['method'] ?? j['payment_method']) ?? '',
      paymentStatus: _s(pay['status'] ?? j['payment_status']) ?? '',
      paymentBadge:
          _s(pay['badge'] ?? j['payment_badge'] ?? j['payment_status']) ?? '',
      paymentDate: _s(pay['payment_date'] ?? j['payment_date']),
      dueDate: _s(pay['due_date'] ?? j['due_date']),
      paidAmount: _d(pay['paid_amount']),
      dueAmount: _d(pay['due_amount']),
      packingStatus: _s(log['packing_status'] ?? j['packing_status']) ?? '',
      dispatchStatus: _s(log['dispatch_status'] ?? j['dispatch_status']) ?? '',
      warehouse: _s(log['warehouse'] ?? j['warehouse']),
      carrier: _s(log['carrier'] ?? j['carrier']),
      trackingNo: _s(log['tracking_number'] ?? j['tracking_no']),
      eta: _s(log['eta'] ?? j['eta']),
      dispatchedAt: _s(log['dispatched_at'] ?? j['dispatched_at']),
      receivedAt: _s(log['received_at'] ?? j['received_at']),
      itemsSubtotal: _d(price['items_subtotal'] ?? j['items_subtotal']),
      couponCode: _s(price['coupon_code'] ?? j['coupon_code']),
      couponDiscount: _d(price['coupon_discount'] ?? j['coupon_discount']),
      totalQuantity: _i(price['total_quantity'] ?? j['total_quantity']),
    );
  }

  bool get isPaid => paymentStatus.toLowerCase() == 'paid';
  bool get hasItems => items.isNotEmpty;
}

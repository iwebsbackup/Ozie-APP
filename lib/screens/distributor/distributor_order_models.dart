/// Models for distributor order APIs:
///   v1/distributor/pending-orders
///   v1/distributor/order-tracking
///   v1/distributor/order-detail

double _d(dynamic v) => v == null ? 0 : (double.tryParse('$v') ?? 0);
int _i(dynamic v) => v == null ? 0 : (int.tryParse('$v') ?? 0);
String _s(dynamic v) => v == null ? '' : v.toString();
String? _sn(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

Map<String, dynamic> _m(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class PageInfo {
  final int currentPage;
  final int totalPages;
  final int totalItems;
  final bool hasNext;
  const PageInfo({
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
    required this.hasNext,
  });

  factory PageInfo.fromJson(Map<String, dynamic> j) => PageInfo(
        currentPage: _i(j['current_page']),
        totalPages: _i(j['total_pages']),
        totalItems: _i(j['total_items']),
        hasNext: j['has_next'] == true,
      );
}

// ───────────────────────── Pending POs ─────────────────────────

class PendingPo {
  final int poId;
  final String poNumber;
  final String status;
  final double totalAmount;
  final int itemCount;
  final String retailerName;
  final String retailerMobile;
  final String retailerCity;
  final String formattedDate;
  final int orderId;
  final int retailerId;

  const PendingPo({
    required this.poId,
    required this.poNumber,
    required this.status,
    required this.totalAmount,
    required this.itemCount,
    required this.retailerName,
    required this.retailerMobile,
    required this.retailerCity,
    required this.formattedDate,
    required this.orderId,
    required this.retailerId,
  });

  factory PendingPo.fromJson(Map<String, dynamic> j) => PendingPo(
        poId: _i(j['po_id']),
        poNumber: _s(j['po_number']),
        status: _s(j['status']),
        totalAmount: _d(j['total_amount']),
        itemCount: _i(j['item_count']),
        retailerName: _s(j['retailer_name']),
        retailerMobile: _s(j['retailer_mobile']),
        retailerCity: _s(j['retailer_city']),
        formattedDate: _s(j['formatted_date']),
        orderId: _i(j['order_id']),
        retailerId: _i(j['retailer_id']),
      );
}

class PendingPoPage {
  final int totalPending;
  final PageInfo page;
  final List<PendingPo> orders;
  const PendingPoPage({
    required this.totalPending,
    required this.page,
    required this.orders,
  });

  factory PendingPoPage.fromJson(Map<String, dynamic> j) => PendingPoPage(
        totalPending: _i(_m(j['summary'])['total_pending']),
        page: PageInfo.fromJson(_m(j['pagination'])),
        orders: (j['orders'] as List? ?? [])
            .map((e) => PendingPo.fromJson(_m(e)))
            .toList(),
      );
}

class PoActionResult {
  final int poId;
  final String poNumber;
  final String newStatus; // approved | rejected
  const PoActionResult({
    required this.poId,
    required this.poNumber,
    required this.newStatus,
  });

  factory PoActionResult.fromJson(Map<String, dynamic> j) => PoActionResult(
        poId: _i(j['po_id']),
        poNumber: _s(j['po_number']),
        newStatus: _s(j['new_status']),
      );
}

// ───────────────────────── Order tracking ─────────────────────────

class TrackedOrder {
  final int orderId;
  final String invoiceNumber;
  final String retailerName;
  final String? salesmanName;
  final String city;
  final double totalAmount;
  final String invoiceStatus;
  final String? dispatchStatus;
  final String paymentStatus;
  final String paymentLabel;

  /// success | primary | warning
  final String paymentColor;

  /// 1 Pending, 2 Processing, 3 Dispatched, 4 Delivered
  final int stageStep;
  final String stageLabel;
  final String? invoicePdfUrl;
  final String? paymentMethod;
  final String orderDate;
  final String? dispatchDate;

  const TrackedOrder({
    required this.orderId,
    required this.invoiceNumber,
    required this.retailerName,
    required this.salesmanName,
    required this.city,
    required this.totalAmount,
    required this.invoiceStatus,
    required this.dispatchStatus,
    required this.paymentStatus,
    required this.paymentLabel,
    required this.paymentColor,
    required this.stageStep,
    required this.stageLabel,
    required this.invoicePdfUrl,
    required this.paymentMethod,
    required this.orderDate,
    required this.dispatchDate,
  });

  factory TrackedOrder.fromJson(Map<String, dynamic> j) {
    final badge = _m(j['payment_badge']);
    final stage = _m(j['tracking_stage']);
    return TrackedOrder(
      orderId: _i(j['order_id']),
      invoiceNumber: _s(j['invoice_number']),
      retailerName: _s(j['retailer_name']),
      salesmanName: _sn(j['salesman_name']),
      city: _s(j['city']),
      totalAmount: _d(j['total_amount']),
      invoiceStatus: _s(j['invoice_status']),
      dispatchStatus: _sn(j['dispatch_status']),
      paymentStatus: _s(j['payment_status']),
      paymentLabel: _s(badge['label']).isEmpty ? 'Pending' : _s(badge['label']),
      paymentColor: _s(badge['color']),
      stageStep: _i(stage['step']) == 0 ? 1 : _i(stage['step']),
      stageLabel: _s(stage['label']),
      invoicePdfUrl: _sn(j['invoice_pdf_url']),
      paymentMethod: _sn(j['payment_method']),
      orderDate: _s(j['order_date']),
      dispatchDate: _sn(j['dispatch_date']),
    );
  }
}

class TrackingPage {
  final int approved;
  final int dispatched;
  final int all;
  final PageInfo page;
  final List<TrackedOrder> orders;
  const TrackingPage({
    required this.approved,
    required this.dispatched,
    required this.all,
    required this.page,
    required this.orders,
  });

  factory TrackingPage.fromJson(Map<String, dynamic> j) {
    final c = _m(j['counts']);
    return TrackingPage(
      approved: _i(c['approved']),
      dispatched: _i(c['dispatched']),
      all: _i(c['all']),
      page: PageInfo.fromJson(_m(j['pagination'])),
      orders: (j['orders'] as List? ?? [])
          .map((e) => TrackedOrder.fromJson(_m(e)))
          .toList(),
    );
  }
}

// ───────────────────────── Order detail ─────────────────────────

class OrderLine {
  final String name;
  final int quantity;
  final double unitPrice;
  final double subtotal;
  final String unit;
  final String hsn;
  final double gstPercent;
  final String? image;
  const OrderLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
    required this.unit,
    required this.hsn,
    required this.gstPercent,
    required this.image,
  });

  factory OrderLine.fromJson(Map<String, dynamic> j) => OrderLine(
        name: _s(j['product_name']),
        quantity: _i(j['quantity']),
        unitPrice: _d(j['unit_price']),
        subtotal: _d(j['subtotal']),
        unit: _s(j['unit']),
        hsn: _s(j['hsn_code']),
        gstPercent: _d(j['gst_percent']),
        image: _sn(j['product_image']),
      );
}

class TimelineStep {
  final int step;
  final String label;
  final bool done;
  final String? date;
  const TimelineStep({
    required this.step,
    required this.label,
    required this.done,
    required this.date,
  });

  factory TimelineStep.fromJson(Map<String, dynamic> j) => TimelineStep(
        step: _i(j['step']),
        label: _s(j['label']),
        done: j['done'] == true,
        date: _sn(j['date']),
      );
}

class PartyInfo {
  final String? name;
  final String? mobile;
  final String? city;
  final String? address;
  final String? state;
  final String? pincode;
  const PartyInfo({
    this.name,
    this.mobile,
    this.city,
    this.address,
    this.state,
    this.pincode,
  });

  factory PartyInfo.fromJson(Map<String, dynamic> j) => PartyInfo(
        name: _sn(j['name']),
        mobile: _sn(j['mobile']),
        city: _sn(j['city']),
        address: _sn(j['address']),
        state: _sn(j['state']),
        pincode: _sn(j['pincode']),
      );

  bool get isEmpty =>
      name == null &&
      mobile == null &&
      city == null &&
      address == null &&
      state == null &&
      pincode == null;

  /// "12, MG Road, Pune, Maharashtra - 411001"
  String get fullAddress {
    final parts = <String>[
      if (address != null) address!,
      if (city != null && city != 'N/A') city!,
      if (state != null) state!,
    ];
    final base = parts.join(', ');
    if (pincode == null) return base;
    return base.isEmpty ? pincode! : '$base - $pincode';
  }
}

/// One model for both `type=retailer` (invoice order) and `type=po`.
class OrderDetail {
  final bool isPo;
  final int id;

  /// invoice number (retailer type) or PO number (po type)
  final String number;

  /// po type: pending | approved | rejected. retailer type: dispatch status.
  final String status;
  final String orderDate;
  final String? notes;

  final PartyInfo retailer;
  final PartyInfo salesman;
  final PartyInfo shipping;
  final List<OrderLine> items;

  // money
  final double subtotal;
  final double discount;
  final double gst;
  final double total;

  // invoice (retailer type)
  final String? invoiceStatus;
  final String? paymentStatus;
  final String? paymentMethod;
  final String? dueDate;
  final String? invoiceDate;
  final String? pdfUrl;

  // tracking (retailer type)
  final String? dispatchStatus;
  final String? dispatchedAt;
  final String? receivedAt;
  final String? trackingNumber;
  final List<TimelineStep> timeline;

  const OrderDetail({
    required this.isPo,
    required this.id,
    required this.number,
    required this.status,
    required this.orderDate,
    required this.notes,
    required this.retailer,
    required this.salesman,
    required this.shipping,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.gst,
    required this.total,
    this.invoiceStatus,
    this.paymentStatus,
    this.paymentMethod,
    this.dueDate,
    this.invoiceDate,
    this.pdfUrl,
    this.dispatchStatus,
    this.dispatchedAt,
    this.receivedAt,
    this.trackingNumber,
    this.timeline = const [],
  });

  bool get isPendingPo => isPo && status == 'pending';

  factory OrderDetail.fromJson(Map<String, dynamic> j) {
    final isPo = _s(j['type']) == 'po';
    final items = (j['items'] as List? ?? [])
        .map((e) => OrderLine.fromJson(_m(e)))
        .toList();

    if (isPo) {
      final sum = items.fold<double>(0, (a, b) => a + b.subtotal);
      final total = _d(j['total_amount']);
      return OrderDetail(
        isPo: true,
        id: _i(j['po_id']),
        number: _s(j['po_number']),
        status: _s(j['po_status']),
        orderDate: _s(j['formatted_date']),
        notes: _sn(j['notes']),
        retailer: PartyInfo.fromJson(_m(j['retailer'])),
        salesman: const PartyInfo(),
        shipping: const PartyInfo(),
        items: items,
        subtotal: sum,
        discount: 0,
        gst: 0,
        total: total == 0 ? sum : total,
      );
    }

    final inv = _m(j['invoice']);
    final fin = _m(j['financials']);
    final trk = _m(j['tracking']);
    final id = _i(j['order_id']);
    return OrderDetail(
      isPo: false,
      id: id,
      number: _sn(inv['invoice_number']) ?? 'ORD-$id',
      status: _s(trk['dispatch_status']),
      orderDate: _s(j['order_date']),
      notes: _sn(j['notes']),
      retailer: PartyInfo.fromJson(_m(j['retailer'])),
      salesman: PartyInfo.fromJson(_m(j['salesman'])),
      shipping: PartyInfo.fromJson(_m(j['shipping'])),
      items: items,
      subtotal: _d(fin['subtotal']),
      discount: _d(fin['discount']),
      gst: _d(fin['gst_amount']),
      total: _d(fin['total_amount']),
      invoiceStatus: _sn(inv['invoice_status']),
      paymentStatus: _sn(inv['payment_status']),
      paymentMethod: _sn(inv['payment_method']),
      dueDate: _sn(inv['due_date']),
      invoiceDate: _sn(inv['invoice_date']),
      pdfUrl: _sn(inv['pdf_url']),
      dispatchStatus: _sn(trk['dispatch_status']),
      dispatchedAt: _sn(trk['dispatched_at']),
      receivedAt: _sn(trk['received_at']),
      trackingNumber: _sn(trk['tracking_number']),
      timeline: (trk['timeline'] as List? ?? [])
          .map((e) => TimelineStep.fromJson(_m(e)))
          .toList(),
    );
  }
}
double _invDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

int _invInt(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

String? _invStr(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

Map<String, dynamic> _invMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// One row of GET v1/retailer/invoices -> data.invoices[].
class InvoiceListItem {
  final int id;
  final String invoiceNumber;
  final String customerName;
  final double subtotal;
  final String paymentStatus;
  final String? paymentMethod;
  final String? createdAt;
  final String? pdfUrl;

  const InvoiceListItem({
    required this.id,
    required this.invoiceNumber,
    required this.customerName,
    required this.subtotal,
    required this.paymentStatus,
    this.paymentMethod,
    this.createdAt,
    this.pdfUrl,
  });

  factory InvoiceListItem.fromJson(Map<String, dynamic> j) => InvoiceListItem(
        id: _invInt(j['id']),
        invoiceNumber: (j['invoice_number'] ?? '').toString(),
        customerName: (j['customer_name'] ?? '').toString(),
        subtotal: _invDouble(j['subtotal']),
        paymentStatus: (j['payment_status'] ?? '').toString(),
        paymentMethod: _invStr(j['payment_method']),
        createdAt: _invStr(j['created_at']),
        pdfUrl: _invStr(j['pdf_url']),
      );
}

/// GET v1/retailer/invoices -> data.
class InvoicesPage {
  final int page;
  final int totalPages;
  final int totalItems;
  final List<InvoiceListItem> invoices;

  const InvoicesPage({
    this.page = 1,
    this.totalPages = 1,
    this.totalItems = 0,
    this.invoices = const [],
  });

  factory InvoicesPage.fromJson(Map<String, dynamic> j) {
    final pg = _invMap(j['pagination']);
    final list = j['invoices'] is List ? j['invoices'] as List : const [];
    final page = _invInt(pg['page']);
    final pages = _invInt(pg['total_pages']);
    return InvoicesPage(
      page: page == 0 ? 1 : page,
      totalPages: pages == 0 ? 1 : pages,
      totalItems: _invInt(pg['total_items']),
      invoices: list
          .whereType<Map>()
          .map((e) => InvoiceListItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// billing / shipping block of GET v1/retailer/invoice-view.
class InvoiceAddress {
  final String? name;
  final String? contact;
  final String? address;
  final String? city;
  final String? state;
  final String? pincode;
  final String? gstin;

  const InvoiceAddress({
    this.name,
    this.contact,
    this.address,
    this.city,
    this.state,
    this.pincode,
    this.gstin,
  });

  factory InvoiceAddress.fromJson(Map<String, dynamic> j) => InvoiceAddress(
        name: _invStr(j['name']),
        contact: _invStr(j['contact']),
        address: _invStr(j['address']),
        city: _invStr(j['city']),
        state: _invStr(j['state']),
        pincode: _invStr(j['pincode']),
        gstin: _invStr(j['gstin']),
      );

  /// "addr, city, state - pincode"
  String get fullAddress {
    final parts = <String>[
      if (address != null) address!,
      if (city != null) city!,
      if (state != null) state!,
    ];
    final line = parts.join(', ');
    if (pincode == null) return line;
    return line.isEmpty ? pincode! : '$line - $pincode';
  }

  bool get isEmpty =>
      name == null && contact == null && fullAddress.isEmpty && gstin == null;
}

class InvoiceLine {
  final int productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double originalPrice;
  final double totalAmount;
  final bool isSpecial;
  final double specialSaving;
  final bool isReturn;
  final List<String> schemes;

  const InvoiceLine({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.originalPrice,
    required this.totalAmount,
    this.isSpecial = false,
    this.specialSaving = 0,
    this.isReturn = false,
    this.schemes = const [],
  });

  factory InvoiceLine.fromJson(Map<String, dynamic> j) => InvoiceLine(
        productId: _invInt(j['product_id']),
        productName: (j['product_name'] ?? '').toString(),
        quantity: _invInt(j['quantity']),
        unitPrice: _invDouble(j['unit_price']),
        originalPrice: _invDouble(j['original_price']),
        totalAmount: _invDouble(j['total_amount']),
        isSpecial: j['is_special'] == true || j['is_special'] == 1,
        specialSaving: _invDouble(j['special_saving']),
        isReturn: j['is_return'] == true || j['is_return'] == 1,
        schemes: j['schemes'] is List
            ? (j['schemes'] as List).map((e) => e.toString()).toList()
            : const [],
      );
}

class InvoiceSummary {
  final double grossTotal;
  final double specialDiscount;
  final double schemeDiscount;
  final double freeValue;
  final double returnCredit;
  final double totalSavings;
  final double netPayable;

  const InvoiceSummary({
    this.grossTotal = 0,
    this.specialDiscount = 0,
    this.schemeDiscount = 0,
    this.freeValue = 0,
    this.returnCredit = 0,
    this.totalSavings = 0,
    this.netPayable = 0,
  });

  factory InvoiceSummary.fromJson(Map<String, dynamic> j) => InvoiceSummary(
        grossTotal: _invDouble(j['gross_total']),
        specialDiscount: _invDouble(j['special_discount']),
        schemeDiscount: _invDouble(j['scheme_discount']),
        freeValue: _invDouble(j['free_value']),
        returnCredit: _invDouble(j['return_credit']),
        totalSavings: _invDouble(j['total_savings']),
        netPayable: _invDouble(j['net_payable']),
      );
}

/// GET v1/retailer/invoice-view?inv=... -> data.
class InvoiceDetail {
  final String invoiceNumber;
  final String? invoiceDate;
  final String? dueDate;
  final String paymentStatus;
  final String? paymentMethod;
  final InvoiceAddress billing;
  final InvoiceAddress shipping;
  final List<InvoiceLine> items;
  final InvoiceSummary summary;
  final String? pdfUrl;

  const InvoiceDetail({
    required this.invoiceNumber,
    this.invoiceDate,
    this.dueDate,
    required this.paymentStatus,
    this.paymentMethod,
    required this.billing,
    required this.shipping,
    required this.items,
    required this.summary,
    this.pdfUrl,
  });

  factory InvoiceDetail.fromJson(Map<String, dynamic> j) => InvoiceDetail(
        invoiceNumber: (j['invoice_number'] ?? '').toString(),
        invoiceDate: _invStr(j['invoice_date']),
        dueDate: _invStr(j['due_date']),
        paymentStatus: (j['payment_status'] ?? '').toString(),
        paymentMethod: _invStr(j['payment_method']),
        billing: InvoiceAddress.fromJson(_invMap(j['billing'])),
        shipping: InvoiceAddress.fromJson(_invMap(j['shipping'])),
        items: j['items'] is List
            ? (j['items'] as List)
                .whereType<Map>()
                .map((e) => InvoiceLine.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : const [],
        summary: InvoiceSummary.fromJson(_invMap(j['summary'])),
        pdfUrl: _invStr(j['pdf_url']),
      );
}

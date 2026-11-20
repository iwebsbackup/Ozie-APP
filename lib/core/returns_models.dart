int _rtInt(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

double _rtDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

bool _rtBool(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';

String _rtStr(dynamic v) => (v ?? '').toString().trim();

/// data.returns[].items[] (what was sent in selected_items).
class ReturnLine {
  final String productName;
  final int quantity;
  final double price;

  const ReturnLine({this.productName = '', this.quantity = 0, this.price = 0});

  factory ReturnLine.fromJson(Map<String, dynamic> j) => ReturnLine(
        productName: _rtStr(j['product_name']),
        quantity: _rtInt(j['return_quantity'] ?? j['quantity']),
        price: _rtDouble(j['original_price'] ?? j['price']),
      );
}

/// One row of GET v1/retailer/returns -> data.returns[].
class ReturnRecord {
  final int id;
  final String invoiceNumber;
  final String reason;
  final String description;
  final String resolutionType; // Credit Note | Replacement
  final double creditAmount;
  final String status; // Pending | Approved | Claimed | Rejected...
  final String claimStatus;
  final bool isClaimable;
  final String formattedDate;
  final List<ReturnLine> items;

  const ReturnRecord({
    required this.id,
    this.invoiceNumber = '',
    this.reason = '',
    this.description = '',
    this.resolutionType = 'Credit Note',
    this.creditAmount = 0,
    this.status = 'Pending',
    this.claimStatus = '',
    this.isClaimable = false,
    this.formattedDate = '',
    this.items = const [],
  });

  bool get isReplacement => resolutionType.toLowerCase() == 'replacement';
  bool get isRejected => status.toLowerCase().startsWith('rejected');

  factory ReturnRecord.fromJson(Map<String, dynamic> j) {
    final raw = j['items'] is List ? j['items'] as List : const [];
    final status = _rtStr(j['status']);
    return ReturnRecord(
      id: _rtInt(j['id']),
      invoiceNumber: _rtStr(j['invoice_number']),
      reason: _rtStr(j['reason']),
      description: _rtStr(j['description']),
      resolutionType: _rtStr(j['resolution_type']).isEmpty
          ? 'Credit Note'
          : _rtStr(j['resolution_type']),
      creditAmount: _rtDouble(j['credit_amount']),
      status: status.isEmpty ? 'Pending' : status,
      claimStatus: _rtStr(j['claim_status']),
      isClaimable: j.containsKey('is_claimable')
          ? _rtBool(j['is_claimable'])
          : status.toLowerCase() == 'approved',
      formattedDate: _rtStr(j['formatted_date']),
      items: raw
          .whereType<Map>()
          .map((e) => ReturnLine.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// GET v1/retailer/returns -> data.
class ReturnsPage {
  final int totalReturns;
  final int page;
  final int totalPages;
  final List<ReturnRecord> returns;

  const ReturnsPage({
    this.totalReturns = 0,
    this.page = 1,
    this.totalPages = 1,
    this.returns = const [],
  });

  factory ReturnsPage.fromJson(Map<String, dynamic> j) {
    final pg = j['pagination'] is Map
        ? Map<String, dynamic>.from(j['pagination'] as Map)
        : const <String, dynamic>{};
    final list = j['returns'] is List ? j['returns'] as List : const [];
    final page = _rtInt(pg['current_page']);
    final pages = _rtInt(pg['total_pages']);
    return ReturnsPage(
      totalReturns: _rtInt(j['total_returns']),
      page: page == 0 ? 1 : page,
      totalPages: pages == 0 ? 1 : pages,
      returns: list
          .whereType<Map>()
          .map((e) => ReturnRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// GET v1/retailer/returns?action=search_invoices -> data.invoices[].
class ReturnInvoiceSuggestion {
  final String invoiceNumber;
  final String invoiceDate;
  final double subtotal;
  final String paymentStatus;

  const ReturnInvoiceSuggestion({
    required this.invoiceNumber,
    this.invoiceDate = '',
    this.subtotal = 0,
    this.paymentStatus = '',
  });

  factory ReturnInvoiceSuggestion.fromJson(Map<String, dynamic> j) =>
      ReturnInvoiceSuggestion(
        invoiceNumber: _rtStr(j['invoice_number']),
        invoiceDate: _rtStr(j['invoice_date']),
        subtotal: _rtDouble(j['subtotal']),
        paymentStatus: _rtStr(j['payment_status']),
      );
}

/// GET ...?action=fetch_invoice -> data.items[].
class ReturnInvoiceItem {
  final int detailId;
  final int productId;
  final String productName;
  final int casesOrdered;
  final int unitsPerCase;
  final int totalBottles;
  final double casePrice;
  final double bottlePrice;

  const ReturnInvoiceItem({
    this.detailId = 0,
    this.productId = 0,
    this.productName = '',
    this.casesOrdered = 0,
    this.unitsPerCase = 1,
    this.totalBottles = 0,
    this.casePrice = 0,
    this.bottlePrice = 0,
  });

  factory ReturnInvoiceItem.fromJson(Map<String, dynamic> j) =>
      ReturnInvoiceItem(
        detailId: _rtInt(j['detail_id']),
        productId: _rtInt(j['product_id']),
        productName: _rtStr(j['product_name']),
        casesOrdered: _rtInt(j['cases_ordered']),
        unitsPerCase: _rtInt(j['units_per_case']) == 0 ? 1 : _rtInt(j['units_per_case']),
        totalBottles: _rtInt(j['total_bottles']),
        casePrice: _rtDouble(j['case_price']),
        bottlePrice: _rtDouble(j['bottle_price']),
      );
}

class ReturnInvoiceDetail {
  final String invoiceNumber;
  final String invoiceDate;
  final double subtotal;
  final List<ReturnInvoiceItem> items;

  const ReturnInvoiceDetail({
    required this.invoiceNumber,
    this.invoiceDate = '',
    this.subtotal = 0,
    this.items = const [],
  });

  factory ReturnInvoiceDetail.fromJson(Map<String, dynamic> j) {
    final list = j['items'] is List ? j['items'] as List : const [];
    return ReturnInvoiceDetail(
      invoiceNumber: _rtStr(j['invoice_number']),
      invoiceDate: _rtStr(j['invoice_date']),
      subtotal: _rtDouble(j['subtotal']),
      items: list
          .whereType<Map>()
          .map((e) => ReturnInvoiceItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// POST claim_return result.
class ReturnClaimResult {
  final String message;
  final String resolutionType;
  final bool goToCart;

  const ReturnClaimResult({
    this.message = '',
    this.resolutionType = '',
    this.goToCart = false,
  });
}

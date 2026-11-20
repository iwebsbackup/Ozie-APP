double _ppDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

int _ppInt(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

/// One row of GET v1/retailer/pending-payments -> data.invoices[].
class PendingInvoice {
  final int id;
  final String invoiceNumber;
  final double total;
  final double paid;
  final double due;
  final String? dueDate;
  final bool isOverdue;
  final String status;

  const PendingInvoice({
    required this.id,
    required this.invoiceNumber,
    required this.total,
    required this.paid,
    required this.due,
    this.dueDate,
    this.isOverdue = false,
    this.status = 'Pending',
  });

  factory PendingInvoice.fromJson(Map<String, dynamic> j) => PendingInvoice(
        id: _ppInt(j['id']),
        invoiceNumber: (j['invoice_number'] ?? '').toString(),
        total: _ppDouble(j['total']),
        paid: _ppDouble(j['paid_amount']),
        due: _ppDouble(j['due_amount']),
        dueDate: j['due_date']?.toString(),
        isOverdue: j['is_overdue'] == true || j['is_overdue'] == 1,
        status: (j['payment_status'] ?? 'Pending').toString(),
      );

  /// Collection already requested -> cannot request again.
  bool get isRequested => status.toLowerCase() == 'requested';

  bool get isPartial => paid > 0 && due > 0;
}

/// GET v1/retailer/pending-payments -> data.
class PendingPaymentsPage {
  final double totalAmount;
  final int totalCount;
  final int page;
  final int totalPages;
  final List<PendingInvoice> invoices;

  const PendingPaymentsPage({
    this.totalAmount = 0,
    this.totalCount = 0,
    this.page = 1,
    this.totalPages = 1,
    this.invoices = const [],
  });

  factory PendingPaymentsPage.fromJson(Map<String, dynamic> j) {
    final summary = j['summary'] is Map
        ? Map<String, dynamic>.from(j['summary'] as Map)
        : const <String, dynamic>{};
    final pg = j['pagination'] is Map
        ? Map<String, dynamic>.from(j['pagination'] as Map)
        : const <String, dynamic>{};
    final list = j['invoices'] is List ? j['invoices'] as List : const [];
    return PendingPaymentsPage(
      totalAmount: _ppDouble(summary['total_pending_amount']),
      totalCount: _ppInt(summary['total_pending_count']),
      page: _ppInt(pg['page']) == 0 ? 1 : _ppInt(pg['page']),
      totalPages: _ppInt(pg['total_pages']) == 0 ? 1 : _ppInt(pg['total_pages']),
      invoices: list
          .whereType<Map>()
          .map((e) => PendingInvoice.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

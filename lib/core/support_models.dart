/// Support tickets (retailer).
/// API: GET/POST v1/retailer/support-tickets.

String _stStr(dynamic v) => v == null ? '' : '$v'.trim();

int _stInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

/// Ticket type options (API takes free text `ticket_type`).
const List<String> kSupportTicketTypes = [
  'Order Issue',
  'Payment Issue',
  'Delivery Issue',
  'Product Issue',
  'Return / Refund',
  'Account / Profile',
  'App Problem',
  'Other',
];

class SupportTicket {
  final int id;
  final String ticketNumber;
  final String ticketType;
  final String subject;
  final String description;
  final String status;
  final String satisfactionRating; // '' | satisfied | unsatisfied
  final String solutionComment;
  final String solvedBy;
  final String solvedAt;
  final String attachmentUrl;
  final String solutionDocUrl;
  final String createdAt;

  const SupportTicket({
    this.id = 0,
    this.ticketNumber = '',
    this.ticketType = '',
    this.subject = '',
    this.description = '',
    this.status = '',
    this.satisfactionRating = '',
    this.solutionComment = '',
    this.solvedBy = '',
    this.solvedAt = '',
    this.attachmentUrl = '',
    this.solutionDocUrl = '',
    this.createdAt = '',
  });

  factory SupportTicket.fromJson(Map<String, dynamic> j) => SupportTicket(
        id: _stInt(j['id']),
        ticketNumber: _stStr(j['ticket_number']),
        ticketType: _stStr(j['ticket_type']),
        subject: _stStr(j['subject']),
        description: _stStr(j['description']),
        status: _stStr(j['status']),
        satisfactionRating: _stStr(j['satisfaction_rating']).toLowerCase(),
        solutionComment: _stStr(j['solution_comment']),
        solvedBy: _stStr(j['solved_by']),
        solvedAt: _stStr(j['solved_at']),
        attachmentUrl: _stStr(j['attachment_url']),
        solutionDocUrl: _stStr(j['solution_doc_url']),
        createdAt: _stStr(j['created_at']),
      );

  String get _s => status.toLowerCase();

  bool get isOpen => _s == 'open' || _s == 'pending' || _s.isEmpty;
  bool get isSolved =>
      _s == 'solved' || _s == 'resolved' || _s == 'closed' || _s == 'completed';
  bool get isInProgress => !isOpen && !isSolved;

  bool get hasRating => satisfactionRating.isNotEmpty;

  /// Rating only makes sense once the ticket is solved and not rated yet.
  bool get canRate => isSolved && !hasRating;

  SupportTicket copyWithRating(String rating) => SupportTicket(
        id: id,
        ticketNumber: ticketNumber,
        ticketType: ticketType,
        subject: subject,
        description: description,
        status: status,
        satisfactionRating: rating,
        solutionComment: solutionComment,
        solvedBy: solvedBy,
        solvedAt: solvedAt,
        attachmentUrl: attachmentUrl,
        solutionDocUrl: solutionDocUrl,
        createdAt: createdAt,
      );
}

/// GET v1/retailer/support-tickets -> data.
class SupportTicketsResult {
  final List<SupportTicket> tickets;
  const SupportTicketsResult({this.tickets = const []});

  factory SupportTicketsResult.fromJson(Map<String, dynamic> j) {
    final list = j['tickets'] is List ? j['tickets'] as List : const [];
    return SupportTicketsResult(
      tickets: list
          .whereType<Map>()
          .map((e) => SupportTicket.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// POST action=submit_ticket -> data.
class SupportSubmitResult {
  final String ticketNumber;
  final String status;
  const SupportSubmitResult({this.ticketNumber = '', this.status = 'Open'});

  factory SupportSubmitResult.fromJson(Map<String, dynamic> j) =>
      SupportSubmitResult(
        ticketNumber: _stStr(j['ticket_number']),
        status: _stStr(j['status']),
      );
}
int _fnInt(dynamic v) {
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

double _fnDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

bool _fnBool(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';

String _fnStr(dynamic v) => (v ?? '').toString().trim();

List<String> _fnStrList(dynamic v) =>
    v is List ? v.map((e) => _fnStr(e)).where((e) => e.isNotEmpty).toList() : const [];

/// data.profile of GET v1/retailer/loan-applications (form auto-fill).
class LoanProfile {
  final String companyName;
  final String contactPerson;
  final String email;
  final String phoneNumber;
  final String entityType;
  final String yearEstablished;
  final String panNumber;
  final String gstNumber;
  final String location;
  final String city;
  final String state;
  final String pincode;
  final String address;
  final bool isProfileComplete;

  const LoanProfile({
    this.companyName = '',
    this.contactPerson = '',
    this.email = '',
    this.phoneNumber = '',
    this.entityType = '',
    this.yearEstablished = '',
    this.panNumber = '',
    this.gstNumber = '',
    this.location = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.address = '',
    this.isProfileComplete = false,
  });

  factory LoanProfile.fromJson(Map<String, dynamic> j) => LoanProfile(
        companyName: _fnStr(j['company_name']),
        contactPerson: _fnStr(j['contact_person']),
        email: _fnStr(j['email']),
        phoneNumber: _fnStr(j['phone_number']),
        entityType: _fnStr(j['entity_type']),
        yearEstablished: _fnStr(j['year_established']),
        panNumber: _fnStr(j['pan_number']),
        gstNumber: _fnStr(j['gst_number']),
        location: _fnStr(j['location']),
        city: _fnStr(j['city']),
        state: _fnStr(j['state']),
        pincode: _fnStr(j['pincode']),
        address: _fnStr(j['address']),
        isProfileComplete: _fnBool(j['is_profile_complete']),
      );
}

class LoanBank {
  final String name;
  final String label;
  final String subtitle;

  const LoanBank({required this.name, this.label = '', this.subtitle = ''});

  factory LoanBank.fromJson(Map<String, dynamic> j) => LoanBank(
        name: _fnStr(j['name']),
        label: _fnStr(j['label']),
        subtitle: _fnStr(j['subtitle']),
      );
}

/// data.options (dropdown values for the application form).
class LoanOptions {
  final List<LoanBank> banks;
  final List<String> entityTypes;
  final List<String> salesTurnoverRanges;
  final List<String> loanRequirements;

  const LoanOptions({
    this.banks = const [],
    this.entityTypes = const [],
    this.salesTurnoverRanges = const [],
    this.loanRequirements = const [],
  });

  factory LoanOptions.fromJson(Map<String, dynamic> j) => LoanOptions(
        banks: (j['banks'] is List ? j['banks'] as List : const [])
            .whereType<Map>()
            .map((e) => LoanBank.fromJson(Map<String, dynamic>.from(e)))
            .where((b) => b.name.isNotEmpty)
            .toList(),
        entityTypes: _fnStrList(j['entity_types']),
        salesTurnoverRanges: _fnStrList(j['sales_turnover_ranges']),
        loanRequirements: _fnStrList(j['loan_requirements']),
      );
}

/// One pending / completed application.
class LoanApplication {
  final int id;
  final String applicationNumber;
  final String bankName;
  final String companyName;
  final String contactPersonName;
  final String loanRequirement;
  final double approvedAmount;
  final String remarks;
  final String status;
  final String formattedDate;

  const LoanApplication({
    required this.id,
    this.applicationNumber = '',
    this.bankName = '',
    this.companyName = '',
    this.contactPersonName = '',
    this.loanRequirement = '',
    this.approvedAmount = 0,
    this.remarks = '',
    this.status = 'Pending',
    this.formattedDate = '',
  });

  bool get isPending => status.toLowerCase() == 'pending';
  bool get isRejected {
    final s = status.toLowerCase();
    return s.startsWith('reject') || s.startsWith('declin');
  }

  factory LoanApplication.fromJson(Map<String, dynamic> j) => LoanApplication(
        id: _fnInt(j['id']),
        applicationNumber: _fnStr(j['application_number']),
        bankName: _fnStr(j['bank_name']),
        companyName: _fnStr(j['company_name']),
        contactPersonName: _fnStr(j['contact_person_name']),
        loanRequirement: _fnStr(j['loan_requirement']),
        approvedAmount: _fnDouble(j['approved_amount']),
        remarks: _fnStr(j['remarks']),
        status: _fnStr(j['status']).isEmpty ? 'Pending' : _fnStr(j['status']),
        formattedDate: _fnStr(j['formatted_date']),
      );
}

/// GET v1/retailer/loan-applications -> data.
class LoanData {
  final LoanProfile profile;
  final LoanOptions options;
  final List<LoanApplication> pending;
  final List<LoanApplication> completed;

  const LoanData({
    required this.profile,
    required this.options,
    this.pending = const [],
    this.completed = const [],
  });

  static List<LoanApplication> _apps(dynamic v) => (v is List ? v : const [])
      .whereType<Map>()
      .map((e) => LoanApplication.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  factory LoanData.fromJson(Map<String, dynamic> j) => LoanData(
        profile: LoanProfile.fromJson(
            j['profile'] is Map ? Map<String, dynamic>.from(j['profile'] as Map) : const {}),
        options: LoanOptions.fromJson(
            j['options'] is Map ? Map<String, dynamic>.from(j['options'] as Map) : const {}),
        pending: _apps(j['pending_loans']),
        completed: _apps(j['completed_loans']),
      );
}

/// POST v1/retailer/loan-applications -> data.
class LoanSubmitResult {
  final String applicationNumber;
  final String title;
  final String body;

  const LoanSubmitResult({this.applicationNumber = '', this.title = '', this.body = ''});

  factory LoanSubmitResult.fromJson(Map<String, dynamic> j) => LoanSubmitResult(
        applicationNumber: _fnStr(j['application_number']),
        title: _fnStr(j['message_title']),
        body: _fnStr(j['message_body']),
      );
}
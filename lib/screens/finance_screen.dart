import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/api_client.dart';
import '../core/constants.dart';
import '../core/finance_models.dart';
import '../core/retailer_service.dart';
import '../widgets/app_widgets.dart';

/// Ozie Finance: bank loan applications (pending / completed) + apply.
/// API: GET/POST v1/retailer/loan-applications.
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen>
    with SingleTickerProviderStateMixin {
  static const Color _header = Color(0xFFBE185D); // top header (change here)

  late final TabController _tabs;
  LoanData? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final d = await RetailerService.getLoanApplications();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _apply() async {
    final d = _data;
    if (d == null) return;
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => LoanApplicationFormScreen(profile: d.profile, options: d.options),
      ),
    );
    if (done == true && mounted) {
      _tabs.animateTo(0);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      backgroundColor: _header,
      appBar: AppBar(
        title: const Text('Ozie Finance'),
        backgroundColor: _header,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: IconButton(
          tooltip: 'Back',
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedChevronLeft,
            color: Colors.white,
            strokeWidth: 1.5,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          dividerColor: Colors.transparent,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: [
            Tab(text: 'Pending (${d?.pending.length ?? 0})'),
            Tab(text: 'Completed (${d?.completed.length ?? 0})'),
          ],
        ),
      ),
      floatingActionButton: d == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _apply,
              backgroundColor: _header,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Apply for Loan'),
            ),
      body: Column(
        children: [
          if (d != null) _heroStrip(d),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              clipBehavior: Clip.antiAlias,
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroStrip(LoanData d) {
    final approved = d.completed
        .where((a) => !a.isRejected)
        .fold<double>(0, (s, a) => s + a.approvedAmount);
    Widget stat(String k, String v) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(k, style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
              const SizedBox(height: 2),
              Text(
                v,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Row(
        children: [
          stat('Applications', '${d.pending.length + d.completed.length}'),
          stat('Under review', '${d.pending.length}'),
          stat('Approved amount', formatInr(approved, decimals: false)),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40, color: AppColors.muted),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.dangerText),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final d = _data!;
    return TabBarView(
      controller: _tabs,
      children: [
        _list(d.pending, pending: true),
        _list(d.completed, pending: false),
      ],
    );
  }

  Widget _list(List<LoanApplication> items, {required bool pending}) {
    return RefreshIndicator(
      onRefresh: _load,
      child: items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 90, 24, 24),
              children: [
                Container(
                  width: 84,
                  height: 84,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _header.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.account_balance_outlined, size: 40, color: _header),
                ),
                const SizedBox(height: 16),
                Text(
                  pending ? 'No applications under review' : 'No completed applications',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  pending
                      ? 'Tap "Apply for Loan" to send a bank loan request.'
                      : 'Approved and rejected applications appear here.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 96),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _card(items[i]),
            ),
    );
  }

  ({Color bg, Color fg}) _statusColors(LoanApplication a) {
    if (a.isPending) return (bg: const Color(0xFFFFF1D6), fg: const Color(0xFF8A5A00));
    if (a.isRejected) return (bg: AppColors.dangerBg, fg: AppColors.dangerText);
    return (bg: AppColors.successBg, fg: AppColors.successText);
  }

  Widget _kv(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: AppColors.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          ],
        ),
      );

  Widget _card(LoanApplication a) {
    final c = _statusColors(a);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x0F1E2A3B), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _header.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(Icons.account_balance_outlined, color: _header, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.bankName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            a.applicationNumber,
                            style: const TextStyle(fontSize: 12, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.bg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        a.status,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.fg),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (a.companyName.isNotEmpty) _kv(Icons.storefront_outlined, a.companyName),
                if (a.contactPersonName.isNotEmpty && a.contactPersonName != 'N/A')
                  _kv(Icons.person_outline_rounded, a.contactPersonName),
                if (a.formattedDate.isNotEmpty) _kv(Icons.event_outlined, a.formattedDate),
                if (a.remarks.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.inputBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      a.remarks,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.text),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: const BoxDecoration(
              color: Color(0xFFFDF2F8),
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Requested',
                          style: TextStyle(fontSize: 11, color: AppColors.muted)),
                      const SizedBox(height: 2),
                      Text(
                        a.loanRequirement.isEmpty ? '-' : a.loanRequirement,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!a.isPending && !a.isRejected && a.approvedAmount > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Approved',
                          style: TextStyle(fontSize: 11, color: AppColors.muted)),
                      const SizedBox(height: 2),
                      Text(
                        formatInr(a.approvedAmount),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.successText,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bank loan application form. Pops with `true` on success.
/// Auto-filled from [LoanProfile]. API: POST v1/retailer/loan-applications.
class LoanApplicationFormScreen extends StatefulWidget {
  final LoanProfile profile;
  final LoanOptions options;

  const LoanApplicationFormScreen({
    super.key,
    required this.profile,
    required this.options,
  });

  @override
  State<LoanApplicationFormScreen> createState() => _LoanApplicationFormScreenState();
}

class _LoanApplicationFormScreenState extends State<LoanApplicationFormScreen> {
  static const Color _header = Color(0xFFBE185D);

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _company;
  late final TextEditingController _contact;
  late final TextEditingController _phone;
  late final TextEditingController _year;
  late final TextEditingController _pan;
  late final TextEditingController _gst;
  late final TextEditingController _location;
  late final TextEditingController _city;
  late final TextEditingController _pincode;
  late final TextEditingController _address;

  String? _bank;
  String? _entity;
  String? _turnover;
  String? _requirement;
  String? _state;
  bool _terms = false;
  bool _termsError = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _company = TextEditingController(text: p.companyName);
    _contact = TextEditingController(text: p.contactPerson);
    _phone = TextEditingController(text: p.phoneNumber);
    _year = TextEditingController(text: p.yearEstablished);
    _pan = TextEditingController(text: p.panNumber);
    _gst = TextEditingController(text: p.gstNumber);
    _location = TextEditingController(text: p.location);
    _city = TextEditingController(text: p.city);
    _pincode = TextEditingController(text: p.pincode);
    _address = TextEditingController(text: p.address);
    final o = widget.options;
    _entity = o.entityTypes.contains(p.entityType) ? p.entityType : null;
    _state = kIndianStates.contains(p.state) ? p.state : null;
    if (o.banks.length == 1) _bank = o.banks.first.name;
  }

  @override
  void dispose() {
    for (final c in [
      _company, _contact, _phone, _year, _pan, _gst, _location, _city, _pincode, _address,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _req(String? v) => requiredValidator(v);

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final valid = _formKey.currentState?.validate() ?? false;
    if (_bank == null) {
      showStatus(context, 'Please select a preferred bank.', error: true);
      return;
    }
    setState(() => _termsError = !_terms);
    if (!valid || !_terms) return;

    setState(() => _submitting = true);
    try {
      final r = await RetailerService.submitLoanApplication({
        'bank_name': _bank,
        'company_name': _company.text.trim(),
        'contact_person_name': _contact.text.trim(),
        'entity_type': _entity,
        'year_established': int.tryParse(_year.text.trim()) ?? 0,
        'pan_number': _pan.text.trim().toUpperCase(),
        'gst_number': _gst.text.trim().toUpperCase(),
        'sales_turnover': _turnover,
        'loan_requirement': _requirement,
        'phone_number': _phone.text.trim(),
        'location': _location.text.trim(),
        'city': _city.text.trim(),
        'state': _state,
        'pincode': _pincode.text.trim(),
        'registered_address': _address.text.trim(),
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded, size: 52, color: AppColors.green),
          title: Text(r.title.isEmpty ? 'Form Submitted Successfully' : r.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (r.applicationNumber.isNotEmpty)
                Text(
                  r.applicationNumber,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _header,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                r.body.isEmpty
                    ? 'Your application is currently under review.'
                    : r.body,
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _header),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showStatus(context, e.message, error: true);
    }
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _header.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 18, color: _header),
              ),
              const SizedBox(width: 10),
              Flexible(child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _gap() => const SizedBox(height: 14);

  Widget _bankTile(LoanBank b) {
    final sel = _bank == b.name;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _submitting ? null : () => setState(() => _bank = b.name),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: sel ? _header.withValues(alpha: 0.06) : AppColors.inputBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? _header : AppColors.border, width: sel ? 1.6 : 1),
        ),
        child: Row(
          children: [
            Icon(Icons.account_balance_outlined, color: sel ? _header : AppColors.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    b.label.isEmpty ? b.name : b.label,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  if (b.subtitle.isNotEmpty)
                    Text(b.subtitle,
                        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
            Icon(
              sel ? Icons.radio_button_checked : Icons.radio_button_off,
              color: sel ? _header : AppColors.muted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.options;
    return Scaffold(
      backgroundColor: _header,
      appBar: AppBar(
        title: const Text('Apply for Loan'),
        backgroundColor: _header,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: IconButton(
          tooltip: 'Back',
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedChevronLeft,
            color: Colors.white,
            strokeWidth: 1.5,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 2, 20, 18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Details are filled from your profile. Check and complete the rest.',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                  children: [
                    _section('Preferred bank', Icons.account_balance_outlined, [
                      if (o.banks.isEmpty)
                        const Text('No bank available right now.',
                            style: TextStyle(fontSize: 13, color: AppColors.muted))
                      else
                        for (final b in o.banks) _bankTile(b),
                    ]),
                    const SizedBox(height: 16),
                    _section('Business details', Icons.storefront_outlined, [
                      LabeledField(
                        label: 'Company legal name *',
                        controller: _company,
                        textInputAction: TextInputAction.next,
                        validator: _req,
                      ),
                      _gap(),
                      LabeledField(
                        label: 'Contact person *',
                        controller: _contact,
                        textInputAction: TextInputAction.next,
                        validator: _req,
                      ),
                      _gap(),
                      LabeledDropdown(
                        label: 'Entity type *',
                        hint: 'Select entity type',
                        items: o.entityTypes,
                        value: _entity,
                        onChanged: (v) => setState(() => _entity = v),
                        validator: (v) => (v == null || v.isEmpty) ? 'Select entity type' : null,
                      ),
                      _gap(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: LabeledField(
                              label: 'Year established *',
                              controller: _year,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                              validator: (v) {
                                final y = int.tryParse((v ?? '').trim());
                                if (y == null || y < 1900 || y > DateTime.now().year) {
                                  return 'Enter valid year';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: LabeledField(
                              label: 'Phone *',
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              validator: _req,
                            ),
                          ),
                        ],
                      ),
                      _gap(),
                      LabeledField(
                        label: 'PAN number *',
                        controller: _pan,
                        textInputAction: TextInputAction.next,
                        validator: _req,
                      ),
                      _gap(),
                      LabeledField(
                        label: 'GST number (optional)',
                        controller: _gst,
                        textInputAction: TextInputAction.next,
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _section('Address', Icons.place_outlined, [
                      LabeledField(
                        label: 'Registered address *',
                        controller: _address,
                        textInputAction: TextInputAction.next,
                        validator: _req,
                      ),
                      _gap(),
                      LabeledField(
                        label: 'Business location / area *',
                        controller: _location,
                        textInputAction: TextInputAction.next,
                        validator: _req,
                      ),
                      _gap(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: LabeledField(
                              label: 'City *',
                              controller: _city,
                              textInputAction: TextInputAction.next,
                              validator: _req,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: LabeledField(
                              label: 'Pincode *',
                              controller: _pincode,
                              keyboardType: TextInputType.number,
                              validator: (v) => RegExp(r'^[0-9]{6}$').hasMatch((v ?? '').trim())
                                  ? null
                                  : '6 digits',
                            ),
                          ),
                        ],
                      ),
                      _gap(),
                      LabeledDropdown(
                        label: 'State *',
                        hint: 'Select state',
                        items: kIndianStates,
                        value: _state,
                        onChanged: (v) => setState(() => _state = v),
                        validator: (v) => (v == null || v.isEmpty) ? 'Select state' : null,
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _section('Financials', Icons.payments_outlined, [
                      LabeledDropdown(
                        label: 'Sales turnover *',
                        hint: 'Select range',
                        items: o.salesTurnoverRanges,
                        value: _turnover,
                        onChanged: (v) => setState(() => _turnover = v),
                        validator: (v) => (v == null || v.isEmpty) ? 'Select turnover' : null,
                      ),
                      _gap(),
                      LabeledDropdown(
                        label: 'Loan requirement *',
                        hint: 'Select amount',
                        items: o.loanRequirements,
                        value: _requirement,
                        onChanged: (v) => setState(() => _requirement = v),
                        validator: (v) => (v == null || v.isEmpty) ? 'Select amount' : null,
                      ),
                    ]),
                    const SizedBox(height: 16),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _submitting
                          ? null
                          : () => setState(() {
                                _terms = !_terms;
                                _termsError = false;
                              }),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _termsError ? AppColors.dangerText : AppColors.border,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: _terms,
                              activeColor: _header,
                              visualDensity: VisualDensity.compact,
                              onChanged: _submitting
                                  ? null
                                  : (v) => setState(() {
                                        _terms = v ?? false;
                                        _termsError = false;
                                      }),
                            ),
                            const Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'I authorize Ozie to share these details with the selected bank for loan processing.',
                                  style: TextStyle(fontSize: 13, color: AppColors.text),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_termsError)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 6, 0, 0),
                        child: Text(
                          'Accept the terms to continue.',
                          style: TextStyle(fontSize: 12, color: AppColors.dangerText),
                        ),
                      ),
                    const SizedBox(height: 20),
                    GradientButton(
                      label: 'Submit Application',
                      loading: _submitting,
                      onPressed: _submitting ? null : _submit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
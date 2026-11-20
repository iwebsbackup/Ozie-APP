import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/profile_service.dart';
import '../core/constants.dart';
import '../core/router.dart';
import '../widgets/app_widgets.dart';
import 'change_password_screen.dart';

/// My Account: shows GET v1/profile/get and edits via v1/profile/update.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  ProfileData? _profile;
  String? _error;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;

  final _nameCtrl = TextEditingController();
  final _shopCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _shopCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _pincodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await ProfileService.get();
      if (!mounted) return;
      setState(() {
        _profile = p;
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

  void _startEdit() {
    final p = _profile;
    if (p == null) return;
    _nameCtrl.text = p.name ?? '';
    _shopCtrl.text = p.retailer?.shopName ?? '';
    _addressCtrl.text = p.retailer?.address ?? '';
    _cityCtrl.text = p.retailer?.city ?? '';
    _stateCtrl.text = p.retailer?.state ?? '';
    _pincodeCtrl.text = p.retailer?.pincode ?? '';
    setState(() => _editing = true);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.length < 2) {
      showStatus(context, 'Please enter your full name (2-100 characters).', error: true);
      return;
    }
    final hasRetailer = _profile?.retailer != null;
    final pincode = _pincodeCtrl.text.trim();
    if (hasRetailer && pincode.isNotEmpty && !RegExp(r'^[0-9]{6}$').hasMatch(pincode)) {
      showStatus(context, 'Pincode must be 6 digits.', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final p = await ProfileService.update(
        name: name,
        shopName: hasRetailer ? _shopCtrl.text.trim() : null,
        address: hasRetailer ? _addressCtrl.text.trim() : null,
        city: hasRetailer ? _cityCtrl.text.trim() : null,
        state: hasRetailer ? _stateCtrl.text.trim() : null,
        pincode: hasRetailer ? pincode : null,
      );
      if (!mounted) return;
      setState(() {
        _profile = p;
        _editing = false;
      });
      showStatus(context, 'Profile updated successfully.');
    } on ApiException catch (e) {
      if (!mounted) return;
      showStatus(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _roleLabel(String? t) {
    if (t == null || t.isEmpty) return 'No role yet';
    return t
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String _money(double v) => '₹${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Account'),
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        actions: [
          if (_profile != null && !_editing)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _startEdit,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.dangerText)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final p = _profile!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _header(p),
        const SizedBox(height: 20),
        if (_editing) ...[
          _editForm(p),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => setState(() => _editing = false),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GradientButton(
                  label: 'Save',
                  loading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ] else ...[
          if (p.retailer != null) ...[
            _creditCard(p.retailer!),
            const SizedBox(height: 16),
          ],
          _card('Account', Icons.person_outline_rounded, AppColors.blue, [
            _row(Icons.badge_outlined, 'Name', p.name ?? '-'),
            _row(Icons.mail_outline_rounded, 'Email', p.email ?? '-', copy: p.email != null),
            _row(Icons.phone_outlined, 'Mobile', p.mobile ?? '-', copy: p.mobile != null),
            _row(Icons.work_outline_rounded, 'Role', _roleLabel(p.userType)),
            if (p.memberSince != null)
              _row(Icons.event_outlined, 'Member since', p.memberSince!, last: true),
          ]),
          if (p.retailer != null) ...[
            const SizedBox(height: 16),
            _card('Shop', Icons.storefront_outlined, const Color(0xFF0D9488), [
              _row(Icons.store_mall_directory_outlined, 'Shop name', p.retailer!.shopName ?? '-'),
              _row(Icons.qr_code_2_rounded, 'Retailer code', p.retailer!.retailerCode ?? '-',
                  copy: p.retailer!.retailerCode != null),
              _row(Icons.place_outlined, 'Address', p.retailer!.address ?? '-'),
              _row(Icons.location_city_outlined, 'City', p.retailer!.city ?? '-'),
              _row(Icons.map_outlined, 'State', p.retailer!.state ?? '-'),
              _row(Icons.pin_drop_outlined, 'Pincode', p.retailer!.pincode ?? '-'),
              _row(Icons.receipt_long_outlined, 'GST', p.retailer!.gst ?? '-',
                  copy: p.retailer!.gst != null),
              _row(Icons.credit_card_outlined, 'PAN', p.retailer!.pan ?? '-',
                  copy: p.retailer!.pan != null),
              _row(Icons.verified_outlined, 'Status', p.retailer!.status ?? '-',
                  chip: p.retailer!.status != null, last: true),
            ]),
          ],
          if (p.license != null) ...[
            const SizedBox(height: 16),
            _card('License', Icons.assignment_ind_outlined, const Color(0xFF7C3AED), [
              _row(Icons.person_outline_rounded, 'Holder name', p.license!.holderName ?? '-'),
              _row(Icons.phone_outlined, 'Holder contact', p.license!.holderContact ?? '-'),
              _row(Icons.place_outlined, 'Holder address', p.license!.holderAddress ?? '-'),
              _row(Icons.engineering_outlined, 'Operator name', p.license!.operatorName ?? '-'),
              _row(Icons.phone_outlined, 'Operator contact', p.license!.operatorContact ?? '-',
                  last: true),
            ]),
          ],
        ],
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _actionTile(
                Icons.lock_outline_rounded,
                'Change Password',
                AppColors.blue,
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ChangePasswordScreen()),
                ),
              ),
              const Divider(height: 1, indent: 68, endIndent: 14, color: AppColors.border),
              _actionTile(
                Icons.logout,
                'Logout',
                const Color(0xFFDC3545),
                () => logoutAndGoToLogin(context),
                danger: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _actionTile(IconData icon, String label, Color tint, VoidCallback onTap,
      {bool danger = false}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: tint, size: 22),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w500,
          color: danger ? tint : AppColors.text,
        ),
      ),
      trailing: danger
          ? null
          : const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 24),
      onTap: onTap,
    );
  }

  Widget _pill(String text, {required Color bg, required Color fg, IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(text, style: TextStyle(fontSize: 11.5, color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _header(ProfileData p) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.green, AppColors.blue],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: CircleAvatar(
              radius: 40,
              backgroundColor: const Color(0xFFDCE9FA),
              child: Text(
                _initials(p.displayName),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.blue,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            p.displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          if (p.email != null && p.email!.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(p.email!, style: const TextStyle(fontSize: 13, color: Colors.white70)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _pill(_roleLabel(p.userType),
                  bg: Colors.white.withValues(alpha: 0.22), fg: Colors.white),
              if (p.isVerified == true)
                _pill('Verified',
                    bg: Colors.white, fg: AppColors.successText, icon: Icons.verified_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _creditCard(RetailerProfile r) {
    final limit = r.creditLimit;
    final used = r.currentBalance;
    final frac = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    final barColor = frac > 0.85
        ? const Color(0xFFDC3545)
        : frac > 0.6
            ? const Color(0xFFF59E0B)
            : AppColors.green;
    Widget stat(String k, String v) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(k, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              const SizedBox(height: 2),
              Text(
                v,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Available credit', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
          const SizedBox(height: 4),
          Text(
            _money(r.availableCredit),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 8,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              stat('Credit limit', _money(limit)),
              stat('Used', _money(used)),
              stat('Credit days', '${r.creditDays}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _editForm(ProfileData p) {
    final hasRetailer = p.retailer != null;
    final stateVal = kIndianStates.contains(_stateCtrl.text) ? _stateCtrl.text : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card('Personal', Icons.person_outline_rounded, AppColors.blue, [
          const SizedBox(height: 4),
          LabeledField(
            label: 'Full Name',
            controller: _nameCtrl,
            hint: 'Enter your full name',
            textInputAction: TextInputAction.next,
          ),
        ]),
        const SizedBox(height: 16),
        if (hasRetailer)
          _card('Shop details', Icons.storefront_outlined, const Color(0xFF0D9488), [
            const SizedBox(height: 4),
            LabeledField(
              label: 'Shop Name',
              controller: _shopCtrl,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: 'Address',
              controller: _addressCtrl,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LabeledField(
                    label: 'City',
                    controller: _cityCtrl,
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LabeledField(
                    label: 'Pincode',
                    controller: _pincodeCtrl,
                    hint: '6 digits',
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LabeledDropdown(
              label: 'State',
              hint: _stateCtrl.text.isEmpty ? 'Select state' : _stateCtrl.text,
              items: kIndianStates,
              value: stateVal,
              onChanged: (v) => setState(() => _stateCtrl.text = v ?? ''),
            ),
          ])
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: AppColors.blue),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Shop and address details are created after your onboarding is approved.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.text),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _card(String title, IconData icon, Color tint, List<Widget> rows) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
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
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 18, color: tint),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }

  Widget _row(IconData icon, String k, String v,
      {bool copy = false, bool chip = false, bool last = false}) {
    final value = chip
        ? Align(
            alignment: Alignment.centerLeft,
            child: _pill(
              v,
              bg: v.toLowerCase() == 'active' ? AppColors.successBg : const Color(0xFFEEF0F4),
              fg: v.toLowerCase() == 'active' ? AppColors.successText : AppColors.muted,
            ),
          )
        : Text(
            v,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              color: AppColors.text,
            ),
          );
    return Builder(
      builder: (context) => InkWell(
        onLongPress: copy
            ? () {
                Clipboard.setData(ClipboardData(text: v));
                showStatus(context, '$k copied.');
              }
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: last ? null : const Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: AppColors.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(k, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                    const SizedBox(height: 2),
                    value,
                  ],
                ),
              ),
              if (copy) const Icon(Icons.copy_rounded, size: 15, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
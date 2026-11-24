import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/auth_service.dart';
import '../core/models.dart';
import '../core/router.dart';
import '../core/test_mode.dart';
import '../widgets/app_widgets.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';
import 'test/delivery_boy_test_view.dart';
import 'test/test_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _idCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _dNameCtrl = TextEditingController();
  final _dMobileCtrl = TextEditingController();

  bool _obscure = true;
  bool _agree = true;
  bool _loading = false;
  bool _googleLoading = false;

  // Test mode: retailer | distributor | delivery
  bool _testOn = TestMode.enabled.value;
  String _role = 'retailer';

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwCtrl.dispose();
    _dNameCtrl.dispose();
    _dMobileCtrl.dispose();
    super.dispose();
  }

  bool _tncOk() {
    if (!_agree) {
      showStatus(
        context,
        'Please accept the Terms & Conditions and Privacy Policy.',
        error: true,
      );
      return false;
    }
    return true;
  }

  Future<void> _setTest(bool v) async {
    setState(() {
      _testOn = v;
      _role = 'retailer';
    });
    await TestMode.set(v);
  }

  /// Test mode: only retailer / distributor accounts may enter, and the
  /// account must match the role picked on the login page.
  Future<bool> _testAllowed(Session s, {bool anyRole = false}) async {
    if (!_testOn) return true;
    final type = (s.user.userType ?? '').toLowerCase();
    String? msg;
    if (!TestMode.mainRoles.contains(type)) {
      msg = 'Test mode: only retailer, distributor & delivery boy can login.';
    } else if (!anyRole && type != _role) {
      msg = 'This is a $type account. Select "$type" above.';
    }
    if (msg == null) return true;
    await AuthService.logout();
    if (mounted) showStatus(context, msg, error: true);
    return false;
  }

  Future<void> _login() async {
    if (_testOn && _role == 'delivery') return _deliveryLogin();
    if (!_formKey.currentState!.validate() || !_tncOk()) return;
    setState(() => _loading = true);
    try {
      final session = await AuthService.login(
        _idCtrl.text.trim(),
        _pwCtrl.text.trim(),
      );
      if (!mounted) return;
      if (!await _testAllowed(session)) return;
      if (!mounted) return;
      goToSession(context, session);
    } on ApiException catch (e) {
      if (!mounted) return;
      showStatus(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deliveryLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final r = await TestService.deliveryLogin(
        _dNameCtrl.text.trim(),
        _dMobileCtrl.text.trim(),
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DeliveryBoyTestScreen(initialLogin: r),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      showStatus(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _google() async {
    if (!_tncOk()) return;
    setState(() => _googleLoading = true);
    try {
      final session = await AuthService.loginWithGoogle();
      if (!mounted) return;
      if (!await _testAllowed(session, anyRole: true)) return;
      if (!mounted) return;
      goToSession(context, session);
    } on ApiException catch (e) {
      if (!mounted) return;
      showStatus(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Widget _testToggle(bool busy) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: _testOn ? const Color(0xFFDCEBFF) : AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _testOn ? AppColors.blue : AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.science_outlined,
              size: 18, color: _testOn ? AppColors.blue : AppColors.muted),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Test mode',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text)),
          ),
          Switch(
            value: _testOn,
            activeColor: AppColors.blue,
            onChanged: busy ? null : _setTest,
          ),
        ],
      ),
    );
  }

  Widget _roleSelector(bool busy) {
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
            value: 'retailer',
            label: FittedBox(fit: BoxFit.scaleDown, child: Text('Retailer'))),
        ButtonSegment(
            value: 'distributor',
            label: FittedBox(fit: BoxFit.scaleDown, child: Text('Distributor'))),
        ButtonSegment(
            value: 'delivery',
            label: FittedBox(fit: BoxFit.scaleDown, child: Text('Delivery Boy'))),
      ],
      selected: {_role},
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
      ),
      onSelectionChanged:
          busy ? null : (s) => setState(() => _role = s.first),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading || _googleLoading;
    final isDelivery = _testOn && _role == 'delivery';
    return AuthScaffold(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: BrandLogo()),
            const SizedBox(height: 20),
            const Text(
              'Welcome back',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w500,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 16),
            _testToggle(busy),
            if (_testOn) ...[
              const SizedBox(height: 12),
              _roleSelector(busy),
            ],
            const SizedBox(height: 20),
            if (isDelivery) ...[
              LabeledField(
                label: 'Name',
                controller: _dNameCtrl,
                hint: 'Delivery boy name',
                textInputAction: TextInputAction.next,
                validator: requiredValidator,
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: 'Mobile Number',
                controller: _dMobileCtrl,
                hint: 'Enter your mobile number',
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => busy ? null : _login(),
                validator: (v) =>
                    (v ?? '').replaceAll(RegExp(r'\D'), '').length < 10
                        ? 'Enter 10 digit mobile'
                        : null,
              ),
              const SizedBox(height: 24),
              GradientButton(
                label: 'Login as Delivery Boy',
                loading: _loading,
                onPressed: busy ? null : _login,
              ),
            ] else ...[
              LabeledField(
                label: 'Email or Mobile Number',
                controller: _idCtrl,
                hint: 'Enter your email or mobile number',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: requiredValidator,
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: 'Password',
                controller: _pwCtrl,
                hint: 'Enter your password',
                obscure: _obscure,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => busy ? null : _login(),
                validator: requiredValidator,
                suffix: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: AppColors.blue,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ForgotPasswordScreen(),
                            ),
                          ),
                  child: const Text('Forgot password?',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: Checkbox(
                        value: _agree,
                        onChanged: (v) => setState(() => _agree = v ?? false),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'I have read and agree to the Ozie Terms & Conditions and Privacy Policy.',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.muted, height: 1.4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              GradientButton(
                label: 'Sign in',
                loading: _loading,
                onPressed: busy ? null : _login,
              ),
              const SizedBox(height: 20),
              const Row(
                children: [
                  Expanded(child: Divider(color: AppColors.border)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('OR',
                        style: TextStyle(fontSize: 11, color: AppColors.muted)),
                  ),
                  Expanded(child: Divider(color: AppColors.border)),
                ],
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: busy ? null : _google,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  foregroundColor: AppColors.text,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: _googleLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.g_mobiledata_rounded, size: 28),
                label: Text(
                    _googleLoading ? 'Processing...' : 'Sign in with Google'),
              ),
              if (!_testOn) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(child: const Text(
                      "Don't have an account? ",
                      style: TextStyle(fontSize: 13, color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    GestureDetector(
                      onTap: busy
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              ),
                      child: const Text(
                        'Sign up',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

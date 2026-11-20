import 'package:flutter/material.dart';

import '../screens/distributor/distributor_shell.dart';
import '../screens/generic_home_screen.dart';
import '../screens/main_shell.dart';
import '../screens/login_screen.dart';
import '../screens/role_selection_screen.dart';
import '../screens/salesman/salesman_home_screen.dart';
import '../screens/test/distributor_test_screen.dart';
import '../screens/test/retailer_test_screen.dart';
import '../screens/wait_for_approval_screen.dart';
import 'auth_service.dart';
import 'models.dart';
import 'test_mode.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// User types that already have a dedicated dashboard in the app.
const Set<String> kDedicatedDashboards = {'retailer'};

Widget screenFor(Session s) {
  final type = (s.user.userType ?? '').toLowerCase();

  switch (s.nextScreen) {
    case 'wait_for_approval':
      return WaitForApprovalScreen(session: s);
    case 'role_selection':
      return RoleSelectionScreen(session: s);
    case 'dashboard':
    default:
      // Test mode: bare test homes (quick actions only, no bottom menu).
      if (TestMode.enabled.value) {
        if (type == 'retailer') return RetailerTestHome(session: s);
        if (type == 'distributor') return DistributorTestHome(session: s);
      }
      // Dedicated screen exists -> use it. Otherwise generic home.
      if (kDedicatedDashboards.contains(type)) return MainShell(session: s);
      if (type == 'salesman') return SalesmanHomeScreen(session: s);
      if (type == 'distributor') return DistributorShell(session: s);
      return GenericHomeScreen(session: s);
  }
}

void goToSession(BuildContext context, Session s) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => screenFor(s)),
    (route) => false,
  );
}

void goToLogin(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    (route) => false,
  );
}

Future<void> logoutAndGoToLogin(BuildContext context) async {
  await AuthService.logout();
  if (!context.mounted) return;
  goToLogin(context);
}
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/debug_log.dart';
import '../screens/bank_card_screen.dart';
import '../screens/cart_screen.dart';
import '../screens/catalog_screen.dart';
import '../screens/coming_soon_screen.dart';
import '../screens/invoices_screen.dart';
import '../screens/pending_payments_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/tabs/orders_tab.dart';
import '../widgets/app_widgets.dart';
import '../screens/schemes_screen.dart';

const Map<String, String> _kLinkTitles = {
  'orders': 'Orders',
  'new_order': 'New Order',
  'catalog': 'Catalog',
  'bank_card': 'Bank Card',
  'team': 'My Team',
};

String _titleFor(String key) {
  final t = _kLinkTitles[key];
  if (t != null) return t;
  return key
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

Future<void> _openUrl(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (e, st) {
    DebugLog.error('launchUrl', e, st);
  }
}

/// Open what a notification points to.
///  - `https://...`      -> external browser
///  - known screen key   -> that screen (retailer panel only has real ones)
///  - any other key      -> ComingSoonScreen (screen not built yet)
///  - empty              -> returns false (caller keeps default behaviour)
bool openNotificationLink(NavigatorState nav, String? link) {
  final raw = (link ?? '').trim();
  DebugLog.log('router raw="$raw"');
  if (raw.isEmpty) return false;

  if (raw.toLowerCase().startsWith('https://')) {
    DebugLog.log('router -> open url');
    _openUrl(raw);
    return true;
  }

  final key = raw.toLowerCase();
  DebugLog.log('router key=$key');
  Widget screen;
  switch (key) {
    // Real screens. Only the retailer panel has screens; admin offers
    // these only when target = Retailers. Other panels use https links.
    case 'orders':
      screen = Scaffold(
        appBar: AppBar(
          title: const Text('Orders'),
          backgroundColor: AppColors.card,
          surfaceTintColor: Colors.transparent,
        ),
        body: const OrdersTab(),
      );
      break;
    case 'schemes':
      screen = const SchemesScreen();
      break;
    case 'cart':
      screen = const CartScreen();
      break;
    case 'catalog':
      screen = const CatalogScreen();
      break;
    case 'bank_card':
      screen = const BankCardScreen();
      break;
    case 'payments':
    case 'pending_payments':
      screen = const PendingPaymentsScreen();
      break;
    case 'invoices':
    case 'invoice':
      screen = const InvoicesScreen();
      break;
    case 'profile':
      screen = const ProfileScreen();
      break;
    default:
      screen = ComingSoonScreen(title: _titleFor(key));
  }
  nav.push(MaterialPageRoute<void>(builder: (_) => screen));
  return true;
}
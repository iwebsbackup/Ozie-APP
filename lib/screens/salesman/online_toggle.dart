import 'package:flutter/material.dart';

import '../../core/location_tracker.dart';
import '../../widgets/app_widgets.dart';

/// Appbar pill: Online / Offline switch for the salesman.
///  ON  -> permissions checked, live tracking starts (salesman is online)
///  OFF -> tracking stops (salesman is offline)
class OnlineToggle extends StatefulWidget {
  const OnlineToggle({super.key});

  @override
  State<OnlineToggle> createState() => _OnlineToggleState();
}

class _OnlineToggleState extends State<OnlineToggle> {
  bool _busy = false;

  Future<void> _change(bool wantOnline) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (wantOnline) {
        // null = every permission allowed -> online. Otherwise toggle stays OFF.
        final missing = await LocationTracker.goOnline(context);
        if (missing != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Cannot go online. $missing')));
        }
      } else {
        await LocationTracker.goOffline();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: LocationTracker.online,
      builder: (context, on, _) {
        final fg = on ? AppColors.successText : AppColors.muted;
        final bg = on ? AppColors.successBg : AppColors.inputBg;
        return Container(
          padding: const EdgeInsets.only(left: 10, right: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on ? AppColors.successText : AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: on ? AppColors.green : AppColors.muted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(on ? 'Online' : 'Offline',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
              const SizedBox(width: 2),
              SizedBox(
                width: 44,
                height: 30,
                child: _busy
                    ? const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : FittedBox(
                        child: Switch(
                          value: on,
                          onChanged: _change,
                          activeColor: AppColors.green,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
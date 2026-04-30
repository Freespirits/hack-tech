import 'package:flutter/material.dart';

import '../../ble/connection_state_machine.dart';

class ConnectionStatusChip extends StatelessWidget {
  const ConnectionStatusChip({super.key, required this.state});
  final BleConnectionState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color, icon) = switch (state) {
      Idle() => ('Idle', scheme.outline, Icons.bluetooth_disabled),
      Scanning() => ('Scanning…', scheme.primary, Icons.bluetooth_searching),
      Connecting(:final attempt) => (
          'Connecting (attempt $attempt)',
          scheme.tertiary,
          Icons.bluetooth_audio,
        ),
      DiscoveringServices() => (
          'Discovering services',
          scheme.tertiary,
          Icons.search,
        ),
      NegotiatingMtu() => (
          'Negotiating MTU',
          scheme.tertiary,
          Icons.swap_horiz,
        ),
      SubscribingNotifications() => (
          'Subscribing',
          scheme.tertiary,
          Icons.notifications_active,
        ),
      Connected(:final deviceName) => (
          'Connected • $deviceName',
          Colors.green,
          Icons.bluetooth_connected,
        ),
      Reconnecting(:final attempt, :final delay) => (
          'Reconnecting in ${delay.inSeconds}s (attempt $attempt)',
          scheme.tertiary,
          Icons.refresh,
        ),
      Disconnected() => (
          'Disconnected',
          scheme.error,
          Icons.bluetooth_disabled,
        ),
    };
    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label, style: TextStyle(color: color)),
      backgroundColor: color.withOpacity(0.08),
      side: BorderSide(color: color.withOpacity(0.3)),
    );
  }
}

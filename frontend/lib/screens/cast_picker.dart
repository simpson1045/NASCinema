import 'package:flutter/material.dart';

import '../services/cast/cast_device.dart';
import '../services/cast_controller.dart';
import '../theme/app_theme.dart';

/// Bottom-sheet device picker for casting. Discovers on open and lists devices
/// live. Reused by the player (cast a movie) and the library (connect first).
class CastPicker extends StatefulWidget {
  const CastPicker({
    super.key,
    required this.cast,
    required this.onPick,
    required this.onDisconnect,
  });

  final CastController cast;
  final void Function(CastDevice) onPick;
  final VoidCallback onDisconnect;

  @override
  State<CastPicker> createState() => _CastPickerState();
}

class _CastPickerState extends State<CastPicker> {
  @override
  void initState() {
    super.initState();
    widget.cast.discover();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedBuilder(
        animation: widget.cast,
        builder: (_, _) {
          final c = widget.cast;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Row(
                  children: [
                    const Text('Cast to TV',
                        style: TextStyle(
                            color: NasColors.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (c.isDiscovering)
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: NasColors.amber)),
                  ],
                ),
              ),
              if (c.isConnected)
                ListTile(
                  leading:
                      const Icon(Icons.cast_connected, color: NasColors.amber),
                  title: Text('Connected — ${c.connectedDevice?.name ?? ''}',
                      style: const TextStyle(color: NasColors.text)),
                  trailing: TextButton(
                    onPressed: widget.onDisconnect,
                    child: const Text('Stop',
                        style: TextStyle(color: NasColors.amber)),
                  ),
                ),
              for (final d in c.devices)
                ListTile(
                  leading: const Icon(Icons.tv, color: NasColors.muted),
                  title: Text(d.name,
                      style: const TextStyle(color: NasColors.text)),
                  subtitle: Text(d.host,
                      style:
                          const TextStyle(color: NasColors.muted, fontSize: 11)),
                  onTap: () => widget.onPick(d),
                ),
              if (!c.isDiscovering && c.devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No Chromecast devices found',
                      style: TextStyle(color: NasColors.muted)),
                ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }
}

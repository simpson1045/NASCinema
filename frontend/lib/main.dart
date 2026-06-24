import 'package:flutter/material.dart';

import 'services/api_service.dart';
import 'services/server_config.dart';
import 'theme/app_theme.dart';

void main() => runApp(const NasCinemaApp());

class NasCinemaApp extends StatelessWidget {
  const NasCinemaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NASCinema',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const ConnectScreen(),
    );
  }
}

/// Phase-0 shell: configure the backend address and confirm connectivity.
/// The real login + library browser land in Phase 1.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _config = ServerConfig();
  final _urlController = TextEditingController(text: 'http://localhost:8400');
  bool _busy = false;
  String? _error;
  HealthStatus? _health;

  @override
  void initState() {
    super.initState();
    _config.get().then((saved) {
      if (saved != null && saved.isNotEmpty) {
        setState(() => _urlController.text = saved);
      }
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
      _health = null;
    });
    final url = _urlController.text.trim();
    try {
      final status = await ApiService(url).health();
      await _config.set(url);
      setState(() => _health = status);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Brand(),
                const SizedBox(height: 28),
                const Text(
                  'Server address',
                  style: TextStyle(color: NasColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: 'http://your-server:8400',
                    prefixIcon: Icon(Icons.dns_outlined, color: NasColors.muted),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _busy ? null : _connect,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: NasColors.bg,
                          ),
                        )
                      : const Text('Connect'),
                ),
                const SizedBox(height: 24),
                if (_error != null) _ErrorBox(_error!),
                if (_health != null) _HealthCard(_health!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.movie_outlined, color: NasColors.amber, size: 34),
            const SizedBox(width: 10),
            RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  color: NasColors.text,
                ),
                children: [
                  TextSpan(text: 'NAS'),
                  TextSpan(
                    text: 'Cinema',
                    style: TextStyle(color: NasColors.amber),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Your movies. Your NAS. No subscription.',
          style: TextStyle(color: NasColors.muted, fontSize: 13),
        ),
      ],
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard(this.health);
  final HealthStatus health;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: NasColors.ok, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Connected · backend v${health.version}',
                  style: const TextStyle(
                    color: NasColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip('database', health.db),
                _StatusChip('ffmpeg', health.ffmpeg),
                _StatusChip('ffprobe', health.ffprobe),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${health.mediaDirs} media folder(s) configured',
              style: const TextStyle(color: NasColors.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.label, this.ok);
  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final color = ok ? NasColors.ok : NasColors.bad;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check : Icons.close, color: color, size: 15),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NasColors.bad.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NasColors.bad.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: NasColors.bad, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: NasColors.text, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'screens/library_screen.dart';
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

/// Configure the backend address, validate it, then enter the library.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _config = ServerConfig();
  // On web the app is served by the backend, so default to that same origin.
  final _urlController = TextEditingController(
    text: kIsWeb ? Uri.base.origin : 'http://localhost:8400',
  );
  bool _busy = false;
  String? _error;

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
    });
    final url = _urlController.text.trim();
    try {
      await ApiService(url).health(); // validate reachability
      await _config.set(url);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LibraryScreen(baseUrl: url)),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
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
                  onSubmitted: (_) => _busy ? null : _connect(),
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

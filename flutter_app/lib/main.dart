import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Set at build time, e.g.:
/// flutter run --dart-define=API_BASE_URL=https://your-app.onrender.com/api/v1
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000/api/v1',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GlorettoApp());
}

class GlorettoApp extends StatelessWidget {
  const GlorettoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gloretto',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _status = 'Tap “Ping API” to verify Laravel is reachable.';
  bool _loading = false;

  Future<void> _pingApi() async {
    setState(() {
      _loading = true;
      _status = 'GET $kApiBaseUrl/hotels …';
    });
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final res = await dio.get<Map<String, dynamic>>('$kApiBaseUrl/hotels');
      final n = (res.data?['data'] as List?)?.length ?? 0;
      setState(() {
        _status = 'OK (${res.statusCode}) — $n hotel(s) in response.';
      });
    } on DioException catch (e) {
      setState(() {
        _status = 'Error: ${e.message ?? e.type.name}';
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gloretto')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('API: $kApiBaseUrl', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            Text(_status, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _pingApi,
              child: Text(_loading ? 'Loading…' : 'Ping API (GET /hotels)'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Use portal login, Sanctum tokens, and guest tokens per backend docs (flutter_app/README.md).',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

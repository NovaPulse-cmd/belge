import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BelgeAsistaniApp());
}

class BelgeAsistaniApp extends StatelessWidget {
  const BelgeAsistaniApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Belge Asistanı',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4F46E5),
        scaffoldBackgroundColor: const Color(0xFFF7F7FB),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _uuid = const Uuid();
  String? _installationId;
  bool _premium = false;
  bool _busy = false;
  String? _selectedFile;
  String? _selectedPath;
  String? _lastResult;
  String? _lastFilename;
  String? _error;
  DateTime? _premiumActivatedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadIdentityAndStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPremium(silent: true);
    }
  }

  Future<void> _loadIdentityAndStatus() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('installation_id');
    if (id == null || !RegExp(r'^[a-f0-9-]{36}$', caseSensitive: false).hasMatch(id)) {
      id = _uuid.v4();
      await prefs.setString('installation_id', id);
    }
    if (!mounted) return;
    setState(() => _installationId = id);
    await _checkPremium();
  }

  String get _baseUrl {
    final value = AppConfig.apiBaseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    return value;
  }

  bool get _backendConfigured =>
      _baseUrl.isNotEmpty &&
      !_baseUrl.contains('BACKEND-DOMAININIZ.example') &&
      !_baseUrl.contains('example.com');

  Map<String, String> get _headers => {
        'x-installation-id': _installationId ?? '',
      };

  Future<void> _checkPremium({bool silent = false}) async {
    if (_installationId == null || !_backendConfigured) return;
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/iyzico/status/$_installationId'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _premium = data['premium'] == true;
          _premiumActivatedAt = data['activatedAt'] == null
              ? null
              : DateTime.tryParse(data['activatedAt'].toString());
        });
      }
    } catch (_) {
      if (!silent && mounted) {
        setState(() => _error =
            'Premium durumu kontrol edilemedi. İnternet bağlantınızı ve backend adresini kontrol edin.');
      }
    }
  }

  Future<void> _pickDocument() async {
    setState(() => _error = null);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx', 'xlsx', 'xls', 'csv', 'txt', 'md'],
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.path == null) {
      setState(() => _error = 'Dosyanın yolu alınamadı. Lütfen dosyayı tekrar seçin.');
      return;
    }
    setState(() {
      _selectedFile = file.name;
      _selectedPath = file.path;
      _lastResult = null;
      _lastFilename = null;
    });
  }

  Future<void> _compareDocuments() async {
    if (!_premium) {
      await _showPremiumRequired();
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx', 'xlsx', 'xls', 'csv', 'txt', 'md'],
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.length != 2) {
      if (mounted) {
        setState(() => _error = 'Karşılaştırmak için tam olarak iki belge seçin.');
      }
      return;
    }
    final paths = result.files.map((e) => e.path).whereType<String>().toList();
    if (paths.length != 2) {
      setState(() => _error = 'Seçilen belgelerin dosya yolları alınamadı.');
      return;
    }

    await _runCompare(paths[0], paths[1], result.files[0].name, result.files[1].name);
  }

  Future<void> _runCompare(
    String pathA,
    String pathB,
    String nameA,
    String nameB,
  ) async {
    if (!_backendConfigured) {
      setState(() => _error = 'Backend adresi yapılandırılmamış.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _lastResult = null;
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/compare'),
      );
      request.headers.addAll(_headers);
      request.files.add(await http.MultipartFile.fromPath('files', pathA));
      request.files.add(await http.MultipartFile.fromPath('files', pathB));

      final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(minutes: 3)),
      );
      final data = _decodeResponse(response);
      if (response.statusCode != 200) {
        throw Exception(data['error'] ?? 'Karşılaştırma başarısız.');
      }
      setState(() {
        _lastResult = data['text']?.toString() ?? '';
        _lastFilename = '$nameA ↔ $nameB';
      });
    } catch (e) {
      setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runAnalysis(String action, {String? language, String? question}) async {
    if (!_premium) {
      await _showPremiumRequired();
      return;
    }
    final path = _selectedPath;
    if (path == null) {
      setState(() => _error = 'Önce bir belge seçin.');
      return;
    }
    if (!_backendConfigured) {
      setState(() => _error = 'Backend adresi yapılandırılmamış.');
      return;
    }

    if (action == 'ask' && (question == null || question.trim().isEmpty)) return;

    setState(() {
      _busy = true;
      _error = null;
      _lastResult = null;
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/analyze'),
      );
      request.headers.addAll(_headers);
      request.files.add(await http.MultipartFile.fromPath('file', path));
      request.fields['action'] = action;
      if (language != null) request.fields['language'] = language;
      if (question != null) request.fields['question'] = question;

      final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(minutes: 3)),
      );
      final data = _decodeResponse(response);
      if (response.statusCode != 200) {
        throw Exception(data['error'] ?? 'Belge işlemi başarısız.');
      }
      setState(() {
        _lastResult = data['text']?.toString() ?? '';
        _lastFilename = data['filename']?.toString() ?? _selectedFile;
      });
    } catch (e) {
      setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
      return {'text': decoded.toString()};
    } catch (_) {
      return {'error': utf8.decode(response.bodyBytes)};
    }
  }

  String _cleanError(Object error) {
    var message = error.toString();
    if (message.startsWith('Exception: ')) message = message.substring(11);
    if (message.contains('SocketException')) {
      return 'Sunucuya bağlanılamadı. İnternet bağlantınızı ve backend adresinizi kontrol edin.';
    }
    return message;
  }

  Future<void> _askQuestion() async {
    final controller = TextEditingController();
    final question = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Belgeye soru sor'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Örn. Bu belgede en önemli üç sonuç nedir?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Sor'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (question != null && question.isNotEmpty) {
      await _runAnalysis('ask', question: question);
    }
  }

  Future<void> _translate() async {
    const languages = ['İngilizce', 'Almanca', 'Fransızca', 'Arapça', 'İspanyolca'];
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Hedef dili seçin'),
        children: [
          for (final language in languages)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, language),
              child: Text(language),
            ),
        ],
      ),
    );
    if (selected != null) {
      await _runAnalysis('translate', language: selected);
    }
  }

  Future<void> _showPremiumRequired() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Premium gerekli'),
        content: const Text(
          'Bu özellik Belge Asistanı Premium kapsamındadır.\n\n'
          '299 TL tek seferlik ödeme ile Premium\'u etkinleştirebilirsiniz. '
          'Abonelik ve otomatik yenileme yoktur.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Daha sonra'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _openPremium();
            },
            child: const Text('Premium\'u aç'),
          ),
        ],
      ),
    );
  }

  Future<void> _openPremium() async {
    if (!_backendConfigured) {
      setState(() => _error =
          'Ödeme için gerçek HTTPS backend adresini GitHub Actions BACKEND_BASE_URL değişkenine tanımlayın.');
      return;
    }
    final form = await showDialog<_BuyerData>(
      context: context,
      builder: (context) => const _BuyerDialog(),
    );
    if (form == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/iyzico/initialize'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'installationId': _installationId,
              'name': form.name,
              'surname': form.surname,
              'email': form.email,
              'gsmNumber': form.gsmNumber,
              'identityNumber': form.identityNumber,
              'address': form.address,
              'city': form.city,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final data = _decodeResponse(response);
      if (response.statusCode != 200) {
        throw Exception(data['error'] ?? 'Ödeme başlatılamadı.');
      }

      final paymentUrl = data['paymentPageUrl']?.toString();
      if (paymentUrl == null || paymentUrl.isEmpty) {
        throw Exception('iyzico ödeme bağlantısı alınamadı.');
      }

      final launched = await launchUrl(
        Uri.parse(paymentUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('iyzico ödeme sayfası açılamadı.');
      }

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ödeme sayfası açıldı'),
          content: const Text(
            'iyzico ödeme işlemini tamamladıktan sonra bu uygulamaya dönün '
            've “Ödemeyi kontrol et” düğmesine basın.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
      await _checkPremium();
    } catch (e) {
      setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(String format) async {
    if (!_premium) {
      await _showPremiumRequired();
      return;
    }
    final text = _lastResult;
    if (text == null || text.trim().isEmpty) {
      setState(() => _error = 'Önce bir belge işlemi sonucu oluşturun.');
      return;
    }
    if (!_backendConfigured) {
      setState(() => _error = 'Backend adresi yapılandırılmamış.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/export'),
            headers: {
              ..._headers,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'text': text, 'format': format}),
          )
          .timeout(const Duration(minutes: 2));

      if (response.statusCode != 200) {
        final data = _decodeResponse(response);
        throw Exception(data['error'] ?? 'Dışa aktarma başarısız.');
      }

      final dir = await getApplicationDocumentsDirectory();
      final extension = format == 'pdf' ? 'pdf' : 'docx';
      final file = File(
        '${dir.path}/belge-asistani-${DateTime.now().millisecondsSinceEpoch}.$extension',
      );
      await file.writeAsBytes(response.bodyBytes, flush: true);
      await OpenFilex.open(file.path);
    } catch (e) {
      setState(() => _error = _cleanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Belge Asistanı',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Premium',
            onPressed: _openPremium,
            icon: Icon(
              _premium ? Icons.workspace_premium : Icons.workspace_premium_outlined,
              color: _premium ? Colors.amber.shade800 : null,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _checkPremium(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _heroCard(cs),
              const SizedBox(height: 16),
              if (!_backendConfigured) _backendWarning(),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _errorCard(_error!),
              ],
              const SizedBox(height: 16),
              _uploadCard(),
              const SizedBox(height: 16),
              _actionGrid(),
              const SizedBox(height: 16),
              if (_lastResult != null) _resultCard(),
              const SizedBox(height: 16),
              _premiumCard(),
              const SizedBox(height: 16),
              _compareCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroCard(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.primaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.description_outlined, color: Colors.white, size: 38),
          SizedBox(height: 14),
          Text(
            'Belgelerinizi yapay zekâ ile yönetin.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'PDF, Word, Excel ve metin belgelerinizi yükleyin; özetleyin, soru sorun, çevirin ve rapor oluşturun.',
            style: TextStyle(color: Colors.white, fontSize: 15, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _backendWarning() {
    return Card(
      color: Colors.orange.shade50,
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_off_outlined, color: Colors.orange),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Backend adresi henüz yapılandırılmamış. APK derlenmeden önce GitHub Actions içindeki BACKEND_BASE_URL değişkenini gerçek HTTPS adresinizle doldurun.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(String message) {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            IconButton(
              onPressed: () => setState(() => _error = null),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  Widget _uploadCard() {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _busy ? null : _pickDocument,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                child: Icon(_selectedFile == null ? Icons.upload_file : Icons.description),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedFile ?? 'Belge seçin',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _selectedFile == null
                          ? 'PDF • Word • Excel • CSV • TXT'
                          : 'İşleme hazır',
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionGrid() {
    final actions = [
      _ActionData('Özetle', Icons.summarize_outlined, () => _runAnalysis('summary')),
      _ActionData('Soru Sor', Icons.chat_bubble_outline, _askQuestion),
      _ActionData('Çevir', Icons.translate, _translate),
      _ActionData('Rapor', Icons.article_outlined, () => _runAnalysis('report')),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.35,
      ),
      itemBuilder: (context, index) {
        final item = actions[index];
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _busy ? null : item.onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(item.icon, size: 30),
                  const Spacer(),
                  Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  const Text('Premium'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _resultCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'AI sonucu',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: _export,
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'docx', child: Text('Word olarak dışa aktar')),
                    PopupMenuItem(value: 'pdf', child: Text('PDF olarak dışa aktar')),
                  ],
                ),
              ],
            ),
            if (_lastFilename != null) ...[
              const SizedBox(height: 6),
              Text(_lastFilename!, style: TextStyle(color: Colors.grey.shade700)),
            ],
            const Divider(height: 24),
            SelectableText(
              _lastResult!,
              style: const TextStyle(fontSize: 15, height: 1.55),
            ),
          ],
        ),
      ),
    );
  }

  Widget _premiumCard() {
    return Card(
      elevation: 0,
      color: Colors.indigo.shade50,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.workspace_premium, color: Colors.amber.shade800, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _premium ? 'Premium aktif' : 'Belge Asistanı Premium',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_premium)
              Text(
                _premiumActivatedAt == null
                    ? 'Premium kullanımınız aktif.'
                    : 'Aktivasyon: ${_premiumActivatedAt!.day.toString().padLeft(2, '0')}.${_premiumActivatedAt!.month.toString().padLeft(2, '0')}.${_premiumActivatedAt!.year}',
              )
            else ...[
              const Text(
                '299 TL • tek seferlik ödeme\nAbonelik yok • aylık ödeme yok • otomatik yenileme yok',
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  Chip(label: Text('PDF analiz')),
                  Chip(label: Text('Word analiz')),
                  Chip(label: Text('Excel analiz')),
                  Chip(label: Text('Soru-cevap')),
                  Chip(label: Text('Çeviri')),
                  Chip(label: Text('Rapor')),
                  Chip(label: Text('Karşılaştırma')),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _openPremium,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('299 TL ile Premium\'u satın al'),
                ),
              ),
            ],
            if (_premium) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _checkPremium(),
                icon: const Icon(Icons.refresh),
                label: const Text('Premium durumunu kontrol et'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _compareCard() {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.compare_arrows)),
        title: const Text(
          'İki belgeyi karşılaştır',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text('Ortak noktalar, farklılıklar, çelişkiler ve eksikler'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _busy ? null : _compareDocuments,
      ),
    );
  }
}

class _ActionData {
  const _ActionData(this.title, this.icon, this.onTap);
  final String title;
  final IconData icon;
  final VoidCallback onTap;
}

class _BuyerData {
  const _BuyerData({
    required this.name,
    required this.surname,
    required this.email,
    required this.gsmNumber,
    required this.identityNumber,
    required this.address,
    required this.city,
  });

  final String name;
  final String surname;
  final String email;
  final String gsmNumber;
  final String identityNumber;
  final String address;
  final String city;
}

class _BuyerDialog extends StatefulWidget {
  const _BuyerDialog();

  @override
  State<_BuyerDialog> createState() => _BuyerDialogState();
}

class _BuyerDialogState extends State<_BuyerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _surname = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _identity = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _surname.dispose();
    _email.dispose();
    _phone.dispose();
    _identity.dispose();
    _address.dispose();
    _city.dispose();
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Bu alan zorunlu.' : null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Premium satın alma'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '299 TL tek seferlik ödeme. Ödeme iyzico sayfasında tamamlanır.',
                ),
                const SizedBox(height: 14),
                TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Ad'), validator: _required),
                const SizedBox(height: 8),
                TextFormField(controller: _surname, decoration: const InputDecoration(labelText: 'Soyad'), validator: _required),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-posta'),
                  validator: (value) {
                    if (_required(value) != null) return _required(value);
                    if (!value!.contains('@')) return 'Geçerli bir e-posta girin.';
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Telefon'),
                  validator: _required,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _identity,
                  keyboardType: TextInputType.number,
                  maxLength: 11,
                  decoration: const InputDecoration(labelText: 'T.C. Kimlik No'),
                  validator: (value) {
                    if (value == null || !RegExp(r'^\d{11}$').hasMatch(value.trim())) {
                      return '11 haneli T.C. kimlik numarası girin.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _address,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Adres'),
                  validator: _required,
                ),
                const SizedBox(height: 8),
                TextFormField(controller: _city, decoration: const InputDecoration(labelText: 'Şehir'), validator: _required),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _BuyerData(
                name: _name.text.trim(),
                surname: _surname.text.trim(),
                email: _email.text.trim(),
                gsmNumber: _phone.text.trim(),
                identityNumber: _identity.text.trim(),
                address: _address.text.trim(),
                city: _city.text.trim(),
              ),
            );
          },
          child: const Text('iyzico ile ödemeye geç'),
        ),
      ],
    );
  }
}

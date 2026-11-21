import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

void main() => runApp(const BelgeAsistaniApp());

class BelgeAsistaniApp extends StatelessWidget {
  const BelgeAsistaniApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Belge Asistanı',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B55D9)), useMaterial3: true),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  String? _installationId;
  final _uuid = const Uuid();
  final _name = TextEditingController();
  final _surname = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _identityNumber = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController(text: 'İzmir');
  bool _premium = false;
  bool _billingBusy = false;
  

  @override
  void initState() {
    super.initState();
    _loadInstallation();
  }

  Future<void> _loadInstallation() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('belge_asistani_installation_id');
    if (id == null) {
      id = _uuid.v4();
      await prefs.setString('belge_asistani_installation_id', id);
    }
    if (mounted) setState(() => _installationId = id);
    await _checkPremium(silent: true);
  }

  Future<void> _checkPremium({bool silent = false}) async {
    final id = _installationId;
    if (id == null) return;
    try {
      final r = await http.get(Uri.parse('${AppConfig.apiBaseUrl}/api/iyzico/status/$id'));
      if (r.statusCode >= 400) throw Exception('Premium durumu alınamadı.');
      final data = jsonDecode(r.body);
      if (mounted) setState(() => _premium = data['premium'] == true);
    } catch (e) {
      if (!silent && mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _startPayment() async {
    if (_installationId == null) return;
    if ([_name, _surname, _email, _phone, _identityNumber, _address, _city].any((c) => c.text.trim().isEmpty)) {
      setState(() => error = 'Ödeme için tüm fatura bilgilerini doldurun.');
      return;
    }
    if (!RegExp(r'^\d{11}$').hasMatch(_identityNumber.text.trim())) {
      setState(() => error = 'T.C. kimlik numarası 11 rakam olmalıdır.');
      return;
    }
    setState(() { _billingBusy = true; error = null; });
    try {
      final r = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/api/iyzico/initialize'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'installationId': _installationId,
          'name': _name.text.trim(), 'surname': _surname.text.trim(),
          'email': _email.text.trim(), 'gsmNumber': _phone.text.trim(),
          'identityNumber': _identityNumber.text.trim(),
          'address': _address.text.trim(), 'city': _city.text.trim(),
        }),
      );
      final data = jsonDecode(r.body);
      if (r.statusCode >= 400 || data['paymentPageUrl'] == null) {
        throw Exception(data['error'] ?? 'iyzico ödeme sayfası oluşturulamadı.');
      }
      final uri = Uri.parse(data['paymentPageUrl']);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Ödeme sayfası açılamadı.');
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => _billingBusy = false);
    }
  }

  Future<void> _showPaymentDetails() async {
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('Fatura bilgileri'),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _field(_name, 'Ad'), _field(_surname, 'Soyad'), _field(_email, 'E-posta', keyboard: TextInputType.emailAddress),
        _field(_phone, 'Telefon (+905...)', keyboard: TextInputType.phone),
        _field(_identityNumber, 'T.C. kimlik numarası', keyboard: TextInputType.number),
        _field(_address, 'Fatura adresi', lines: 2), _field(_city, 'İl'),
        const SizedBox(height: 8), const Text('Tek seferlik 299 TL ödeme. Abonelik veya otomatik yenileme yoktur.', style: TextStyle(fontSize: 12)),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: _billingBusy ? null : () { Navigator.pop(context); _startPayment(); }, child: const Text('iyzico ile öde — 299 TL'))],
    ));
  }

  Widget _field(TextEditingController c, String label, {TextInputType? keyboard, int lines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: c, keyboardType: keyboard, maxLines: lines,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true)));

  @override
  void dispose() {
    question.dispose(); language.dispose();
    _name.dispose(); _surname.dispose(); _email.dispose(); _phone.dispose();
    _identityNumber.dispose(); _address.dispose(); _city.dispose();
    super.dispose();
  }
  PlatformFile? selected;
  PlatformFile? second;
  String result = '';
  bool busy = false;
  final question = TextEditingController();
  final language = TextEditingController(text: 'İngilizce');
  String? error;

  Future<PlatformFile?> choose() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf','docx','xlsx','xls','csv','txt','md'], withData: true);
    if (r == null || r.files.isEmpty) return null;
    return r.files.first;
  }
  Future<void> pickMain() async {
    final f = await choose(); if (f != null) setState(() { selected=f; error=null; });
  }
  Future<void> pickSecond() async {
    final f = await choose(); if (f != null) setState(() { second=f; error=null; });
  }
  Future<void> analyze(String action) async {
    if (!_premium) { setState(() => error = 'Bu özellik için Premium satın alımı gerekir.'); return; }
    if (selected == null) { setState(()=>error='Önce bir belge seçin.'); return; }
    setState(()=>{busy=true,error=null,result=''});
    try {
      final req = http.MultipartRequest('POST', Uri.parse('${AppConfig.apiBaseUrl}/api/analyze'));
      req.headers['x-installation-id'] = _installationId ?? '';
      req.fields['action']=action;
      if (action=='ask') req.fields['question']=question.text.trim();
      if (action=='translate') req.fields['language']=language.text.trim();
      req.files.add(await http.MultipartFile.fromPath('file', selected!.path!, filename:selected!.name));
      final streamed = await req.send();
      final body = await streamed.stream.bytesToString();
      final data = jsonDecode(body);
      if (streamed.statusCode >= 400) throw Exception(data['error'] ?? 'Sunucu hatası');
      setState(()=>result=data['text'] ?? '');
    } catch(e) { setState(()=>error=e.toString()); }
    finally { setState(()=>busy=false); }
  }
  Future<void> compare() async {
    if (!_premium) { setState(() => error = 'Bu özellik için Premium satın alımı gerekir.'); return; }
    if(selected==null || second==null){setState(()=>error='Karşılaştırma için iki belge seçin.');return;}
    setState(()=>{busy=true,error=null,result=''});
    try {
      final req=http.MultipartRequest('POST',Uri.parse('${AppConfig.apiBaseUrl}/api/compare'));
      req.headers['x-installation-id'] = _installationId ?? '';
      req.files.add(await http.MultipartFile.fromPath('files',selected!.path!,filename:selected!.name));
      req.files.add(await http.MultipartFile.fromPath('files',second!.path!,filename:second!.name));
      final streamed=await req.send(); final body=await streamed.stream.bytesToString(); final data=jsonDecode(body);
      if(streamed.statusCode>=400) throw Exception(data['error']??'Sunucu hatası');
      setState(()=>result=data['text']??'');
    } catch(e){setState(()=>error=e.toString());}
    finally{setState(()=>busy=false);}
  }
  Future<void> export(String format) async {
    if (!_premium) { setState(() => error = 'Bu özellik için Premium satın alımı gerekir.'); return; }
    if(result.isEmpty)return;
    try {
      final r=await http.post(Uri.parse('${AppConfig.apiBaseUrl}/api/export'),headers:{'Content-Type':'application/json','x-installation-id':_installationId ?? ''},body:jsonEncode({'text':result,'format':format}));
      if(r.statusCode>=400) throw Exception('Dışa aktarma başarısız.');
      final dir=await getApplicationDocumentsDirectory();
      final file=File('${dir.path}/belge-asistani.${format=='pdf'?'pdf':'docx'}');
      await file.writeAsBytes(r.bodyBytes);
      if(!mounted)return;
      await OpenFilex.open(file.path);
    }catch(e){setState(()=>error=e.toString());}
  }
  Widget actionButton(String label, IconData icon, VoidCallback fn)=>Expanded(child:FilledButton.tonalIcon(onPressed:busy?null:fn,icon:Icon(icon),label:Text(label)));
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Belge Asistanı'),centerTitle:true),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
      Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:Theme.of(context).colorScheme.primaryContainer,borderRadius:BorderRadius.circular(20)),child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Belgelerinle konuş.',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
        SizedBox(height:6),Text('PDF, Word ve Excel dosyalarını analiz et, özetle ve rapora dönüştür.')
      ])),
      const SizedBox(height:16),
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[Icon(_premium ? Icons.verified : Icons.lock, color: _premium ? Colors.green : null),const SizedBox(width:8),Text(_premium ? 'Premium aktif' : 'Premium erişim',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))]),
        const SizedBox(height:6),
        Text(_premium ? 'Tüm belge analiz özellikleri açık.' : 'Tüm özellikleri kalıcı olarak açmak için 299 TL tek seferlik ödeme yapın.'),
        const SizedBox(height:10),
        if (!_premium) FilledButton.icon(onPressed: _billingBusy ? null : _showPaymentDetails,
          icon: const Icon(Icons.workspace_premium), label: const Text('Premium’u Satın Al — 299 TL')),
        if (!_premium) OutlinedButton.icon(onPressed: _billingBusy ? null : () => _checkPremium(),
          icon: const Icon(Icons.refresh), label: const Text('Ödemeyi kontrol et / Premium’u geri yükle')),
        
      ]))),
      const SizedBox(height:12),
      Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('1. Belge seç',style:TextStyle(fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        OutlinedButton.icon(onPressed:busy?null:pickMain,icon:const Icon(Icons.upload_file),label:Text(selected?.name??'PDF / DOCX / XLSX / TXT seç')),
        if(second!=null) Text('İkinci belge: ${second!.name}'),
        TextButton.icon(onPressed:busy?null:pickSecond,icon:const Icon(Icons.add),label:const Text('Karşılaştırma için ikinci belge seç'))
      ]))),
      const SizedBox(height:12),
      const Text('2. Ne yapmak istiyorsun?',style:TextStyle(fontWeight:FontWeight.bold)),
      const SizedBox(height:8),
      Row(children:[actionButton('Özetle',Icons.summarize,()=>analyze('summary')),const SizedBox(width:8),actionButton('Rapor',Icons.description,()=>analyze('report'))]),
      const SizedBox(height:8),
      Row(children:[actionButton('Karşılaştır',Icons.compare_arrows,compare),const SizedBox(width:8),actionButton('Çevir',Icons.translate,()=>analyze('translate'))]),
      TextField(controller:language,decoration:const InputDecoration(labelText:'Çeviri dili',hintText:'Örn. İngilizce, Almanca')),
      const SizedBox(height:12),
      TextField(controller:question,maxLines:2,decoration:const InputDecoration(labelText:'Belgeye soru sor',hintText:'Bu belgenin en önemli üç sonucu nedir?',border:OutlineInputBorder())),
      const SizedBox(height:8),
      FilledButton.icon(onPressed:busy?null:()=>analyze('ask'),icon:const Icon(Icons.chat),label:const Text('Soruyu yanıtla')),
      if(busy) const Padding(padding:EdgeInsets.all(20),child:Center(child:CircularProgressIndicator())),
      if(error!=null) Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      if(result.isNotEmpty) ...[
        const SizedBox(height:18),const Text('Sonuç',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
        Card(child:Padding(padding:const EdgeInsets.all(14),child:SelectableText(result))),
        Row(children:[actionButton('Word olarak aç',Icons.article,()=>export('docx')),const SizedBox(width:8),actionButton('PDF olarak aç',Icons.picture_as_pdf,()=>export('pdf'))])
      ],
      const SizedBox(height:20),
      const Text('Not: AI yanıtlarını önemli kararlar için mutlaka kaynak belgeyle karşılaştır.'),
    ]))),
  );
}

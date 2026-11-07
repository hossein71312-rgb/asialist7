import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart' show InputImage, RecognizedText, TextRecognizer;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shamsi_date/shamsi_date.dart';

const _fd = '۰۱۲۳۴۵۶۷۸۹', _ad = '٠١٢٣٤٥٦٧٨٩';
const purple = Color(0xFF7B2FA0);
String fa(String s) => s.replaceAllMapped(RegExp(r'[0-9]'), (m) => _fd[int.parse(m[0]!)]);
String en(String s) {
  var r = s;
  for (var i = 0; i < 10; i++) {
    r = r.replaceAll(_fd[i], '$i').replaceAll(_ad[i], '$i');
  }
  return r;
}
String norm(String s) => en(s).replaceAll('ي', 'ی').replaceAll('ك', 'ک').toLowerCase().trim();
String money(int v) {
  final neg = v < 0;
  final s = v.abs().toString(), b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return fa('${neg ? '-' : ''}$b');
}
int pInt(String s) => int.tryParse(en(s).replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
double pDbl(String s) => double.tryParse(en(s).replaceAll('٫', '.').replaceAll(',', '.')) ?? 0;
String shamsi(DateTime d) {
  final j = Jalali.fromDateTime(d);
  return fa('${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}');
}
int round100(double v) => (v / 100).round() * 100;
void snack(BuildContext c, String t) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(t)));

class Product {
  String id, name, code, barcode, cat;
  int buy, sell, qty;
  double profit;
  String? photo;
  DateTime updated;
  List<Map<String, dynamic>> hist;
  Product({required this.id, this.name = '', this.code = '', this.barcode = '', this.cat = '', this.buy = 0, this.sell = 0, this.qty = 0, this.profit = 20, this.photo, DateTime? updated, List<Map<String, dynamic>>? hist})
      : updated = updated ?? DateTime.now(),
        hist = hist ?? [];
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'code': code, 'barcode': barcode, 'cat': cat, 'buy': buy, 'sell': sell, 'qty': qty, 'profit': profit, 'photo': photo, 'updated': updated.toIso8601String(), 'hist': hist};
  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'], name: j['name'] ?? '', code: j['code'] ?? '', barcode: j['barcode'] ?? '', cat: j['cat'] ?? '',
        buy: j['buy'] ?? 0, sell: j['sell'] ?? 0, qty: j['qty'] ?? 0, profit: (j['profit'] ?? 20).toDouble(), photo: j['photo'],
        updated: DateTime.tryParse(j['updated'] ?? ''), hist: List<Map<String, dynamic>>.from((j['hist'] ?? []).map((e) => Map<String, dynamic>.from(e))));
  void record() {
    updated = DateTime.now();
    hist.add({'d': updated.toIso8601String(), 's': sell, 'b': buy});
  }
  File? get photoFile => photo == null ? null : File('${docDir.path}/photos/$photo');
  bool get low => qty <= st.low;
}

class Settings {
  String shop, phone, address, footer;
  String? logo, lastBackup, pin;
  int low, nextNo;
  Settings({this.shop = 'فروشگاه من', this.phone = '', this.address = '', this.footer = 'با تشکر از خرید شما', this.logo, this.lastBackup, this.pin, this.low = 3, this.nextNo = 1001});
  Map<String, dynamic> toJson() => {'shop': shop, 'phone': phone, 'address': address, 'footer': footer, 'logo': logo, 'lastBackup': lastBackup, 'pin': pin, 'low': low, 'nextNo': nextNo};
  factory Settings.fromJson(Map<String, dynamic> j) => Settings(shop: j['shop'] ?? '', phone: j['phone'] ?? '', address: j['address'] ?? '', footer: j['footer'] ?? '', logo: j['logo'], lastBackup: j['lastBackup'], pin: j['pin'], low: j['low'] ?? 3, nextNo: j['nextNo'] ?? 1001);
}

class Invoice {
  int no, discount, paid;
  DateTime date;
  String customer, phone, pay, cid;
  bool voided;
  List<Map<String, dynamic>> lines, pays;
  Invoice({required this.no, required this.date, this.customer = '', this.phone = '', this.cid = '', required this.lines, this.discount = 0, this.pay = 'cash', this.paid = 0, this.voided = false, List<Map<String, dynamic>>? pays}) : pays = pays ?? [];
  int get sum => lines.fold<int>(0, (a, l) => a + (l['q'] as int) * (l['p'] as int));
  int get total => sum - discount;
  int get debt => voided ? 0 : total - paid;
  int get profit {
    var t = 0;
    for (final l in lines) {
      final b = (l['b'] ?? 0) as int;
      if (b > 0) t += ((l['p'] as int) - b) * (l['q'] as int);
    }
    return t - discount;
  }
  Map<String, dynamic> toJson() => {'no': no, 'date': date.toIso8601String(), 'customer': customer, 'phone': phone, 'lines': lines, 'discount': discount, 'pay': pay, 'paid': paid, 'void': voided, 'pays': pays, 'cid': cid};
  factory Invoice.fromJson(Map<String, dynamic> j) {
    final v = Invoice(
      no: j['no'], date: DateTime.parse(j['date']), customer: j['customer'] ?? '', cid: j['cid'] ?? '', phone: j['phone'] ?? '', discount: j['discount'] ?? 0,
      pay: j['pay'] ?? 'cash', paid: j['paid'] ?? 0, voided: j['void'] ?? false,
      lines: List<Map<String, dynamic>>.from((j['lines'] ?? []).map((e) => Map<String, dynamic>.from(e))),
      pays: List<Map<String, dynamic>>.from((j['pays'] ?? []).map((e) => Map<String, dynamic>.from(e))),
    );
    if (j['paid'] == null) v.paid = v.total;
    return v;
  }
}

class Customer {
  String id, name, phone, note;
  Customer({required this.id, required this.name, this.phone = '', this.note = ''});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone, 'note': note};
  factory Customer.fromJson(Map<String, dynamic> j) => Customer(id: j['id'], name: j['name'] ?? '', phone: j['phone'] ?? '', note: j['note'] ?? '');
}

late Directory docDir;
List<Customer> customers = [];
List<Product> items = [];
List<Invoice> invoices = [];
Settings st = Settings();
File _f(String n) => File('${docDir.path}/$n');
Future<void> _w(String n, String data) async {
  final f = _f(n), t = _f('$n.tmp');
  await t.writeAsString(data, flush: true);
  if (await f.exists()) {
    try {
      await f.copy('${f.path}.bak');
    } catch (_) {}
  }
  await t.rename(f.path);
}
Future<void> saveDb() => _w('products.json', jsonEncode(items.map((e) => e.toJson()).toList()));
Future<void> saveSt() => _w('settings.json', jsonEncode(st.toJson()));
Future<void> saveInv() => _w('invoices.json', jsonEncode(invoices.map((e) => e.toJson()).toList()));
Future<void> saveCust() => _w('customers.json', jsonEncode(customers.map((e) => e.toJson()).toList()));
Future<void> loadDb() async {
  docDir = await getApplicationDocumentsDirectory();
  await Directory('${docDir.path}/photos').create(recursive: true);
  items = [];
  invoices = [];
  customers = [];
  st = Settings();
  Future<dynamic> rd(String n) async {
    for (final x in [n, '$n.bak']) {
      final f = _f(x);
      if (await f.exists()) {
        try {
          return jsonDecode(await f.readAsString());
        } catch (_) {}
      }
    }
    return null;
  }
  final a = await rd('products.json');
  if (a is List) items = a.map((e) => Product.fromJson(Map<String, dynamic>.from(e))).toList();
  final s = await rd('settings.json');
  if (s is Map) st = Settings.fromJson(Map<String, dynamic>.from(s));
  final v = await rd('invoices.json');
  if (v is List) invoices = v.map((e) => Invoice.fromJson(Map<String, dynamic>.from(e))).toList();
  final cu = await rd('customers.json');
  if (cu is List) customers = cu.map((e) => Customer.fromJson(Map<String, dynamic>.from(e))).toList();
  for (final v in invoices) {
    if (v.cid.isEmpty && v.customer.trim().isNotEmpty) {
      final m = customers.where((c) => c.name.trim() == v.customer.trim()).toList();
      if (m.length == 1) v.cid = m.first.id;
    }
  }
}
Product? prod(String id) => items.where((e) => e.id == id).firstOrNull;
String hashPin(String p) => sha256.convert(utf8.encode('asia-v1:$p')).toString();
String hn(String s) => norm(s).replaceAll('\u200c', ' ').replaceAll(RegExp(r'\s+'), ' ');
int pMoney(String s) {
  final d = double.tryParse(en(s).replaceAll(RegExp(r'[,،\s]'), ''));
  return d == null ? 0 : d.round();
}
String cleanCell(String s) {
  s = s.trim();
  if (s.startsWith('="') && s.endsWith('"') && s.length >= 3) s = s.substring(2, s.length - 1);
  return s;
}
String csvCell(String s) => (s.contains(',') || s.contains('"') || s.contains('\n')) ? '"${s.replaceAll('"', '""')}"' : s;
List<List<String>> parseCsv(String text, String d) {
  final rows = <List<String>>[];
  var row = <String>[];
  final f = StringBuffer();
  var q = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (q) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          f.write('"');
          i++;
        } else {
          q = false;
        }
      } else {
        f.write(c);
      }
    } else if (c == '"') {
      q = true;
    } else if (c == d) {
      row.add(f.toString());
      f.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(f.toString());
      f.clear();
      if (row.any((e) => e.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      f.write(c);
    }
  }
  row.add(f.toString());
  if (row.any((e) => e.trim().isNotEmpty)) rows.add(row);
  return rows;
}
List<Invoice> invOf(Customer c) => invoices.where((v) => v.cid.isNotEmpty ? v.cid == c.id : v.customer.trim() == c.name.trim()).toList();
int debtOf(Customer c) => invOf(c).fold<int>(0, (a, v) => a + v.debt);
int boughtOf(Customer c) => invOf(c).where((v) => !v.voided).fold<int>(0, (a, v) => a + v.total);
Widget logoImg(double size) {
  final f = st.logo == null ? null : File('${docDir.path}/photos/${st.logo}');
  return (f != null && f.existsSync()) ? Image.file(f, width: size, height: size, fit: BoxFit.contain) : const SizedBox.shrink();
}
Future<ui.Image> capture(GlobalKey k) async {
  await WidgetsBinding.instance.endOfFrame;
  final ctx = k.currentContext;
  if (ctx == null) throw Exception('صفحه کامل آماده نیست؛ دوباره امتحان کنید');
  final b = ctx.findRenderObject() as RenderRepaintBoundary;
  final pr = b.size.height * 2.5 > 7000 ? 7000 / b.size.height : 2.5;
  return b.toImage(pixelRatio: pr);
}
Future<void> guard(BuildContext c, Future<void> Function() f) async {
  snack(c, 'در حال آماده‌سازی…');
  try {
    await f();
  } catch (e) {
    if (c.mounted) {
      showDialog(
        context: c,
        builder: (_) => AlertDialog(
          title: const Text('خطا'),
          content: SingleChildScrollView(child: SelectableText('$e')),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('بستن'))],
        ),
      );
    }
  }
}
Future<Uint8List> pngOf(ui.Image i) async => (await i.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
Future<Uint8List> pdfOfKeys(List<GlobalKey> keys) async {
  final doc = pw.Document();
  for (final k in keys) {
    final img = await capture(k);
    final png = await pngOf(img);
    const w = 420.0;
    final h = w * img.height / img.width;
    doc.addPage(pw.Page(pageFormat: PdfPageFormat(w, h), margin: pw.EdgeInsets.zero, build: (_) => pw.Image(pw.MemoryImage(png), width: w, height: h, fit: pw.BoxFit.fill)));
  }
  return doc.save();
}
Future<void> payDialog(BuildContext c, Invoice v) async {
  final t = TextEditingController(text: fa('${v.debt}'));
  final ok = await showDialog<bool>(
    context: c,
    builder: (_) => AlertDialog(
      title: Text('ثبت پرداخت — مانده ${money(v.debt)}'),
      content: TextField(controller: t, keyboardType: TextInputType.number, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('ثبت')),
      ],
    ),
  );
  if (ok == true) {
    final a = pInt(t.text) > v.debt ? v.debt : pInt(t.text);
    if (a > 0) {
      v.paid += a;
      v.pays.add({'d': DateTime.now().toIso8601String(), 'a': a});
      await saveInv();
    }
  }
}
Future<String?> pickPhoto(ImageSource s) async {
  final x = await ImagePicker().pickImage(source: s, maxWidth: 900, imageQuality: 70);
  if (x == null) return null;
  final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
  await File(x.path).copy('${docDir.path}/photos/$name');
  return name;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadDb();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'لیست قیمت آسیا',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: purple,
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF6F2F9),
          appBarTheme: const AppBarTheme(backgroundColor: purple, foregroundColor: Colors.white),
        ),
        builder: (c, w) => Directionality(textDirection: TextDirection.rtl, child: LockGate(child: w!)),
        home: const Home(),
      );
}

// ---------------- Home ----------------
class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  String q = '';
  final sel = <String>{};

  String sort = 'name';
  String? catF;
  bool lowOnly = false, oldOnly = false;

  List<Product> get shown {
    final k = norm(q);
    final now = DateTime.now();
    final l = items.where((p) => (k.isEmpty || norm(p.name).contains(k) || p.code.contains(k) || p.barcode == k) && (catF == null || p.cat == catF) && (!lowOnly || p.low) && (!oldOnly || now.difference(p.updated).inDays > 30)).toList();
    switch (sort) {
      case 'pa':
        l.sort((a, b) => a.sell.compareTo(b.sell));
      case 'pd':
        l.sort((a, b) => b.sell.compareTo(a.sell));
      case 'qa':
        l.sort((a, b) => a.qty.compareTo(b.qty));
      case 'old':
        l.sort((a, b) => a.updated.compareTo(b.updated));
      default:
        l.sort((a, b) => a.name.compareTo(b.name));
    }
    return l;
  }

  Future<void> go(Widget w) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    setState(() {});
  }

  Future<void> scan() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanPage()));
    if (code == null || !mounted) return;
    final p = items.where((e) => e.barcode == code || (e.code.isNotEmpty && e.code == en(code))).firstOrNull;
    if (p == null) {
      snack(context, 'کالای جدید است؛ اطلاعاتش را وارد کنید');
      await go(EditPage(barcode: code));
    } else {
      showQuick(p);
    }
  }

  void showQuick(Product p) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (p.photoFile != null && p.photoFile!.existsSync()) Image.file(p.photoFile!, height: 160),
          const SizedBox(height: 8),
          Text(p.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          Text('${money(p.sell)} تومان', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
          Text('موجودی: ${fa('${p.qty}')}', style: TextStyle(color: p.low ? Colors.red : Colors.black87)),
          Text('آخرین تغییر قیمت: ${shamsi(p.updated)}'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
          FilledButton(onPressed: () { Navigator.pop(context); go(EditPage(product: p)); }, child: const Text('ویرایش')),
        ],
      ),
    );
  }

  Future<void> bulkMenu() async {
    if (sel.isNotEmpty) {
      bulk(items.where((p) => sel.contains(p.id)).toList());
      return;
    }
    final c = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.select_all), title: const Text('همه‌ی کالاها'), onTap: () => Navigator.pop(context, 'all')),
          ListTile(leading: const Icon(Icons.checklist), title: const Text('انتخاب کالا از لیست'), onTap: () => Navigator.pop(context, 'pick')),
        ]),
      ),
    );
    if (!mounted) return;
    if (c == 'all') {
      bulk(List.of(items));
    } else if (c == 'pick') {
      final ids = await Navigator.push<Set<String>>(context, MaterialPageRoute(builder: (_) => const MultiPickPage()));
      if (ids != null && ids.isNotEmpty) bulk(items.where((p) => ids.contains(p.id)).toList());
    }
  }

  void bulk(List<Product> targets) {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تغییر قیمت ${fa('${targets.length}')} کالا'),
        content: TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'درصد افزایش (برای کاهش، منفی بنویسید)', suffixText: '٪')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(
            onPressed: () async {
              final pct = double.tryParse(en(c.text).replaceAll('٫', '.')) ?? 0;
              if (pct != 0) {
                for (final p in targets) {
                  if (p.buy > 0) {
                    p.buy = (p.buy * (1 + pct / 100)).round();
                    p.sell = round100(p.buy * (1 + p.profit / 100));
                  } else {
                    p.sell = round100(p.sell * (1 + pct / 100));
                  }
                  p.record();
                }
                await saveDb();
              }
              if (mounted) { Navigator.pop(context); setState(() => sel.clear()); }
            },
            child: const Text('اعمال'),
          ),
        ],
      ),
    );
  }

  Future<void> shareMenu() async {
    final targets = sel.isEmpty ? shown : items.where((p) => sel.contains(p.id)).toList();
    final c = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.text_snippet), title: const Text('ارسال به‌صورت متن'), onTap: () => Navigator.pop(context, 't')),
          ListTile(leading: const Icon(Icons.picture_as_pdf), title: const Text('لیست قیمت مرتب (تصویر / PDF)'), onTap: () => Navigator.pop(context, 'p')),
        ]),
      ),
    );
    if (!mounted) return;
    if (c == 't') {
      shareText();
    } else if (c == 'p' && targets.isNotEmpty) {
      go(PriceListPage(targets));
    }
  }

  Widget backupBanner() {
    final lb = st.lastBackup == null ? null : DateTime.tryParse(st.lastBackup!);
    final old = lb == null || DateTime.now().difference(lb).inDays >= 7;
    if (!old || (items.isEmpty && invoices.isEmpty)) return const SizedBox.shrink();
    return Card(
      color: const Color(0xFFFFF3E0),
      child: ListTile(dense: true, leading: const Icon(Icons.warning_amber, color: Colors.orange), title: Text(lb == null ? 'هنوز پشتیبان نگرفته‌اید' : 'آخرین پشتیبان ${shamsi(lb)} بود'), trailing: const Text('گرفتن'), onTap: () => go(const SettingsPage())),
    );
  }

  void shareText() {
    final targets = sel.isEmpty ? shown : items.where((p) => sel.contains(p.id)).toList();
    final t = StringBuffer('لیست قیمت ${st.shop} — ${shamsi(DateTime.now())}\n\n');
    for (final p in targets) {
      t.writeln('${p.name}: ${money(p.sell)} تومان');
    }
    Share.share(t.toString());
  }

  Color ageColor(Product p) {
    final d = DateTime.now().difference(p.updated).inDays;
    return d > 30 ? Colors.red : (d > 14 ? Colors.orange : Colors.green);
  }

  Widget stat(String t, String v, Color c) => Expanded(
        child: Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Column(children: [
          Text(v, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: c)),
          const SizedBox(height: 2),
          Text(t, style: const TextStyle(fontSize: 11)),
        ]))),
      );

  Widget nav(IconData i, String t, VoidCallback f) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6)),
            onPressed: f,
            child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(i), const SizedBox(height: 2), Text(t, style: const TextStyle(fontSize: 12))]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final list = shown;
    final stockVal = items.fold<int>(0, (a, p) => a + p.buy * p.qty);
    final lowCount = items.where((p) => p.low).length;
    final cats = items.map((p) => p.cat).where((c) => c.isNotEmpty).toSet().toList()..sort();
    const sorts = {'name': 'نام', 'pa': 'ارزان‌ترین', 'pd': 'گران‌ترین', 'qa': 'کم‌موجودترین', 'old': 'قدیمی‌ترین قیمت'};
    Widget header() => Column(children: [
          backupBanner(),
          Row(children: [
            stat('تعداد کالا', fa('${items.length}'), purple),
            stat('ارزش موجودی (خرید)', money(stockVal), Colors.teal),
            stat('کم‌موجود', fa('$lowCount'), lowCount > 0 ? Colors.red : Colors.green),
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(children: [
              Row(children: [
                nav(Icons.point_of_sale, 'فروش جدید', () => go(const SalePage())),
                nav(Icons.move_to_inbox, 'ورود کالا', () => go(const StockInPage())),
                nav(Icons.receipt_long, 'فاکتورها', () => go(const InvoicesPage())),
                nav(Icons.people, 'مشتریان', () => go(const CustomersPage())),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                nav(Icons.bar_chart, 'گزارش', () => go(const ReportPage())),
                nav(Icons.account_balance_wallet, 'بدهکاران', () => go(const DebtPage())),
                nav(Icons.table_chart, 'اکسل', () => go(const ExcelPage())),
                nav(Icons.settings, 'تنظیمات', () => go(const SettingsPage())),
              ]),
            ]),
          ),
          if (list.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Text('کالایی پیدا نشد. با دکمه‌ی پایین کالا اضافه کنید.')),
        ]);
    return Scaffold(
      appBar: AppBar(
        title: Text(sel.isEmpty ? st.shop : '${fa('${sel.length}')} انتخاب'),
        leading: sel.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(sel.clear)),
        actions: [
          IconButton(tooltip: 'تغییر درصدی قیمت', icon: const Icon(Icons.trending_up), onPressed: bulkMenu),
          IconButton(tooltip: 'ارسال لیست', icon: const Icon(Icons.share), onPressed: shareMenu),
          IconButton(tooltip: 'راهنما', icon: const Icon(Icons.help_outline), onPressed: () => go(const HelpPage())),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: TextField(
            decoration: InputDecoration(hintText: 'جست‌وجوی نام یا کد کالا', prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            onChanged: (v) => setState(() => q = v),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
            PopupMenuButton<String>(
              onSelected: (v) => setState(() => sort = v),
              itemBuilder: (_) => [for (final e in sorts.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
              child: Chip(avatar: const Icon(Icons.sort, size: 18), label: Text('مرتب‌سازی: ${sorts[sort]}')),
            ),
            const SizedBox(width: 6),
            FilterChip(label: const Text('کم‌موجود'), selected: lowOnly, onSelected: (v) => setState(() => lowOnly = v)),
            const SizedBox(width: 6),
            FilterChip(label: const Text('قیمت قدیمی'), selected: oldOnly, onSelected: (v) => setState(() => oldOnly = v)),
            for (final c in cats) Padding(padding: const EdgeInsetsDirectional.only(start: 6), child: ChoiceChip(label: Text(c), selected: catF == c, onSelected: (v) => setState(() => catF = v ? c : null))),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: list.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) return header();
              final p = list[i - 1];
              final days = DateTime.now().difference(p.updated).inDays;
              final f = p.photoFile;
              return Card(
                child: ListTile(
                  selected: sel.contains(p.id),
                  leading: SizedBox(width: 52, height: 52, child: (f != null && f.existsSync()) ? ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.file(f, fit: BoxFit.cover)) : const Icon(Icons.inventory_2_outlined, size: 36)),
                  title: Text(p.name),
                  subtitle: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                    Icon(Icons.circle, size: 10, color: ageColor(p)),
                    Text(days == 0 ? 'امروز' : '${fa('$days')} روز پیش'),
                    Text('موجودی: ${fa('${p.qty}')}', style: TextStyle(color: p.low ? Colors.red : null, fontWeight: p.low ? FontWeight.bold : null)),
                    if (p.cat.isNotEmpty) Text('• ${p.cat}', style: const TextStyle(color: Colors.black54)),
                  ]),
                  trailing: Text(money(p.sell), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                  onTap: () => sel.isNotEmpty ? setState(() => sel.contains(p.id) ? sel.remove(p.id) : sel.add(p.id)) : showQuick(p),
                  onLongPress: () => setState(() => sel.contains(p.id) ? sel.remove(p.id) : sel.add(p.id)),
                ),
              );
            },
          ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(children: [
            Expanded(flex: 3, child: FilledButton.icon(style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)), onPressed: scan, icon: const Icon(Icons.qr_code_scanner), label: const Text('اسکن بارکد', style: TextStyle(fontSize: 16)))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: FilledButton.tonalIcon(style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)), onPressed: () => go(const EditPage()), icon: const Icon(Icons.add), label: const Text('کالای جدید'))),
          ]),
        ),
      ),
    );
  }
}

// ---------------- Scan ----------------
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? ctrl;
  bool done = false, torch = false;

  @override
  void dispose() {
    ctrl?.dispose();
    super.dispose();
  }

  void created(QRViewController c) {
    ctrl = c;
    c.scannedDataStream.listen((s) {
      final v = s.code;
      if (done || v == null || v.isEmpty) return;
      done = true;
      if (mounted) Navigator.pop(context, v);
    });
  }

  void typeCode() {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('کد یا بارکد را تایپ کنید'),
        content: TextField(controller: c, keyboardType: TextInputType.number, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(
            onPressed: () {
              final t = en(c.text).trim();
              Navigator.pop(context);
              if (t.isNotEmpty) {
                done = true;
                Navigator.pop(context, t);
              }
            },
            child: const Text('تأیید'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('بارکد را داخل کادر بگیرید'), actions: [
          IconButton(
            icon: Icon(torch ? Icons.flash_on : Icons.flash_off),
            onPressed: () async {
              await ctrl?.toggleFlash();
              final f = await ctrl?.getFlashStatus();
              setState(() => torch = f ?? false);
            },
          ),
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: FilledButton.tonalIcon(onPressed: typeCode, icon: const Icon(Icons.keyboard), label: const Text('تایپ دستی کد')),
          ),
        ),
        body: QRView(
          key: qrKey,
          onQRViewCreated: created,
          overlay: QrScannerOverlayShape(borderColor: Colors.white, borderWidth: 6, cutOutWidth: 320, cutOutHeight: 180, overlayColor: const Color(0x99000000)),
        ),
      );
}

// ---------------- Edit product ----------------
class EditPage extends StatefulWidget {
  final Product? product;
  final String barcode;
  const EditPage({super.key, this.product, this.barcode = ''});
  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  late final nameC = TextEditingController(text: widget.product?.name ?? '');
  late final codeC = TextEditingController(text: fa(widget.product?.code ?? ''));
  late final barC = TextEditingController(text: widget.product?.barcode ?? widget.barcode);
  late final buyC = TextEditingController(text: widget.product == null || widget.product!.buy == 0 ? '' : fa('${widget.product!.buy}'));
  late final profC = TextEditingController(text: fa((widget.product?.profit ?? 20).toString().replaceAll(RegExp(r'\.0$'), '')));
  late final sellC = TextEditingController(text: widget.product == null ? '' : fa('${widget.product!.sell}'));
  late final qtyC = TextEditingController(text: fa('${widget.product?.qty ?? 0}'));
  late final catC = TextEditingController(text: widget.product?.cat ?? '');
  String? photo;

  @override
  void initState() {
    super.initState();
    photo = widget.product?.photo;
  }

  void calc() {
    final buy = pInt(buyC.text);
    if (buy > 0) sellC.text = fa('${round100(buy * (1 + pDbl(profC.text) / 100))}');
  }

  Future<void> pick(ImageSource s) async {
    final n = await pickPhoto(s);
    if (n != null) setState(() => photo = n);
  }

  Future<void> scanBar() async {
    final c = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanPage()));
    if (c != null) setState(() => barC.text = c);
  }

  Future<void> save() async {
    final name = nameC.text.trim();
    if (name.isEmpty) {
      snack(context, 'اسم کالا را بنویسید');
      return;
    }
    final buy = pInt(buyC.text), sell = pInt(sellC.text);
    final bc = barC.text.trim();
    final dup = bc.isEmpty ? null : items.where((e) => e.barcode == bc && e.id != widget.product?.id).firstOrNull;
    if (dup != null) {
      snack(context, 'این بارکد قبلاً برای «${dup.name}» ثبت شده');
      return;
    }
    var p = widget.product;
    final isNew = p == null;
    final changed = isNew || p.sell != sell || p.buy != buy;
    p ??= Product(id: '${DateTime.now().millisecondsSinceEpoch}');
    p..name = name..code = en(codeC.text).trim()..barcode = barC.text.trim()..buy = buy..sell = sell..qty = pInt(qtyC.text)..cat = catC.text.trim()..profit = pDbl(profC.text)..photo = photo;
    if (changed) p.record();
    if (isNew) items.add(p);
    await saveDb();
    if (mounted) Navigator.pop(context);
  }

  Future<void> del() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(title: const Text('حذف کالا؟'), actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('خیر')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
      ]),
    );
    if (ok == true) {
      items.remove(widget.product);
      await saveDb();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = photo == null ? null : File('${docDir.path}/photos/$photo');
    final hist = widget.product?.hist.reversed.take(10).toList() ?? [];
    const bd = OutlineInputBorder();
    return Scaffold(
      appBar: AppBar(title: Text(widget.product == null ? 'کالای جدید' : 'ویرایش کالا'), actions: [
        if (widget.product != null) IconButton(icon: const Icon(Icons.delete_outline), onPressed: del),
      ]),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Center(
          child: Container(
            width: 160, height: 160,
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
            child: (f != null && f.existsSync()) ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(f, fit: BoxFit.cover)) : const Icon(Icons.image_outlined, size: 60, color: Colors.grey),
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton.icon(onPressed: () => pick(ImageSource.camera), icon: const Icon(Icons.photo_camera), label: const Text('عکس بگیر')),
          TextButton.icon(onPressed: () => pick(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text('از گالری')),
        ]),
        const SizedBox(height: 8),
        TextField(controller: nameC, decoration: const InputDecoration(labelText: 'نام کالا', border: bd, filled: true, fillColor: Colors.white)),
        const SizedBox(height: 12),
        TextField(controller: codeC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'کد (عدد زیر بارکد)', border: bd, filled: true, fillColor: Colors.white)),
        const SizedBox(height: 12),
        TextField(controller: barC, decoration: InputDecoration(labelText: 'بارکد', border: bd, filled: true, fillColor: Colors.white, suffixIcon: IconButton(icon: const Icon(Icons.qr_code_scanner), onPressed: scanBar))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: buyC, keyboardType: TextInputType.number, onChanged: (_) => calc(), decoration: const InputDecoration(labelText: 'قیمت خرید (تومان)', border: bd, filled: true, fillColor: Colors.white))),
          const SizedBox(width: 8),
          SizedBox(width: 100, child: TextField(controller: profC, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => calc(), decoration: const InputDecoration(labelText: 'سود ٪', border: bd, filled: true, fillColor: Colors.white))),
        ]),
        const SizedBox(height: 12),
        TextField(controller: sellC, keyboardType: TextInputType.number, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), decoration: const InputDecoration(labelText: 'قیمت فروش (تومان)', border: bd, filled: true, fillColor: Colors.white)),
        const SizedBox(height: 12),
        TextField(controller: qtyC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'موجودی (تعداد)', border: bd, filled: true, fillColor: Colors.white)),
        const SizedBox(height: 12),
        TextField(controller: catC, decoration: const InputDecoration(labelText: 'دسته‌بندی (اختیاری)', border: bd, filled: true, fillColor: Colors.white)),
        Wrap(spacing: 6, children: [for (final c in items.map((p) => p.cat).where((c) => c.isNotEmpty).toSet()) ActionChip(label: Text(c), onPressed: () => setState(() => catC.text = c))]),
        const SizedBox(height: 16),
        FilledButton(onPressed: save, child: const Padding(padding: EdgeInsets.all(10), child: Text('ذخیره', style: TextStyle(fontSize: 18)))),
        if (hist.isNotEmpty) ...[
          const Divider(height: 32),
          const Text('تاریخچه‌ی قیمت فروش', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final h in hist) ListTile(dense: true, title: Text('${money(h['s'])} تومان'), trailing: Text(shamsi(DateTime.parse(h['d'])))),
        ],
      ]),
    );
  }
}

// ---------------- Pick product ----------------
class PickPage extends StatefulWidget {
  const PickPage({super.key});
  @override
  State<PickPage> createState() => _PickState();
}

class _PickState extends State<PickPage> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final k = norm(q);
    final l = items.where((p) => k.isEmpty || norm(p.name).contains(k) || p.code.contains(k)).toList();
    return Scaffold(
      appBar: AppBar(
        title: TextField(autofocus: true, style: const TextStyle(color: Colors.white), cursorColor: Colors.white, decoration: const InputDecoration(hintText: 'جست‌وجوی کالا', hintStyle: TextStyle(color: Colors.white70), border: InputBorder.none), onChanged: (v) => setState(() => q = v)),
      ),
      body: ListView(children: [
        for (final p in l)
          ListTile(title: Text(p.name), subtitle: Text('موجودی: ${fa('${p.qty}')}'), trailing: Text(money(p.sell), style: const TextStyle(fontWeight: FontWeight.bold)), onTap: () => Navigator.pop(context, p)),
      ]),
    );
  }
}

class MultiPickPage extends StatefulWidget {
  const MultiPickPage({super.key});
  @override
  State<MultiPickPage> createState() => _MultiPickState();
}

class _MultiPickState extends State<MultiPickPage> {
  String q = '';
  final ids = <String>{};
  List<Product> get list {
    final k = norm(q);
    return items.where((p) => k.isEmpty || norm(p.name).contains(k) || p.code.contains(k)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = list;
    return Scaffold(
      appBar: AppBar(
        title: TextField(style: const TextStyle(color: Colors.white), cursorColor: Colors.white, decoration: const InputDecoration(hintText: 'جست‌وجو', hintStyle: TextStyle(color: Colors.white70), border: InputBorder.none), onChanged: (v) => setState(() => q = v)),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              if (l.every((p) => ids.contains(p.id))) {
                ids.removeAll(l.map((p) => p.id));
              } else {
                ids.addAll(l.map((p) => p.id));
              }
            }),
            child: const Text('همه', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(children: [
        for (final p in l)
          CheckboxListTile(
            value: ids.contains(p.id),
            onChanged: (v) => setState(() {
              if (v == true) {
                ids.add(p.id);
              } else {
                ids.remove(p.id);
              }
            }),
            title: Text(p.name),
            subtitle: Text('${money(p.sell)} تومان'),
          ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: FilledButton(onPressed: ids.isEmpty ? null : () => Navigator.pop(context, ids), child: Text('ادامه (${fa('${ids.length}')} کالا)')),
        ),
      ),
    );
  }
}

// ---------------- Sale ----------------
class SalePage extends StatefulWidget {
  const SalePage({super.key});
  @override
  State<SalePage> createState() => _SaleState();
}

class _SaleState extends State<SalePage> {
  final lines = <Map<String, dynamic>>[];
  final custC = TextEditingController(), phoneC = TextEditingController(), discC = TextEditingController(), paidC = TextEditingController();
  String pay = 'cash';
  bool busy = false;
  String? custId;
  int get sum => lines.fold<int>(0, (a, l) => a + (l['q'] as int) * (l['p'] as int));
  int get disc => pInt(discC.text) > sum ? sum : pInt(discC.text);
  int get total => sum - disc;

  void add(Product p) {
    final i = lines.indexWhere((l) => l['id'] == p.id);
    if ((i >= 0 ? lines[i]['q'] as int : 0) + 1 > p.qty) {
      snack(context, 'موجودی «${p.name}» فقط ${fa('${p.qty}')} عدد است؛ اول موجودی را اصلاح کنید');
      return;
    }
    if (i >= 0) {
      lines[i]['q'] = (lines[i]['q'] as int) + 1;
    } else {
      lines.add({'id': p.id, 'name': p.name, 'q': 1, 'p': p.sell, 'b': p.buy});
    }
    setState(() {});
  }

  Future<void> scan() async {
    final c = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanPage()));
    if (c == null || !mounted) return;
    final p = items.where((e) => e.barcode == c || (e.code.isNotEmpty && e.code == en(c))).firstOrNull;
    if (p == null) {
      snack(context, 'این بارکد ثبت نشده است');
    } else {
      add(p);
    }
  }

  Future<void> pickItem() async {
    final p = await Navigator.push<Product>(context, MaterialPageRoute(builder: (_) => const PickPage()));
    if (p != null) add(p);
  }

  void editPrice(int i) {
    final c = TextEditingController(text: fa('${lines[i]['p']}'));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('قیمت واحد در این فاکتور'),
        content: TextField(controller: c, keyboardType: TextInputType.number, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(onPressed: () { setState(() => lines[i]['p'] = pInt(c.text)); Navigator.pop(context); }, child: const Text('تأیید')),
        ],
      ),
    );
  }

  Future<void> pickCust() async {
    final c = await Navigator.push<Customer>(context, MaterialPageRoute(builder: (_) => const CustomersPage(pick: true)));
    if (c != null) setState(() {
      custC.text = c.name;
      phoneC.text = c.phone;
      custId = c.id;
    });
  }

  Future<void> finish() async {
    if (lines.isEmpty || busy) return;
    if (pay == 'credit' && custC.text.trim().isEmpty) {
      snack(context, 'برای فروش نسیه نام مشتری را بنویسید');
      return;
    }
    for (final l in lines) {
      final sp = prod(l['id']);
      if (sp != null && (l['q'] as int) > sp.qty) {
        snack(context, 'موجودی «${l['name']}» فقط ${fa('${sp.qty}')} عدد است');
        return;
      }
    }
    final cn0 = custC.text.trim();
    Customer? cust;
    if (cn0.isNotEmpty) {
      if (custId != null) cust = customers.where((c) => c.id == custId).firstOrNull;
      if (cust == null) {
        final m = customers.where((c) => c.name.trim() == cn0).toList();
        if (m.length > 1) {
          snack(context, 'چند مشتری با این نام هست؛ با دکمه‌ی جست‌وجوی مشتری یکی را انتخاب کنید');
          return;
        }
        if (m.length == 1) cust = m.first;
      }
    }
    busy = true;
    final inv = Invoice(
      no: st.nextNo, date: DateTime.now(), customer: custC.text.trim(), phone: phoneC.text.trim(), cid: cust?.id ?? '', discount: disc,
      pay: pay, paid: pay == 'credit' ? (pInt(paidC.text) > total ? total : pInt(paidC.text)) : total,
      lines: lines.map((l) => Map<String, dynamic>.from(l)).toList(),
    );
    st.nextNo++;
    for (final l in inv.lines) {
      final p = prod(l['id']);
      if (p != null) {
        final q = l['q'] as int;
        final d = p.qty <= 0 ? 0 : (q > p.qty ? p.qty : q);
        p.qty -= d;
        l['dq'] = d;
      }
    }
    final cn = inv.customer;
    if (cn.isNotEmpty) {
      final ex = cust;
      if (ex == null) {
        final nc = Customer(id: '${DateTime.now().millisecondsSinceEpoch}', name: cn, phone: inv.phone);
        customers.add(nc);
        inv.cid = nc.id;
      } else if (ex.phone.isEmpty && inv.phone.isNotEmpty) {
        ex.phone = inv.phone;
      }
      await saveCust();
    }
    invoices.add(inv);
    await saveDb();
    await saveSt();
    await saveInv();
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => InvoicePage(inv)));
  }

  @override
  Widget build(BuildContext context) {
    const bd = OutlineInputBorder();
    return Scaffold(
      appBar: AppBar(title: const Text('فروش جدید')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Expanded(child: FilledButton.icon(onPressed: scan, icon: const Icon(Icons.qr_code_scanner), label: const Text('اسکن بارکد'))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton.tonalIcon(onPressed: pickItem, icon: const Icon(Icons.search), label: const Text('انتخاب از لیست'))),
          ]),
        ),
        Expanded(
          child: lines.isEmpty
              ? const Center(child: Text('کالایی اضافه نشده'))
              : ListView.builder(
                  itemCount: lines.length,
                  itemBuilder: (_, i) {
                    final l = lines[i];
                    final p = prod(l['id']);
                    final over = p != null && (l['q'] as int) > p.qty;
                    return Card(
                      child: ListTile(
                        title: Text(l['name']),
                        subtitle: Wrap(spacing: 8, children: [
                          InkWell(onTap: () => editPrice(i), child: Text('${money(l['p'])} ✎', style: const TextStyle(color: purple, fontWeight: FontWeight.bold))),
                          if (over) Text('موجودی فقط ${fa('${p.qty}')}', style: const TextStyle(color: Colors.red)),
                        ]),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => setState(() { if ((l['q'] as int) > 1) { l['q'] = (l['q'] as int) - 1; } else { lines.removeAt(i); } })),
                          Text(fa('${l['q']}'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () { if (p != null && (l['q'] as int) + 1 > p.qty) { snack(context, 'موجودی فقط ${fa('${p.qty}')} عدد است'); } else { setState(() => l['q'] = (l['q'] as int) + 1); } }),
                          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => setState(() => lines.removeAt(i))),
                        ]),
                      ),
                    );
                  },
                ),
        ),
        Flexible(child: SingleChildScrollView(child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(child: TextField(controller: custC, onChanged: (_) => custId = null, decoration: InputDecoration(labelText: 'نام مشتری', border: bd, isDense: true, suffixIcon: IconButton(icon: const Icon(Icons.person_search), onPressed: pickCust)))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: phoneC, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'تلفن', border: bd, isDense: true))),
              ]),
              const SizedBox(height: 8),
              TextField(controller: discC, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'تخفیف (تومان)', border: bd, isDense: true)),
              const SizedBox(height: 8),
              Row(children: [
                for (final e in const {'cash': 'نقد', 'card': 'کارت', 'credit': 'نسیه'}.entries)
                  Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: ChoiceChip(label: Text(e.value), selected: pay == e.key, onSelected: (_) => setState(() => pay = e.key))),
              ]),
              if (pay == 'credit') ...[
                const SizedBox(height: 8),
                TextField(controller: paidC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'پیش‌پرداخت (اختیاری)', border: bd, isDense: true)),
              ],
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text('جمع: ${money(total)} تومان', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                FilledButton(onPressed: lines.isEmpty ? null : finish, child: const Text('ثبت فاکتور')),
              ]),
            ]),
          ),
        ))),
      ]),
    );
  }
}

// ---------------- Invoice ----------------
class InvoiceView extends StatelessWidget {
  final Invoice inv;
  const InvoiceView(this.inv, {super.key});
  Widget row(List<String> c, {bool head = false}) {
    const fl = [1, 5, 2, 3, 3];
    return Container(
      color: head ? const Color(0xFFEBDDF3) : null,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: head ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFDDDDDD)))),
      child: Row(children: [for (var i = 0; i < 5; i++) Expanded(flex: fl[i], child: Text(c[i], textAlign: i == 1 ? TextAlign.start : TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: head ? FontWeight.bold : FontWeight.normal)))]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.black87, fontSize: 13),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (st.logo != null) Padding(padding: const EdgeInsetsDirectional.only(end: 10), child: logoImg(70)),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(st.shop, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: purple)),
                if (st.phone.isNotEmpty) Text('تلفن: ${fa(st.phone)}'),
                if (st.address.isNotEmpty) Text(st.address),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('فاکتور فروش', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                Text('شماره: ${fa('${inv.no}')}'),
                Text('تاریخ: ${shamsi(inv.date)}'),
              ]),
            ]),
            const Divider(height: 20, thickness: 2, color: purple),
            if (inv.customer.isNotEmpty || inv.phone.isNotEmpty)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('خریدار: ${inv.customer}${inv.phone.isNotEmpty ? '   تلفن: ${fa(inv.phone)}' : ''}')),
            row(['ردیف', 'شرح کالا', 'تعداد', 'قیمت واحد', 'مبلغ'], head: true),
            for (var i = 0; i < inv.lines.length; i++)
              row([fa('${i + 1}'), inv.lines[i]['name'], fa('${inv.lines[i]['q']}'), money(inv.lines[i]['p']), money((inv.lines[i]['q'] as int) * (inv.lines[i]['p'] as int))]),
            const SizedBox(height: 10),
            Align(alignment: AlignmentDirectional.centerEnd, child: Text('جمع کل: ${money(inv.sum)} تومان')),
            if (inv.discount > 0) Align(alignment: AlignmentDirectional.centerEnd, child: Text('تخفیف: ${money(inv.discount)} تومان')),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: purple, borderRadius: BorderRadius.circular(8)),
              child: Text('مبلغ قابل پرداخت: ${money(inv.total)} تومان', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            Text('نحوه‌ی پرداخت: ${inv.pay == 'cash' ? 'نقد' : inv.pay == 'card' ? 'کارت' : 'نسیه'}${inv.pay == 'credit' ? ' — پرداخت‌شده: ${money(inv.paid)} • مانده: ${money(inv.total - inv.paid)} تومان' : ''}'),
            if (inv.voided) const Padding(padding: EdgeInsets.only(top: 8), child: Text('این فاکتور باطل شده است', textAlign: TextAlign.center, style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold))),
            const SizedBox(height: 18),
            Row(children: const [
              Expanded(child: Text('مهر و امضای فروشنده', textAlign: TextAlign.center, style: TextStyle(fontSize: 11))),
              Expanded(child: Text('امضای خریدار', textAlign: TextAlign.center, style: TextStyle(fontSize: 11))),
            ]),
            const SizedBox(height: 40),
            if (st.footer.isNotEmpty) Text(st.footer, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ]),
        ),
      ),
    );
  }
}

class InvoicePage extends StatefulWidget {
  final Invoice inv;
  const InvoicePage(this.inv, {super.key});
  @override
  State<InvoicePage> createState() => _InvState();
}

class _InvState extends State<InvoicePage> {
  final key = GlobalKey();

  Future<Uint8List> makePdf() => pdfOfKeys([key]);

  Future<void> voidIt() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ابطال فاکتور؟'),
        content: const Text('کالاها به موجودی برمی‌گردند و فاکتور از گزارش‌ها و بدهی‌ها حذف می‌شود.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('خیر')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ابطال')),
        ],
      ),
    );
    if (ok != true) return;
    for (final l in widget.inv.lines) {
      final p = prod(l['id']);
      if (p != null) p.qty += ((l['dq'] ?? l['q']) as int);
    }
    widget.inv.voided = true;
    await saveDb();
    await saveInv();
    if (mounted) setState(() {});
  }

  Future<void> savePdf() async {
    final bytes = await makePdf();
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'invoice-${widget.inv.no}');
  }

  Future<void> sharePdf() async {
    final bytes = await makePdf();
    await Printing.sharePdf(bytes: bytes, filename: 'invoice-${widget.inv.no}.pdf');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('فاکتور ${fa('${widget.inv.no}')}'), actions: [
          if (widget.inv.debt > 0) IconButton(tooltip: 'ثبت پرداخت', icon: const Icon(Icons.payments), onPressed: () async { await payDialog(context, widget.inv); if (mounted) setState(() {}); }),
          if (!widget.inv.voided) IconButton(tooltip: 'ابطال فاکتور', icon: const Icon(Icons.undo), onPressed: voidIt),
        ]),
        body: SingleChildScrollView(padding: const EdgeInsets.all(8), child: RepaintBoundary(key: key, child: InvoiceView(widget.inv))),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(child: FilledButton.icon(onPressed: () => guard(context, savePdf), icon: const Icon(Icons.picture_as_pdf), label: const Text('ذخیره PDF'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.tonalIcon(onPressed: () => guard(context, sharePdf), icon: const Icon(Icons.share), label: const Text('ارسال'))),
            ]),
          ),
        ),
      );
}

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key});
  @override
  State<InvoicesPage> createState() => _InvListState();
}

class _InvListState extends State<InvoicesPage> {
  @override
  Widget build(BuildContext context) {
    final l = invoices.reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('فاکتورها')),
      body: l.isEmpty
          ? const Center(child: Text('هنوز فاکتوری صادر نشده'))
          : ListView(children: [
              for (final v in l)
                Card(
                  child: ListTile(
                    title: Text('فاکتور ${fa('${v.no}')}${v.customer.isNotEmpty ? ' — ${v.customer}' : ''}'),
                    subtitle: Text('${shamsi(v.date)}${v.voided ? ' • باطل' : ''}${v.debt > 0 ? ' • مانده ${money(v.debt)}' : ''}', style: TextStyle(color: v.voided ? Colors.red : (v.debt > 0 ? Colors.orange.shade800 : null))),
                    trailing: Text('${money(v.total)} تومان', style: TextStyle(fontWeight: FontWeight.bold, decoration: v.voided ? TextDecoration.lineThrough : null)),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => InvoicePage(v)));
                      setState(() {});
                    },
                  ),
                ),
            ]),
    );
  }
}

// ---------------- Settings ----------------
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsPage> {
  late final shopC = TextEditingController(text: st.shop);
  late final phoneC = TextEditingController(text: st.phone);
  late final addrC = TextEditingController(text: st.address);
  late final footC = TextEditingController(text: st.footer);
  late final lowC = TextEditingController(text: fa('${st.low}'));
  late final noC = TextEditingController(text: fa('${st.nextNo}'));
  String? logo;
  @override
  void initState() {
    super.initState();
    logo = st.logo;
  }

  Future<void> setPin() async {
    final a = TextEditingController(), b = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('رمز جدید (حداقل ۴ کاراکتر)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: a, obscureText: true, decoration: const InputDecoration(labelText: 'رمز')),
          TextField(controller: b, obscureText: true, decoration: const InputDecoration(labelText: 'تکرار رمز')),
          const Text('بهتر است رمز از حروف انگلیسی و عدد باشد. اگر رمز را فراموش کنید، فقط با پاک کردن برنامه و بازگردانی یک پشتیبانِ قدیمی (بدون رمز) می‌توانید وارد شوید. پس پشتیبان بگیرید.', style: TextStyle(fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ذخیره')),
        ],
      ),
    );
    if (ok != true) return;
    final p = en(a.text);
    if (p.length < 4 || p != en(b.text)) {
      if (mounted) snack(context, 'رمز باید حداقل ۴ کاراکتر و در هر دو کادر یکسان باشد');
      return;
    }
    st.pin = hashPin(p);
    await saveSt();
    if (mounted) setState(() {});
  }

  Future<void> clearPin() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('رمز فعلی را وارد کنید'),
        content: TextField(controller: c, obscureText: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('خاموش کردن')),
        ],
      ),
    );
    if (ok == true) {
      if (hashPin(en(c.text)) == st.pin) {
        st.pin = null;
        await saveSt();
      } else if (mounted) {
        snack(context, 'رمز اشتباه است');
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> backup() async {
    final ar = Archive();
    for (final n in ['products.json', 'settings.json', 'invoices.json', 'customers.json']) {
      final f = _f(n);
      if (await f.exists()) {
        final b = await f.readAsBytes();
        ar.addFile(ArchiveFile(n, b.length, b));
      }
    }
    for (final e in Directory('${docDir.path}/photos').listSync()) {
      if (e is File) {
        final b = await e.readAsBytes();
        ar.addFile(ArchiveFile('photos/${e.uri.pathSegments.last}', b.length, b));
      }
    }
    final data = ZipEncoder().encode(ar);
    if (data == null) return;
    final tmp = await getTemporaryDirectory();
    final j = Jalali.now();
    final path = '${tmp.path}/asia-backup-${j.year}-${j.month}-${j.day}.zip';
    await File(path).writeAsBytes(data);
    st.lastBackup = DateTime.now().toIso8601String();
    await saveSt();
    await Share.shareXFiles([XFile(path)], text: 'پشتیبان لیست قیمت');
    if (mounted) setState(() {});
  }

  Future<void> restore() async {
    final x = await openFile();
    if (x == null) return;
    try {
      final ar = ZipDecoder().decodeBytes(await x.readAsBytes());
      if (!ar.files.any((f) => f.name == 'products.json' || f.name == 'invoices.json')) {
        if (mounted) snack(context, 'این فایل، پشتیبان این برنامه نیست');
        return;
      }
      if (!mounted) return;
      final yes = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('بازگردانی پشتیبان؟'),
          content: const Text('اطلاعات فعلی برنامه با اطلاعات فایل پشتیبان جایگزین می‌شود.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('بازگردانی')),
          ],
        ),
      );
      if (yes != true) return;
      for (final n in ['products.json', 'settings.json', 'invoices.json', 'customers.json']) {
        for (final x in [n, '$n.bak', '$n.tmp']) {
          final old = _f(x);
          if (await old.exists()) await old.delete();
        }
      }
      for (final f in ar.files) {
        if (!f.isFile || f.name.contains('..')) continue;
        final ok = f.name == 'products.json' || f.name == 'settings.json' || f.name == 'invoices.json' || f.name == 'customers.json' || RegExp(r'^photos/[^/]+$').hasMatch(f.name);
        if (!ok) continue;
        final out = File('${docDir.path}/${f.name}');
        await out.parent.create(recursive: true);
        await out.writeAsBytes(f.content as List<int>);
      }
      await loadDb();
      if (mounted) {
        snack(context, 'بازگردانی انجام شد');
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) snack(context, 'خطا در خواندن فایل پشتیبان');
    }
  }

  Future<void> save() async {
    st.shop = shopC.text.trim();
    st.phone = en(phoneC.text).trim();
    st.address = addrC.text.trim();
    st.footer = footC.text.trim();
    st.low = pInt(lowC.text);
    st.nextNo = pInt(noC.text) == 0 ? st.nextNo : pInt(noC.text);
    st.logo = logo;
    await saveSt();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const bd = OutlineInputBorder();
    final f = logo == null ? null : File('${docDir.path}/photos/$logo');
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات فروشگاه')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(child: ListTile(leading: const Icon(Icons.help_outline), title: const Text('راهنمای برنامه'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpPage())))),
        Card(child: ListTile(leading: const Icon(Icons.lock_outline), title: const Text('قفل برنامه با رمز'), subtitle: Text(st.pin == null ? 'خاموش' : 'روشن'), trailing: Switch(value: st.pin != null, onChanged: (v) => v ? setPin() : clearPin()))),
        Center(
          child: Container(
            width: 110, height: 110,
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
            child: (f != null && f.existsSync()) ? Image.file(f, fit: BoxFit.contain) : const Icon(Icons.storefront, size: 50, color: Colors.grey),
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton.icon(onPressed: () async { final n = await pickPhoto(ImageSource.gallery); if (n != null) setState(() => logo = n); }, icon: const Icon(Icons.image), label: const Text('انتخاب لوگو')),
          if (logo != null) TextButton(onPressed: () => setState(() => logo = null), child: const Text('حذف لوگو')),
        ]),
        const SizedBox(height: 8),
        TextField(controller: shopC, decoration: const InputDecoration(labelText: 'نام فروشگاه', border: bd, filled: true, fillColor: Colors.white)),
        const SizedBox(height: 12),
        TextField(controller: phoneC, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'تلفن', border: bd, filled: true, fillColor: Colors.white)),
        const SizedBox(height: 12),
        TextField(controller: addrC, maxLines: 2, decoration: const InputDecoration(labelText: 'آدرس', border: bd, filled: true, fillColor: Colors.white)),
        const SizedBox(height: 12),
        TextField(controller: footC, decoration: const InputDecoration(labelText: 'متن پایین فاکتور', border: bd, filled: true, fillColor: Colors.white)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: lowC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'هشدار کم‌موجودی (تعداد)', border: bd, filled: true, fillColor: Colors.white))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: noC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'شماره‌ی فاکتور بعدی', border: bd, filled: true, fillColor: Colors.white))),
        ]),
        const SizedBox(height: 16),
        FilledButton(onPressed: save, child: const Padding(padding: EdgeInsets.all(10), child: Text('ذخیره', style: TextStyle(fontSize: 18)))),
        const Divider(height: 32),
        const Text('پشتیبان‌گیری', style: TextStyle(fontWeight: FontWeight.bold)),
        Text(st.lastBackup == null ? 'هنوز پشتیبان نگرفته‌اید' : 'آخرین پشتیبان: ${shamsi(DateTime.parse(st.lastBackup!))}'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: FilledButton.tonalIcon(onPressed: backup, icon: const Icon(Icons.upload_file), label: const Text('گرفتن پشتیبان'))),
          const SizedBox(width: 8),
          Expanded(child: FilledButton.tonalIcon(onPressed: restore, icon: const Icon(Icons.restore), label: const Text('بازگردانی'))),
        ]),
      ]),
    );
  }
}


// ---------------- Stock in ----------------
class StockInPage extends StatefulWidget {
  const StockInPage({super.key});
  @override
  State<StockInPage> createState() => _StockInState();
}

class _StockInState extends State<StockInPage> {
  final log = <String>[];

  Future<void> scan() async {
    final c = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanPage()));
    if (c == null || !mounted) return;
    final p = items.where((e) => e.barcode == c || (e.code.isNotEmpty && e.code == en(c))).firstOrNull;
    if (p == null) {
      snack(context, 'این کالا ثبت نشده؛ اول از صفحه‌ی اصلی ثبتش کنید');
      return;
    }
    await receive(p);
  }

  Future<void> pick() async {
    final p = await Navigator.push<Product>(context, MaterialPageRoute(builder: (_) => const PickPage()));
    if (p != null) await receive(p);
  }

  Future<void> receive(Product p) async {
    final qC = TextEditingController(text: fa('1'));
    final bC = TextEditingController(text: p.buy == 0 ? '' : fa('${p.buy}'));
    var upd = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(p.name),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('موجودی فعلی: ${fa('${p.qty}')}'),
            TextField(controller: qC, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: 'تعداد ورودی')),
            TextField(controller: bC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'قیمت خرید جدید (تومان)')),
            CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, value: upd, onChanged: (v) => set(() => upd = v ?? true), title: const Text('قیمت فروش با درصد سود به‌روز شود')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ثبت ورود')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final n = pInt(qC.text);
    if (n <= 0) return;
    p.qty += n;
    final nb = pInt(bC.text);
    if (nb > 0 && nb != p.buy) {
      p.buy = nb;
      if (upd) p.sell = round100(nb * (1 + p.profit / 100));
      p.record();
    }
    await saveDb();
    setState(() => log.insert(0, '${p.name} — ${fa('+$n')} (موجودی: ${fa('${p.qty}')})'));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ورود کالا به انبار')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(child: FilledButton.icon(onPressed: scan, icon: const Icon(Icons.qr_code_scanner), label: const Text('اسکن بارکد'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.tonalIcon(onPressed: pick, icon: const Icon(Icons.search), label: const Text('انتخاب از لیست'))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final r = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const WholesalePage()));
                  if (r == true) setState(() => log.insert(0, 'ورود از فاکتور عمده‌فروش ثبت شد'));
                },
                icon: const Icon(Icons.document_scanner),
                label: const Text('اسکن فاکتور عمده‌فروش'),
              ),
            ),
          ),
          Expanded(
            child: log.isEmpty
                ? const Center(child: Text('کالا را اسکن کنید و تعداد ورودی را بزنید'))
                : ListView(children: [for (final t in log) Card(child: ListTile(leading: const Icon(Icons.check_circle, color: Colors.green), title: Text(t)))]),
          ),
        ]),
      );
}

// ---------------- Wholesale invoice scan ----------------
class WRow {
  String code, name, note;
  int qty, price;
  bool ok, use;
  WRow({this.code = '', this.name = '', this.note = '', this.qty = 0, this.price = 0, this.ok = true, this.use = true});
  Product? get match => code.isEmpty ? null : items.where((p) => p.code == code || (p.barcode.isNotEmpty && p.barcode == code)).firstOrNull;
}

class _Tok {
  final String t;
  final double x, y, h;
  _Tok(this.t, this.x, this.y, this.h);
}

List<WRow> parseWholesale(RecognizedText rt) {
  final angles = <double>[];
  for (final b in rt.blocks) {
    for (final l in b.lines) {
      final c = l.cornerPoints;
      if (c.length == 4) {
        final w = math.sqrt((c[1].x - c[0].x) * (c[1].x - c[0].x) + (c[1].y - c[0].y) * (c[1].y - c[0].y));
        final h = math.sqrt((c[3].x - c[0].x) * (c[3].x - c[0].x) + (c[3].y - c[0].y) * (c[3].y - c[0].y));
        if (h > 0 && w > 3 * h) angles.add(math.atan2(c[1].y - c[0].y, c[1].x - c[0].x));
      }
    }
  }
  angles.sort();
  final a = angles.isEmpty ? 0.0 : angles[angles.length ~/ 2];
  final toks = <_Tok>[];
  for (final b in rt.blocks) {
    for (final l in b.lines) {
      for (final e in l.elements) {
        var t = en(e.text).replaceAll(RegExp(r'[,،٬./\s]'), '');
        if (!RegExp(r'[0-9]').hasMatch(t)) continue;
        t = t.replaceAll(RegExp(r'[Oo]'), '0').replaceAll(RegExp(r'[lI|]'), '1');
        if (!RegExp(r'^[0-9]+$').hasMatch(t)) continue;
        final r = e.boundingBox;
        final cx = r.center.dx, cy = r.center.dy;
        toks.add(_Tok(t, cx * math.cos(a) + cy * math.sin(a), -cx * math.sin(a) + cy * math.cos(a), r.height));
      }
    }
  }
  if (toks.isEmpty) return [];
  final hs = toks.map((t) => t.h).toList()..sort();
  final thr = hs[hs.length ~/ 2] * 0.7;
  toks.sort((p, q) => p.y.compareTo(q.y));
  final groups = <List<_Tok>>[];
  var avg = 0.0;
  for (final t in toks) {
    if (groups.isEmpty || (t.y - avg).abs() > thr) {
      groups.add([t]);
      avg = t.y;
    } else {
      groups.last.add(t);
      avg = groups.last.fold<double>(0, (s, e) => s + e.y) / groups.last.length;
    }
  }
  final rows = <WRow>[];
  for (final g in groups) {
    if (g.length < 5) continue;
    g.sort((p, q) => q.x.compareTo(p.x));
    final n = g.length;
    final i = (g[0].t.length <= 3 && (int.tryParse(g[0].t) ?? 999) <= 300) ? 1 : 0;
    var q = int.tryParse(g[n - 3].t) ?? 0, pr = int.tryParse(g[n - 2].t) ?? 0;
    final tot = int.tryParse(g[n - 1].t) ?? 0;
    var ok = q > 0 && pr > 0 && q * pr == tot;
    var note = '';
    if (!ok && tot > 0) {
      if (pr > 0 && tot % pr == 0 && tot ~/ pr < 100000) {
        q = tot ~/ pr;
        note = 'تعداد از روی مبلغ اصلاح شد';
      } else if (q > 0 && tot % q == 0) {
        pr = tot ~/ q;
        note = 'قیمت از روی مبلغ اصلاح شد';
      } else {
        note = 'تعداد × قیمت با مبلغ نمی‌خواند';
      }
    }
    rows.add(WRow(code: g[i].t, qty: q, price: pr, ok: ok, note: note));
  }
  return rows;
}

class WholesalePage extends StatefulWidget {
  const WholesalePage({super.key});
  @override
  State<WholesalePage> createState() => _WholesaleState();
}

class _WholesaleState extends State<WholesalePage> {
  final rows = <WRow>[];
  bool busy = false, rial = true, updBuy = true, updSell = true;
  String? info;

  Future<void> pickPhoto(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src, maxWidth: 2800, imageQuality: 92);
    if (x == null) return;
    setState(() {
      busy = true;
      info = null;
    });
    try {
      final rec = TextRecognizer();
      final res = await rec.processImage(InputImage.fromFilePath(x.path));
      await rec.close();
      final r = parseWholesale(res);
      if (!mounted) return;
      setState(() {
        rows.addAll(r);
        info = r.isEmpty ? 'ردیفی خوانده نشد. عکس را صاف‌تر، نزدیک‌تر و با نور بهتر بگیرید، یا ردیف‌ها را دستی اضافه کنید.' : 'ردیف‌های خوانده‌شده را با کاغذ مقایسه کنید.';
      });
    } catch (e) {
      if (mounted) setState(() => info = 'خواندن عکس ناموفق بود: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> edit(WRow r, {bool isNew = false}) async {
    final cC = TextEditingController(text: fa(r.code));
    final nC = TextEditingController(text: r.name);
    final qC = TextEditingController(text: r.qty == 0 ? '' : fa('${r.qty}'));
    final pC = TextEditingController(text: r.price == 0 ? '' : fa('${r.price}'));
    final act = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isNew ? 'ردیف جدید' : 'ویرایش ردیف'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: cC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'کد کالا')),
            TextField(controller: nC, decoration: const InputDecoration(labelText: 'نام (فقط برای کالای جدید)')),
            TextField(controller: qC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'تعداد')),
            TextField(controller: pC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: rial ? 'قیمت واحد (ریال، مطابق فاکتور)' : 'قیمت واحد (تومان)')),
          ]),
        ),
        actions: [
          if (!isNew) TextButton(onPressed: () => Navigator.pop(ctx, 'del'), child: const Text('حذف', style: TextStyle(color: Colors.red))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'ok'), child: const Text('ذخیره')),
        ],
      ),
    );
    if (act == null) return;
    setState(() {
      if (act == 'del') {
        rows.remove(r);
        return;
      }
      r.code = en(cC.text).trim();
      r.name = nC.text.trim();
      r.qty = pInt(qC.text);
      r.price = pInt(pC.text);
      r.ok = true;
      r.note = '';
      if (isNew) rows.add(r);
    });
  }

  int get sumQty => rows.where((r) => r.use).fold<int>(0, (a, r) => a + r.qty);
  int get sumAmt => rows.where((r) => r.use).fold<int>(0, (a, r) => a + r.qty * r.price);

  Future<void> apply() async {
    final use = rows.where((r) => r.use && r.qty > 0 && r.code.isNotEmpty).toList();
    if (use.isEmpty) {
      snack(context, 'ردیفی برای ثبت نیست');
      return;
    }
    for (final r in use) {
      if (r.match == null && r.name.isEmpty) {
        snack(context, 'برای کالای جدید با کد ${fa(r.code)} نام بنویسید (ردیف را لمس کنید)');
        return;
      }
    }
    var created = 0;
    for (final r in use) {
      final buy = rial ? r.price ~/ 10 : r.price;
      final p = r.match;
      if (p != null) {
        p.qty += r.qty;
        if (updBuy && buy > 0 && buy != p.buy) {
          p.buy = buy;
          if (updSell) p.sell = round100(buy * (1 + p.profit / 100));
          p.record();
        }
      } else {
        final np = Product(id: '${DateTime.now().millisecondsSinceEpoch}_$created', name: r.name, code: r.code, buy: buy, sell: buy > 0 ? round100(buy * 1.2) : 0, qty: r.qty);
        np.record();
        items.add(np);
        created++;
      }
    }
    await saveDb();
    if (!mounted) return;
    snack(context, '${fa('${use.length}')} ردیف ثبت شد${created > 0 ? ' (${fa('$created')} کالای جدید)' : ''}');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اسکن فاکتور عمده‌فروش')),
      body: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(8), children: [
            const Text('از فاکتور کاغذی عکس صاف و واضح بگیرید (کل جدول داخل کادر، نور خوب). چند عکس پشت‌سرهم هم می‌شود. بعد از خواندن، همه‌چیز را بررسی کنید.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: FilledButton.icon(onPressed: busy ? null : () => pickPhoto(ImageSource.camera), icon: const Icon(Icons.photo_camera), label: const Text('دوربین'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.tonalIcon(onPressed: busy ? null : () => pickPhoto(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text('گالری'))),
            ]),
            if (busy) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: LinearProgressIndicator()),
            if (info != null) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(info!, style: const TextStyle(color: purple))),
            SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, value: rial, onChanged: (v) => setState(() => rial = v), title: const Text('مبالغ فاکتور ریال است (تقسیم بر ۱۰)')),
            SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, value: updBuy, onChanged: (v) => setState(() => updBuy = v), title: const Text('قیمت خرید کالاها به‌روز شود')),
            SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, value: updSell, onChanged: (v) => setState(() => updSell = v), title: const Text('قیمت فروش با درصد سود به‌روز شود')),
            for (final r in rows)
              Card(
                color: r.ok && r.match != null ? null : Colors.amber.shade50,
                child: ListTile(
                  leading: Checkbox(value: r.use, onChanged: (v) => setState(() => r.use = v ?? true)),
                  title: Text(r.match?.name ?? (r.name.isEmpty ? 'کالای جدید؛ نام را وارد کنید' : r.name)),
                  subtitle: Text('کد ${fa(r.code)} • ${fa('${r.qty}')} عدد × ${money(rial ? r.price ~/ 10 : r.price)} تومان${r.note.isEmpty ? '' : '\n${r.note}'}'),
                  trailing: Icon(r.match != null ? Icons.check_circle : Icons.fiber_new, color: r.match != null ? Colors.green : Colors.orange),
                  onTap: () => edit(r),
                ),
              ),
            TextButton.icon(onPressed: () => edit(WRow(), isNew: true), icon: const Icon(Icons.add), label: const Text('افزودن ردیف دستی')),
          ]),
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('جمع تعداد: ${fa('$sumQty')}   |   جمع مبلغ: ${money(sumAmt)} ${rial ? 'ریال' : 'تومان'}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: rows.isEmpty ? null : apply, child: const Text('تایید و افزودن به انبار'))),
          ]),
        ),
      ]),
    );
  }
}

// ---------------- Report ----------------
class ReportPage extends StatefulWidget {
  const ReportPage({super.key});
  @override
  State<ReportPage> createState() => _ReportState();
}

class _ReportState extends State<ReportPage> {
  int period = 0;
  DateTime? from() {
    final n = DateTime.now();
    final t = DateTime(n.year, n.month, n.day);
    if (period == 0) return t;
    if (period == 1) return t.subtract(const Duration(days: 6));
    if (period == 2) {
      final j = Jalali.fromDateTime(n);
      return Jalali(j.year, j.month, 1).toDateTime();
    }
    return null;
  }

  Widget box(String t, String v, Color c) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [Expanded(child: Text(t)), Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c))]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final f = from();
    final l = invoices.where((v) => !v.voided && (f == null || !v.date.isBefore(f))).toList();
    final sales = l.fold<int>(0, (a, v) => a + v.total);
    final profit = l.fold<int>(0, (a, v) => a + v.profit);
    final debt = l.fold<int>(0, (a, v) => a + v.debt);
    final sold = <String, int>{};
    for (final v in l) {
      for (final x in v.lines) {
        sold[x['name']] = (sold[x['name']] ?? 0) + (x['q'] as int);
      }
    }
    final top = sold.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    const names = ['امروز', '۷ روز اخیر', 'این ماه', 'همه'];
    return Scaffold(
      appBar: AppBar(title: const Text('گزارش فروش')),
      body: ListView(padding: const EdgeInsets.all(8), children: [
        Wrap(spacing: 8, children: [for (var i = 0; i < 4; i++) ChoiceChip(label: Text(names[i]), selected: period == i, onSelected: (_) => setState(() => period = i))]),
        const SizedBox(height: 8),
        box('تعداد فاکتور', fa('${l.length}'), Colors.black87),
        box('جمع فروش', '${money(sales)} تومان', purple),
        box('سود تقریبی', '${money(profit)} تومان', Colors.green.shade700),
        box('مانده‌ی نسیه', '${money(debt)} تومان', debt > 0 ? Colors.red : Colors.black87),
        const Padding(padding: EdgeInsets.fromLTRB(8, 4, 8, 0), child: Text('سود فقط برای کالاهایی حساب می‌شود که قیمت خرید دارند.', style: TextStyle(fontSize: 11, color: Colors.black54))),
        const SizedBox(height: 6),
        Card(child: ListTile(leading: const Icon(Icons.bar_chart, color: purple), title: const Text('فروش ماهانه (نمودار)'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MonthlyPage())))),
        Card(child: ListTile(leading: const Icon(Icons.trending_up, color: purple), title: const Text('سود هر کالا'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfitPage())))),
        Card(child: ListTile(leading: const Icon(Icons.inventory, color: purple), title: const Text('کالاهای راکد'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DeadStockPage())))),
        if (top.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.fromLTRB(8, 14, 8, 4), child: Text('پرفروش‌ترین‌ها', style: TextStyle(fontWeight: FontWeight.bold))),
          for (final e in top.take(5)) Card(child: ListTile(dense: true, title: Text(e.key), trailing: Text('${fa('${e.value}')} عدد'))),
        ],
      ]),
    );
  }
}

// ---------------- Debtors ----------------
class DebtPage extends StatefulWidget {
  const DebtPage({super.key});
  @override
  State<DebtPage> createState() => _DebtState();
}

class _DebtState extends State<DebtPage> {
  @override
  Widget build(BuildContext context) {
    final l = invoices.where((v) => v.debt > 0).toList()..sort((a, b) => a.date.compareTo(b.date));
    final total = l.fold<int>(0, (a, v) => a + v.debt);
    return Scaffold(
      appBar: AppBar(title: const Text('بدهکاران')),
      body: Column(children: [
        Card(child: ListTile(title: const Text('جمع مطالبات'), trailing: Text('${money(total)} تومان', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)))),
        Expanded(
          child: l.isEmpty
              ? const Center(child: Text('بدهکاری وجود ندارد'))
              : ListView(children: [
                  for (final v in l)
                    Card(
                      child: ListTile(
                        title: Text(v.customer.isEmpty ? 'بدون نام' : v.customer),
                        subtitle: Text('فاکتور ${fa('${v.no}')} • ${shamsi(v.date)}${v.phone.isNotEmpty ? ' • ${fa(v.phone)}' : ''}'),
                        trailing: Text(money(v.debt), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                        onTap: () async {
                          await payDialog(context, v);
                          setState(() {});
                        },
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}

// ---------------- Price list (image / PDF) ----------------
class PriceListPage extends StatefulWidget {
  final List<Product> list;
  const PriceListPage(this.list, {super.key});
  @override
  State<PriceListPage> createState() => _PLState();
}

class _PLState extends State<PriceListPage> {
  static const per = 28;
  late final sorted = [...widget.list]..sort((a, b) => a.name.compareTo(b.name));
  late final chunks = [for (var i = 0; i < sorted.length; i += per) sorted.sublist(i, i + per > sorted.length ? sorted.length : i + per)];
  late final keys = List.generate(chunks.length, (_) => GlobalKey());

  Future<void> savePdf() async {
    final b = await pdfOfKeys(keys);
    await Printing.layoutPdf(onLayout: (_) async => b, name: 'price-list');
  }

  Future<void> sharePdf() async {
    final b = await pdfOfKeys(keys);
    await Printing.sharePdf(bytes: b, filename: 'price-list.pdf');
  }

  Future<void> shareImg() async {
    final tmp = await getTemporaryDirectory();
    final files = <XFile>[];
    for (var i = 0; i < keys.length; i++) {
      final png = await pngOf(await capture(keys[i]));
      final f = File('${tmp.path}/price-list-${i + 1}.png');
      await f.writeAsBytes(png);
      files.add(XFile(f.path));
    }
    await Share.shareXFiles(files);
  }

  Widget chunk(int i) => Material(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (i == 0) ...[
              Row(children: [
                if (st.logo != null) ...[logoImg(56), const SizedBox(width: 10)],
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(st.shop, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: purple)),
                  Text('لیست قیمت — ${shamsi(DateTime.now())}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ])),
              ]),
              const Divider(height: 18, thickness: 2, color: purple),
            ],
            for (var k = 0; k < chunks[i].length; k++)
              Container(
                color: k.isEven ? const Color(0xFFF6F2F9) : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
                child: Row(children: [
                  Expanded(child: Text(chunks[i][k].name, style: const TextStyle(fontSize: 13, color: Colors.black87))),
                  Text('${money(chunks[i][k].sell)} تومان', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                ]),
              ),
            if (i == chunks.length - 1 && st.phone.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text('تلفن: ${fa(st.phone)}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.black54))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('لیست قیمت')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < chunks.length; i++) Padding(padding: const EdgeInsets.only(bottom: 8), child: RepaintBoundary(key: keys[i], child: chunk(i))),
          ]),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(child: FilledButton.icon(onPressed: () => guard(context, savePdf), icon: const Icon(Icons.picture_as_pdf), label: const Text('ذخیره PDF'))),
              const SizedBox(width: 6),
              Expanded(child: FilledButton.tonalIcon(onPressed: () => guard(context, sharePdf), icon: const Icon(Icons.share), label: const Text('PDF'))),
              const SizedBox(width: 6),
              Expanded(child: FilledButton.tonalIcon(onPressed: () => guard(context, shareImg), icon: const Icon(Icons.image), label: const Text('عکس'))),
            ]),
          ),
        ),
      );
}


// ---------------- Help ----------------
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});
  static const items2 = [
    ['شروع سریع', 'ابتدا از «تنظیمات» نام فروشگاه، تلفن، آدرس و لوگوی خودتان را وارد کنید؛ همه‌ی فاکتورها و لیست قیمت‌ها با همین اطلاعات ساخته می‌شوند. بعد کالاهایتان را ثبت کنید.'],
    ['ثبت کالا', 'دکمه‌ی + (یا اسکن بارکدِ کالای جدید) صفحه‌ی ثبت را باز می‌کند. نام، کد، بارکد، قیمت خرید، درصد سود و موجودی را بنویسید. قیمت فروش خودکار از قیمت خرید و درصد سود حساب می‌شود، ولی می‌توانید دستی تغییرش دهید. عکس کالا را هم با دوربین یا از گالری اضافه کنید.'],
    ['اسکن بارکد', 'دکمه‌ی بزرگ دوربین، بارکد را می‌خواند. اگر کالا ثبت شده باشد قیمت و موجودی‌اش را بزرگ نشان می‌دهد و اگر نه، صفحه‌ی ثبت کالای جدید باز می‌شود. برای جای کم‌نور از دکمه‌ی فلش بالای صفحه‌ی اسکن استفاده کنید. اگر بارکد خراب بود، «تایپ دستی کد» را بزنید.'],
    ['رنگ‌های لیست', 'نقطه‌ی کنار هر کالا نشان می‌دهد قیمتش چند وقت پیش عوض شده: سبز تازه، نارنجی بعد از ۱۴ روز و قرمز بعد از ۳۰ روز. موجودی قرمز یعنی کمتر از حد هشدار (در تنظیمات قابل تغییر است).'],
    ['تغییر قیمت گروهی', 'دکمه‌ی فلشِ بالای صفحه: برای همه‌ی کالاها یا فقط کالاهای انتخاب‌شده درصد افزایش یا کاهش می‌زند. برای انتخاب چند کالا، انگشت را روی آن‌ها نگه دارید.'],
    ['فروش و فاکتور', 'از «فروش جدید» کالاها را با اسکن یا از لیست اضافه کنید، تعداد را تنظیم کنید و در صورت نیاز قیمت یا تخفیف را عوض کنید. نحوه‌ی پرداخت (نقد، کارت، نسیه) را انتخاب و «ثبت فاکتور» را بزنید؛ موجودی کالاها خودکار کم می‌شود. فاکتور را می‌توانید PDF کنید یا برای مشتری بفرستید.'],
    ['نسیه و بدهکاران', 'در فروش نسیه، نام مشتری لازم است و می‌توانید پیش‌پرداخت بگیرید. در صفحه‌ی «بدهکاران» با لمس هر مورد، پرداخت‌های بعدی را ثبت کنید.'],
    ['ابطال فاکتور', 'داخل فاکتور، دکمه‌ی فلش برگشت: کالاها به موجودی برمی‌گردند و فاکتور از گزارش و بدهی‌ها حذف می‌شود.'],
    ['ورود کالا', 'وقتی جنس جدید می‌خرید، از «ورود کالا» آن را اسکن کنید، تعداد و قیمت خرید جدید را بزنید تا موجودی زیاد و در صورت تمایل قیمت فروش به‌روز شود.'],
    ['گزارش', 'فروش، سود تقریبی، مانده‌ی نسیه و پرفروش‌ترین کالاها برای امروز، ۷ روز اخیر، این ماه و کل. از همین صفحه نمودار فروش ماهانه، سود هر کالا و کالاهای راکد را هم می‌بینید. سود فقط برای کالاهایی حساب می‌شود که قیمت خرید دارند.'],
    ['لیست قیمت برای مشتری', 'دکمه‌ی اشتراک بالای صفحه‌ی اصلی: ارسال به‌صورت متن، یا «لیست قیمت مرتب» با لوگو و تاریخ که به‌صورت PDF یا عکس ذخیره و ارسال می‌شود.'],
    ['مشتریان', 'از «مشتریان» نام و تلفن هر مشتری را نگه دارید. مشتری‌هایی که در فروش اسمشان را می‌نویسید خودکار اضافه می‌شوند. داخل هر مشتری، تاریخچه‌ی خرید و مانده‌ی بدهی دیده می‌شود و با «ثبت دریافتی» پول گرفته‌شده از قدیمی‌ترین بدهی کم می‌شود.'],
    ['اسکن فاکتور عمده‌فروش', 'در «ورود کالا» دکمه‌ی «اسکن فاکتور عمده‌فروش» را بزنید و از فاکتور کاغذی عکس بگیرید (صاف، واضح و با نور خوب). برنامه کد، تعداد و قیمت هر ردیف را می‌خواند و شما قبل از ثبت همه را بررسی و اصلاح می‌کنید. جمع تعداد و مبلغ پایین صفحه را با جمع کاغذ مقایسه کنید.'],
    ['اکسل (ورود و خروج)', 'در صفحه‌ی «اکسل» می‌توانید کالاها و فاکتورها را به‌صورت فایل CSV (قابل باز شدن در اکسل) بگیرید. برای وارد کردن کالاها، اول «فایل نمونه» را بگیرید، در اکسل پر کنید، به‌صورت CSV ذخیره کنید (ترجیحاً CSV UTF-8) و با «ورود کالا از فایل» انتخابش کنید. کالاهایی که بارکد، کد یا نامشان تکراری باشد به‌روز می‌شوند.'],
    ['جست‌وجو، مرتب‌سازی و دسته‌بندی', 'زیر کادر جست‌وجو می‌توانید لیست را مرتب کنید (ارزان‌ترین، گران‌ترین، کم‌موجودترین، قدیمی‌ترین قیمت) و فقط کالاهای کم‌موجود، قیمت‌قدیمی یا یک دسته را ببینید. دسته‌ی هر کالا را هنگام ثبت یا ویرایش می‌نویسید.'],
    ['قفل برنامه', 'از تنظیمات می‌توانید رمز (حروف و عدد، با هر طول دلخواه، حداقل ۴ کاراکتر) بگذارید. برنامه بعد از ورود و همچنین وقتی بیش از یک دقیقه بیرون از آن بوده‌اید، رمز می‌خواهد. رمز را فراموش نکنید؛ بدون آن فقط با پاک کردن برنامه و بازگردانی پشتیبانِ بدون رمز وارد می‌شوید.'],
    ['پشتیبان‌گیری (مهم)', 'همه‌ی اطلاعات فقط روی همین گوشی ذخیره است و جای دیگری ارسال نمی‌شود؛ پس اگر گوشی گم یا خراب شود یا برنامه پاک شود، اطلاعات از بین می‌رود. مرتب از «تنظیمات ← گرفتن پشتیبان» یک فایل بگیرید و در تلگرام، Google Drive یا کامپیوتر نگه دارید. برای انتقال به گوشی جدید از «بازگردانی» استفاده کنید.'],
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('راهنمای برنامه')),
        body: ListView(padding: const EdgeInsets.all(8), children: [
          Center(child: Padding(padding: const EdgeInsets.all(12), child: Image.asset('assets/logo.png', height: 90))),
          const Center(child: Text('نسخه‌ی ۱٫۱٫۰', style: TextStyle(color: Colors.black54))),
          const SizedBox(height: 8),
          for (final e in items2) Card(child: ExpansionTile(title: Text(e[0], style: const TextStyle(fontWeight: FontWeight.bold)), childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14), expandedCrossAxisAlignment: CrossAxisAlignment.start, children: [Text(e[1], style: const TextStyle(height: 1.7))])),
        ]),
      );
}


// ---------------- Customers ----------------
Future<bool> custDialog(BuildContext context, [Customer? c]) async {
  final n = TextEditingController(text: c?.name ?? '');
  final ph = TextEditingController(text: c?.phone ?? '');
  final nt = TextEditingController(text: c?.note ?? '');
  final r = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(c == null ? 'مشتری جدید' : 'ویرایش مشتری'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: n, decoration: const InputDecoration(labelText: 'نام')),
        TextField(controller: ph, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'تلفن')),
        TextField(controller: nt, decoration: const InputDecoration(labelText: 'یادداشت')),
      ]),
      actions: [
        if (c != null) TextButton(onPressed: () => Navigator.pop(context, 'del'), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(context, 'ok'), child: const Text('ذخیره')),
      ],
    ),
  );
  if (r == 'del' && c != null) {
    customers.remove(c);
    await saveCust();
    return true;
  }
  if (r == 'ok' && n.text.trim().isNotEmpty) {
    final name = n.text.trim();
    if (c == null) {
      customers.add(Customer(id: '${DateTime.now().millisecondsSinceEpoch}', name: name, phone: en(ph.text).trim(), note: nt.text.trim()));
    } else {
      final old = c.name.trim();
      c.name = name;
      c.phone = en(ph.text).trim();
      c.note = nt.text.trim();
      if (old != name) {
        final dupOld = customers.any((x) => x != c && x.name.trim() == old);
        for (final v in invoices) {
          if (v.cid == c.id || (v.cid.isEmpty && !dupOld && v.customer.trim() == old)) {
            v.customer = name;
            v.cid = c.id;
          }
        }
        await saveInv();
      }
    }
    await saveCust();
    return true;
  }
  return false;
}

class CustomersPage extends StatefulWidget {
  final bool pick;
  const CustomersPage({super.key, this.pick = false});
  @override
  State<CustomersPage> createState() => _CustState();
}

class _CustState extends State<CustomersPage> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final k = norm(q);
    final l = customers.where((c) => k.isEmpty || norm(c.name).contains(k) || c.phone.contains(k)).toList()..sort((a, b) => a.name.compareTo(b.name));
    return Scaffold(
      appBar: AppBar(title: Text(widget.pick ? 'انتخاب مشتری' : 'مشتریان')),
      floatingActionButton: FloatingActionButton(onPressed: () async { if (await custDialog(context)) setState(() {}); }, child: const Icon(Icons.person_add)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(decoration: InputDecoration(hintText: 'جست‌وجوی نام یا تلفن', prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), onChanged: (v) => setState(() => q = v)),
        ),
        Expanded(
          child: l.isEmpty
              ? const Center(child: Text('مشتری‌ای ثبت نشده'))
              : ListView(padding: const EdgeInsets.only(bottom: 80), children: [
                  for (final c in l)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text(c.name.isEmpty ? '?' : c.name[0])),
                        title: Text(c.name),
                        subtitle: Text('${c.phone.isEmpty ? '' : '${fa(c.phone)} • '}خرید: ${money(boughtOf(c))}'),
                        trailing: debtOf(c) > 0 ? Text(money(debtOf(c)), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)) : null,
                        onTap: () async {
                          if (widget.pick) {
                            Navigator.pop(context, c);
                          } else {
                            await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerPage(c)));
                            setState(() {});
                          }
                        },
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}

class CustomerPage extends StatefulWidget {
  final Customer c;
  const CustomerPage(this.c, {super.key});
  @override
  State<CustomerPage> createState() => _CustDetailState();
}

class _CustDetailState extends State<CustomerPage> {
  Future<void> receive() async {
    final c = widget.c;
    final t = TextEditingController(text: fa('${debtOf(c)}'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('دریافتی از ${c.name}'),
        content: TextField(controller: t, keyboardType: TextInputType.number, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ثبت')),
        ],
      ),
    );
    if (ok != true) return;
    var left = pInt(t.text);
    final l = invOf(c).where((v) => v.debt > 0).toList()..sort((a, b) => a.date.compareTo(b.date));
    for (final v in l) {
      if (left <= 0) break;
      final a = left > v.debt ? v.debt : left;
      v.paid += a;
      v.pays.add({'d': DateTime.now().toIso8601String(), 'a': a});
      left -= a;
    }
    await saveInv();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final l = invOf(c)..sort((a, b) => b.date.compareTo(a.date));
    final debt = debtOf(c);
    return Scaffold(
      appBar: AppBar(title: Text(c.name), actions: [
        IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () async {
            if (await custDialog(context, c)) {
              if (!mounted) return;
              if (!customers.contains(c)) {
                Navigator.pop(context);
              } else {
                setState(() {});
              }
            }
          },
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(8), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (c.phone.isNotEmpty) Text('تلفن: ${fa(c.phone)}'),
              if (c.note.isNotEmpty) Text('یادداشت: ${c.note}'),
              const SizedBox(height: 6),
              Text('جمع خرید: ${money(boughtOf(c))} تومان', style: const TextStyle(fontSize: 16)),
              Text('مانده‌ی بدهی: ${money(debt)} تومان', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: debt > 0 ? Colors.red : Colors.green)),
            ]),
          ),
        ),
        if (debt > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: FilledButton.icon(onPressed: receive, icon: const Icon(Icons.payments), label: const Text('ثبت دریافتی از مشتری'))),
        const Padding(padding: EdgeInsets.fromLTRB(8, 12, 8, 4), child: Text('فاکتورها', style: TextStyle(fontWeight: FontWeight.bold))),
        if (l.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('هنوز فاکتوری ندارد')),
        for (final v in l)
          Card(
            child: ListTile(
              title: Text('فاکتور ${fa('${v.no}')} — ${shamsi(v.date)}${v.voided ? ' (باطل)' : ''}'),
              subtitle: v.debt > 0 ? Text('مانده ${money(v.debt)}', style: TextStyle(color: Colors.orange.shade800)) : null,
              trailing: Text('${money(v.total)} تومان', style: TextStyle(fontWeight: FontWeight.bold, decoration: v.voided ? TextDecoration.lineThrough : null)),
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => InvoicePage(v)));
                if (mounted) setState(() {});
              },
            ),
          ),
      ]),
    );
  }
}

// ---------------- Excel / CSV ----------------
class ExcelPage extends StatefulWidget {
  const ExcelPage({super.key});
  @override
  State<ExcelPage> createState() => _ExcelState();
}

class _ExcelState extends State<ExcelPage> {
  Future<void> shareCsv(String name, List<List<String>> rows) async {
    final sb = StringBuffer('\uFEFF');
    for (final r in rows) {
      sb.writeln(r.map(csvCell).join(','));
    }
    final tmp = await getTemporaryDirectory();
    final f = File('${tmp.path}/$name');
    await f.writeAsString(sb.toString());
    await Share.shareXFiles([XFile(f.path)]);
  }

  static const head = ['نام', 'کد', 'بارکد', 'دسته', 'قیمت خرید', 'درصد سود', 'قیمت فروش', 'موجودی'];

  Future<void> exportProducts() => shareCsv('asia-products.csv', [
        head,
        for (final p in items) [p.name, p.code, p.barcode.isEmpty ? '' : '="${p.barcode}"', p.cat, '${p.buy}', '${p.profit}', '${p.sell}', '${p.qty}'],
      ]);

  Future<void> exportTemplate() => shareCsv('asia-template.csv', [
        head,
        ['کابل شارژ نمونه', '1001', '="6260000000001"', 'کابل', '100000', '20', '120000', '10'],
      ]);

  Future<void> exportInvoices() => shareCsv('asia-invoices.csv', [
        ['شماره', 'تاریخ', 'مشتری', 'تلفن', 'پرداخت', 'جمع', 'تخفیف', 'مبلغ نهایی', 'مانده', 'وضعیت'],
        for (final v in invoices) ['${v.no}', en(shamsi(v.date)), v.customer, v.phone, v.pay == 'cash' ? 'نقد' : v.pay == 'card' ? 'کارت' : 'نسیه', '${v.sum}', '${v.discount}', '${v.total}', '${v.debt}', v.voided ? 'باطل' : 'عادی'],
      ]);

  Future<void> importProducts() async {
    final x = await openFile();
    if (x == null) return;
    var text = utf8.decode(await x.readAsBytes(), allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    if (!mounted) return;
    if (text.contains('\uFFFD')) {
      snack(context, 'فایل UTF-8 نیست. در اکسل با Save As گزینه‌ی «CSV UTF-8» را انتخاب کنید.');
      return;
    }
    final first = text.split('\n').first;
    final d = [',', ';', '\t'].reduce((a, b) => first.split(a).length >= first.split(b).length ? a : b);
    final rows = parseCsv(text, d);
    if (!mounted) return;
    if (rows.length < 2) {
      snack(context, 'فایل خالی است یا خوانده نشد');
      return;
    }
    final hd = rows.first.map(hn).toList();
    int col(List<String> names) {
      for (final n in names) {
        final i = hd.indexOf(hn(n));
        if (i >= 0) return i;
      }
      return -1;
    }
    final cName = col(['نام', 'نام کالا', 'name', 'کالا', 'title']);
    final cCode = col(['کد', 'code']);
    final cBar = col(['بارکد', 'barcode']);
    final cCat = col(['دسته', 'دسته‌بندی', 'category']);
    final cBuy = col(['قیمت خرید', 'خرید', 'buy', 'cost']);
    final cProf = col(['درصد سود', 'سود', 'profit']);
    final cSell = col(['قیمت فروش', 'فروش', 'قیمت', 'price', 'sell']);
    final cQty = col(['موجودی', 'تعداد', 'qty', 'stock']);
    if (cName < 0) {
      snack(context, 'ستون «نام» پیدا نشد. ردیف اول فایل باید عنوان ستون‌ها باشد.');
      return;
    }
    String get(List<String> r, int c) => c >= 0 && c < r.length ? cleanCell(r[c]) : '';
    final data = <List<String>>[];
    var skip = 0;
    for (final r in rows.skip(1)) {
      if (get(r, cName).isEmpty) {
        skip++;
        continue;
      }
      data.add([get(r, cName), get(r, cCode), get(r, cBar), get(r, cCat), get(r, cBuy), get(r, cProf), get(r, cSell), get(r, cQty)]);
    }
    Product? find(List<String> m) {
      if (m[2].isNotEmpty) {
        final p = items.where((e) => e.barcode == m[2]).firstOrNull;
        if (p != null) return p;
      }
      if (m[1].isNotEmpty) {
        final p = items.where((e) => e.code == en(m[1])).firstOrNull;
        if (p != null) return p;
      }
      return items.where((e) => e.name == m[0]).firstOrNull;
    }
    final newCount = data.where((m) => find(m) == null).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ورود کالا از فایل'),
        content: Text('${fa('${data.length}')} ردیف خوانده شد:\n${fa('$newCount')} کالای جدید\n${fa('${data.length - newCount}')} کالای موجود که به‌روز می‌شود\n${fa('$skip')} ردیف بدون نام (نادیده گرفته می‌شود)\n\nپیشنهاد: اول از تنظیمات پشتیبان بگیرید.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('وارد کن')),
        ],
      ),
    );
    if (ok != true) return;
    var i = 0;
    for (final m in data) {
      var p = find(m);
      final isNew = p == null;
      p ??= Product(id: '${DateTime.now().microsecondsSinceEpoch}${i++}');
      final oldSell = p.sell, oldBuy = p.buy;
      p.name = m[0];
      if (cCode >= 0 && m[1].isNotEmpty) p.code = en(m[1]);
      if (cBar >= 0 && m[2].isNotEmpty) p.barcode = m[2];
      if (cCat >= 0 && m[3].isNotEmpty) p.cat = m[3];
      if (cBuy >= 0 && m[4].isNotEmpty) p.buy = pMoney(m[4]);
      if (cProf >= 0 && m[5].isNotEmpty) p.profit = pDbl(m[5]);
      if (cQty >= 0 && m[7].isNotEmpty) p.qty = pMoney(m[7]);
      if (cSell >= 0 && m[6].isNotEmpty) {
        p.sell = pMoney(m[6]);
      } else if (isNew && p.buy > 0) {
        p.sell = round100(p.buy * (1 + p.profit / 100));
      }
      if (isNew || p.sell != oldSell || p.buy != oldBuy) p.record();
      if (isNew) items.add(p);
    }
    await saveDb();
    if (mounted) snack(context, '${fa('$newCount')} کالای جدید و ${fa('${data.length - newCount}')} به‌روزرسانی انجام شد');
  }

  Widget tile(IconData i, String t, String sub, Future<void> Function() f) => Card(
        child: ListTile(leading: Icon(i, color: purple), title: Text(t), subtitle: Text(sub), onTap: () => guard(context, f)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('اکسل (CSV)')),
        body: ListView(padding: const EdgeInsets.all(8), children: [
          tile(Icons.file_upload, 'خروجی کالاها', 'فایل CSV از همه‌ی کالاها (قابل باز شدن در اکسل)', exportProducts),
          tile(Icons.receipt, 'خروجی فاکتورها', 'فهرست فاکتورها با جمع، تخفیف و مانده', exportInvoices),
          tile(Icons.description, 'فایل نمونه برای ورود', 'یک فایل با عنوان ستون‌ها و یک ردیف نمونه', exportTemplate),
          tile(Icons.file_download, 'ورود کالا از فایل', 'کالاهای فایل CSV را اضافه یا به‌روز می‌کند', importProducts),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'راهنما: ردیف اول فایل باید عنوان ستون‌ها باشد (نام، کد، بارکد، دسته، قیمت خرید، درصد سود، قیمت فروش، موجودی). فقط ستون «نام» الزامی است. کالایی که بارکد، کد یا نامش در برنامه باشد به‌روز می‌شود و در غیر این صورت اضافه می‌شود. فایل اکسل را با Save As به‌صورت «CSV UTF-8» ذخیره کنید. اگر بارکدها در اکسل به شکل 1.2E+12 درآمدند، ستون بارکد را قبل از وارد کردن اعداد روی حالت Text بگذارید.',
              style: TextStyle(height: 1.7, fontSize: 13),
            ),
          ),
        ]),
      );
}

// ---------------- Analysis ----------------
const _mn = ['فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', 'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'];
int _daysAgo(DateTime d) => DateTime.now().difference(d).inDays;

class MonthlyPage extends StatelessWidget {
  const MonthlyPage({super.key});
  @override
  Widget build(BuildContext context) {
    final now = Jalali.now();
    final keys = <List<int>>[];
    for (var i = 11; i >= 0; i--) {
      var m = now.month - i, y = now.year;
      while (m < 1) {
        m += 12;
        y--;
      }
      keys.add([y, m]);
    }
    final sales = <String, int>{}, prof = <String, int>{}, cnt = <String, int>{};
    for (final v in invoices) {
      if (v.voided) continue;
      final j = Jalali.fromDateTime(v.date);
      final k = '${j.year}-${j.month}';
      sales[k] = (sales[k] ?? 0) + v.total;
      prof[k] = (prof[k] ?? 0) + v.profit;
      cnt[k] = (cnt[k] ?? 0) + 1;
    }
    String kk(List<int> k) => '${k[0]}-${k[1]}';
    int pos(int? v) => (v ?? 0) < 0 ? 0 : (v ?? 0);
    var mx = 1;
    for (final k in keys) {
      if (pos(sales[kk(k)]) > mx) mx = pos(sales[kk(k)]);
    }
    Widget bar(int v, Color c) => Container(width: 9, height: 150.0 * v / mx, color: c);
    final rows = keys.reversed.where((k) => (cnt[kk(k)] ?? 0) > 0).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('فروش ماهانه')),
      body: ListView(padding: const EdgeInsets.all(8), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                Container(width: 12, height: 12, color: purple),
                const SizedBox(width: 4),
                const Text('فروش', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 14),
                Container(width: 12, height: 12, color: Colors.green),
                const SizedBox(width: 4),
                const Text('سود', style: TextStyle(fontSize: 12)),
                const Spacer(),
                Text('بیشترین: ${money(mx == 1 ? 0 : mx)}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ]),
              const SizedBox(height: 10),
              SizedBox(
                height: 150,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (final k in keys)
                    Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [bar(pos(sales[kk(k)]), purple), const SizedBox(width: 1), bar(pos(prof[kk(k)]), Colors.green)])),
                ]),
              ),
              const Divider(height: 6),
              Row(children: [for (final k in keys) Expanded(child: Text(fa('${k[1]}'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)))]),
              const Text('شماره‌ی ماه شمسی (۱۲ ماه اخیر)', style: TextStyle(fontSize: 10, color: Colors.black54)),
            ]),
          ),
        ),
        if (rows.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('هنوز فروشی ثبت نشده'))),
        for (final k in rows)
          Card(
            child: ListTile(
              title: Text('${_mn[k[1] - 1]} ${fa('${k[0]}')}'),
              subtitle: Text('${fa('${cnt[kk(k)]}')} فاکتور • سود ${money(prof[kk(k)] ?? 0)}'),
              trailing: Text('${money(sales[kk(k)] ?? 0)} تومان', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        const Padding(padding: EdgeInsets.all(8), child: Text('سود فقط برای کالاهایی حساب می‌شود که قیمت خرید دارند.', style: TextStyle(fontSize: 11, color: Colors.black54))),
      ]),
    );
  }
}

class ProfitPage extends StatefulWidget {
  const ProfitPage({super.key});
  @override
  State<ProfitPage> createState() => _ProfitState();
}

class _ProfitState extends State<ProfitPage> {
  int period = 1;
  @override
  Widget build(BuildContext context) {
    final n = DateTime.now();
    final j = Jalali.fromDateTime(n);
    final from = period == 0 ? Jalali(j.year, j.month, 1).toDateTime() : (period == 1 ? n.subtract(const Duration(days: 90)) : null);
    final qty = <String, int>{}, rev = <String, int>{}, pr = <String, int>{}, nm = <String, String>{};
    for (final v in invoices) {
      if (v.voided || (from != null && v.date.isBefore(from))) continue;
      for (final l in v.lines) {
        final k = '${l['id']}';
        final q = l['q'] as int, pz = l['p'] as int, b = (l['b'] ?? 0) as int;
        nm[k] = '${l['name']}';
        qty[k] = (qty[k] ?? 0) + q;
        rev[k] = (rev[k] ?? 0) + q * pz;
        if (b > 0) pr[k] = (pr[k] ?? 0) + (pz - b) * q;
      }
    }
    final ks = qty.keys.toList()..sort((a, b) => (pr[b] ?? 0).compareTo(pr[a] ?? 0));
    final total = pr.values.fold<int>(0, (a, b) => a + b);
    const names = ['این ماه', '۳ ماه اخیر', 'همه'];
    return Scaffold(
      appBar: AppBar(title: const Text('سود هر کالا')),
      body: ListView(padding: const EdgeInsets.all(8), children: [
        Wrap(spacing: 8, children: [for (var i = 0; i < 3; i++) ChoiceChip(label: Text(names[i]), selected: period == i, onSelected: (_) => setState(() => period = i))]),
        Card(child: ListTile(title: const Text('جمع سود کالاها'), trailing: Text('${money(total)} تومان', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.green.shade700)))),
        if (ks.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('در این بازه فروشی نیست'))),
        for (final k in ks)
          Card(
            child: ListTile(
              title: Text(nm[k]!),
              subtitle: Text('فروش ${fa('${qty[k]}')} عدد • ${money(rev[k] ?? 0)}'),
              trailing: pr[k] == null
                  ? const Text('بدون قیمت خرید', style: TextStyle(fontSize: 11, color: Colors.black54))
                  : Text(money(pr[k]!), style: TextStyle(fontWeight: FontWeight.bold, color: pr[k]! < 0 ? Colors.red : Colors.green.shade700)),
            ),
          ),
        const Padding(padding: EdgeInsets.all(8), child: Text('سود هر کالا بدون احتساب تخفیف فاکتور است.', style: TextStyle(fontSize: 11, color: Colors.black54))),
      ]),
    );
  }
}

class DeadStockPage extends StatefulWidget {
  const DeadStockPage({super.key});
  @override
  State<DeadStockPage> createState() => _DeadState();
}

class _DeadState extends State<DeadStockPage> {
  int days = 60;
  @override
  Widget build(BuildContext context) {
    final last = <String, DateTime>{};
    for (final v in invoices) {
      if (v.voided) continue;
      for (final l in v.lines) {
        final k = '${l['id']}';
        final d = last[k];
        if (d == null || v.date.isAfter(d)) last[k] = v.date;
      }
    }
    final dead = <Product>[];
    for (final p in items) {
      if (p.qty <= 0) continue;
      final ref = last[p.id] ?? (p.hist.isNotEmpty ? (DateTime.tryParse('${p.hist.first['d']}') ?? p.updated) : p.updated);
      if (_daysAgo(ref) >= days) dead.add(p);
    }
    dead.sort((a, b) => (b.buy * b.qty).compareTo(a.buy * a.qty));
    final val = dead.fold<int>(0, (a, p) => a + p.buy * p.qty);
    return Scaffold(
      appBar: AppBar(title: const Text('کالاهای راکد')),
      body: ListView(padding: const EdgeInsets.all(8), children: [
        Wrap(spacing: 8, children: [for (final d in const [30, 60, 90, 180]) ChoiceChip(label: Text('${fa('$d')} روز'), selected: days == d, onSelected: (_) => setState(() => days = d))]),
        Card(child: ListTile(title: Text('${fa('${dead.length}')} کالا بدون فروش در ${fa('$days')} روز اخیر'), subtitle: const Text('سرمایه‌ی خوابیده (به قیمت خرید)'), trailing: Text('${money(val)} تومان', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)))),
        if (dead.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('کالای راکدی نیست'))),
        for (final p in dead)
          Card(
            child: ListTile(
              title: Text(p.name),
              subtitle: Text('موجودی ${fa('${p.qty}')} • ${last[p.id] == null ? 'تا حالا فروش نرفته' : 'آخرین فروش ${fa('${_daysAgo(last[p.id]!)}')} روز پیش'}'),
              trailing: Text(money(p.buy * p.qty), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        const Padding(padding: EdgeInsets.all(8), child: Text('کالایی که هنوز فروخته نشده، از تاریخ ثبتش حساب می‌شود.', style: TextStyle(fontSize: 11, color: Colors.black54))),
      ]),
    );
  }
}

// ---------------- App lock ----------------
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});
  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool locked = st.pin != null;
  DateTime? left;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) left = DateTime.now();
    if (s == AppLifecycleState.resumed && st.pin != null && left != null && DateTime.now().difference(left!).inSeconds > 60) {
      setState(() => locked = true);
    }
  }
  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        widget.child,
        if (locked && st.pin != null) Positioned.fill(child: Overlay(initialEntries: [OverlayEntry(builder: (_) => PinPage(onOk: () => setState(() => locked = false)))])),
      ]);
}

class PinPage extends StatefulWidget {
  final VoidCallback onOk;
  const PinPage({super.key, required this.onOk});
  @override
  State<PinPage> createState() => _PinState();
}

class _PinState extends State<PinPage> {
  final c = TextEditingController();
  bool bad = false, show = false;
  void submit() {
    if (hashPin(en(c.text)) == st.pin) {
      widget.onOk();
    } else {
      setState(() {
        bad = true;
        c.clear();
      });
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Image.asset('assets/logo.png', height: 90),
                const SizedBox(height: 14),
                const Text('رمز برنامه را وارد کنید', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 14),
                TextField(
                  controller: c,
                  autofocus: true,
                  obscureText: !show,
                  textAlign: TextAlign.center,
                  onSubmitted: (_) => submit(),
                  onChanged: (_) {
                    if (bad) setState(() => bad = false);
                  },
                  decoration: InputDecoration(border: const OutlineInputBorder(), suffixIcon: IconButton(icon: Icon(show ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => show = !show))),
                ),
                SizedBox(height: 28, child: bad ? const Center(child: Text('رمز اشتباه است', style: TextStyle(color: Colors.red))) : null),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: FilledButton(onPressed: submit, child: const Padding(padding: EdgeInsets.all(8), child: Text('ورود', style: TextStyle(fontSize: 18))))),
              ]),
            ),
          ),
        ),
      );
}

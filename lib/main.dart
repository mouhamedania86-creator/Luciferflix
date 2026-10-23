import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'device.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'mini_player.dart';
import 'notifier.dart';
import 'onboarding_screen.dart';
import 'profile_screen.dart';
import 'store.dart';
import 'strings.dart';
import 'user_data.dart';

/// الأخطاء اللي وقعوا أثناء التهيئة (باش تبان للمستخدم بدل شاشة سوداء).
final List<String> initErrors = <String>[];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    debugPrint('FLUTTER ERROR >>> ${details.exception}\n${details.stack}');
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('UNCAUGHT ERROR >>> $error\n$stack');
    return true;
  };

  Future<void> step(String name, Future<void> Function() fn) async {
    try {
      await fn().timeout(const Duration(seconds: 15));
    } catch (e) {
      initErrors.add('$name → $e');
      debugPrint('INIT STEP "$name" FAILED >>> $e');
    }
  }

  await step('MediaKit', () async => MediaKit.ensureInitialized());
  await step('Device', Device.init);
  // لا ننتظر الشبكة قبل runApp؛ الإعدادات المحفوظة تظل متاحة في وضع الأوفلاين.
  await step('Strings', S.load);
  await step('Store', Store.load);
  await step('Notifier', Notifier.init);
  await step('UserData', () async {
    // نحمل البروفايل النشط ونقراه من التخزين
    final p = await SharedPreferences.getInstance();
    final active = p.getString('active_profile');
    if (active != null && active.isNotEmpty) {
      UD.activeProfile.value = active;
    }
  });

  runApp(const MyApp());
  unawaited(XtreamAPI.instance.load().timeout(const Duration(seconds: 3)).catchError((_) {}));
}

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: S.lang,
      builder: (context, lang, _) => MaterialApp(
        title: 'MovieFlix',
        debugShowCheckedModeBanner: false,
        scrollBehavior: const AppScrollBehavior(),
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF08090D),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE50914),
            brightness: Brightness.dark,
          ),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF08090D), surfaceTintColor: Colors.transparent, elevation: 0, centerTitle: false),
        ),
        builder: (context, child) => Directionality(
          textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          // المشغّل المصغّر يبقى فوق كل الشاشات (باش تشوف الفيديو وانت تتصفح)
          child: MiniPlayerHost(child: child!),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

int _compareVersions(String current, String latest) {
  List<int> parse(String value) => value.split('.').map((part) => int.tryParse(part) ?? 0).toList();
  final a = parse(current);
  final b = parse(latest);
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final av = i < a.length ? a[i] : 0;
    final bv = i < b.length ? b[i] : 0;
    if (av != bv) return av.compareTo(bv);
  }
  return 0;
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _showUpdate = false;
  String _updateUrl = '';

  @override
  void initState() {
    super.initState();
    _checkUpdate();
  }

  Future<void> _checkUpdate() async {
    try {
      // 👈 ضع رابط ملف server.json هنا
      const String configUrl = 'https://raw.githubusercontent.com/mouhamedania86-creator/Update/main/server.json';
      final res = await http.get(Uri.parse(configUrl)).timeout(const Duration(seconds: 1));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final bool forceUpdate = data['force_update'] ?? false;
        final String latestVersion = data['latest_version'] ?? '1.1.0';
        final String updateUrl = data['update_url'] ?? '';

        // الإصدار يُقرأ من pubspec.yaml عبر package_info_plus.
        final packageInfo = await PackageInfo.fromPlatform().timeout(const Duration(seconds: 1));
        final currentVersion = packageInfo.version;

        // 👈 إذا كان التحديث إجبارياً، والإصدار الحالي أقل من المطلوب
        if (forceUpdate && _compareVersions(currentVersion, latestVersion) < 0 && updateUrl.isNotEmpty) {
          setState(() {
            _showUpdate = true;
            _updateUrl = updateUrl;
          });
          return;
        }
      }
    } catch (_) {}

    // إذا لم يوجد تحديث، ننتقل للشاشة الرئيسية
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const OnboardingGate(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showUpdate) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.system_update, size: 80, color: Colors.orange),
                const SizedBox(height: 20),
                const Text('تحديث إجباري', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                const Text('يجب عليك تحديث التطبيق إلى الإصدار الجديد للاستمرار.', textAlign: TextAlign.center),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
                    onPressed: () {
                      launchUrl(Uri.parse(_updateUrl), mode: LaunchMode.externalApplication);
                    },
                    icon: const Icon(Icons.download),
                    label: const Text('تحميل التحديث الآن'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_circle_fill, size: 90, color: Color(0xFFE50914)),
              const SizedBox(height: 16),
              const Text('MovieFlix', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              if (initErrors.isNotEmpty) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x1AFF5252),
                    border: Border.all(color: Colors.redAccent),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      const Text('أخطاء التهيئة:',
                          style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      for (final e in initErrors)
                        Text(e,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// بوابة البروفايل: إذا كان البروفايل النشط مربوط بـ PIN نطلب الرمز قبل ما
/// ندخل للتطبيق (نفس فكرة قفل الأطفال في Netflix).
class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key});
  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    bool needsPin = false;
    try {
      needsPin = await UD.activeNeedsPin();
    } catch (_) {}
    if (!mounted) return;
    if (needsPin) {
      // شاشة اختيار البروفايل: تطلب الرمز السري قبل الدخول
      try {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const ProfileScreen(pickerMode: true),
        ));
      } catch (_) {}
      if (!mounted) return;
    }
    _openApp();
  }

  void _openApp() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => XtreamAPI.instance.isLoggedIn ? const HomeScreen() : const LoginScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF080808),
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

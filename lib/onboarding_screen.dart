import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';

/// يظهر مرة واحدة فقط على الجهاز، قبل تسجيل الدخول أو دخول الصفحة الرئيسية.
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key});
  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  bool _checking = true;
  bool _showIntro = false;

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('movieflix_onboarding_seen') ?? false;
    if (!mounted) return;
    if (seen) {
      _openApp();
    } else {
      setState(() { _checking = false; _showIntro = true; });
    }
  }

  void _openApp() {
    // نمرّ على بوابة البروفايل (قفل الأطفال) قبل الدخول للتطبيق
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => const ProfileGate(),
    ));
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('movieflix_onboarding_seen', true);
    if (mounted) _openApp();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking || !_showIntro) {
      return const Scaffold(backgroundColor: Color(0xFF080808), body: Center(child: CircularProgressIndicator()));
    }
    return _OnboardingScreen(onFinish: _finish);
  }
}

class _OnboardingScreen extends StatefulWidget {
  final Future<void> Function() onFinish;
  const _OnboardingScreen({required this.onFinish});
  @override
  State<_OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<_OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  static const _pages = <({IconData icon, String title, String body})>[
    (icon: Icons.local_movies_rounded, title: 'اكتشف عالم الأفلام', body: 'تصفّح الأفلام والمسلسلات في واجهة سينمائية سهلة وسريعة.'),
    (icon: Icons.bookmark_added_rounded, title: 'تابع من وين حبست', body: 'خلي أعمالك المفضلة في المتابعة والمفضلة وارجعلها وقت ما تحب.'),
    (icon: Icons.tv_rounded, title: 'تجربة على الهاتف والتلفاز', body: 'تنقّل بسهولة باللمس أو بالريموت على الشاشة الكبيرة.'),
  ];

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final current = _pages[_page];
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 22),
        child: Column(children: [
          Align(alignment: Alignment.centerRight, child: TextButton(
            onPressed: widget.onFinish,
            child: const Text('تخطي', style: TextStyle(color: Colors.white70, fontSize: 16)),
          )),
          Expanded(child: PageView.builder(
            controller: _controller,
            itemCount: _pages.length,
            onPageChanged: (value) => setState(() => _page = value),
            itemBuilder: (_, index) {
              final page = _pages[index];
              return AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: Column(
                key: ValueKey(index), mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(width: 190, height: 190,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [const Color(0xFFE50914).withOpacity(.35), Colors.transparent])),
                    child: Icon(page.icon, size: 100, color: const Color(0xFFE50914))),
                  const SizedBox(height: 34),
                  Text(page.title, textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 14),
                  Text(page.body, textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, height: 1.6, color: Colors.white70)),
                ],
              ));
            },
          )),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(_pages.length, (i) => AnimatedContainer(
            duration: const Duration(milliseconds: 200), margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == _page ? 24 : 8, height: 8,
            decoration: BoxDecoration(color: i == _page ? const Color(0xFFE50914) : Colors.white30, borderRadius: BorderRadius.circular(8)),
          ))),
          const SizedBox(height: 26),
          SizedBox(width: double.infinity, height: 52, child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE50914), foregroundColor: Colors.white),
            onPressed: () {
              if (_page < _pages.length - 1) {
                _controller.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
              } else {
                widget.onFinish();
              }
            },
            child: Text(_page == _pages.length - 1 ? 'ابدأ المشاهدة' : 'التالي', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          )),
        ]),
      )),
    );
  }
}

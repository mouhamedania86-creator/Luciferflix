import 'package:flutter/material.dart';

import 'api.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'strings.dart';
import 'user_data.dart';
import 'widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  String? _error;
  List<Profile> _profiles = [];
  String? _activeId;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    final p = await UD.profiles();
    if (!mounted) return;
    setState(() {
      _profiles = p;
      _activeId = UD.activeProfile.value;
    });
  }

  Future<void> _switchProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen(pickerMode: true)),
    );
    await _loadProfiles();
  }

  Future<void> _login() async {
    if (_server.text.trim().isEmpty ||
        _user.text.trim().isEmpty ||
        _pass.text.trim().isEmpty) {
      setState(() => _error = 'fill_all');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await XtreamAPI.instance.login(
      _server.text,
      _user.text,
      _pass.text,
    );
    if (!mounted) return;
    if (err == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      setState(() {
        _loading = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _profiles.where((p) => p.id == _activeId).toList();
    final activeProfile = active.isEmpty ? null : active.first;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: loginInset(context),
              vertical: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.play_circle_fill,
                  size: 72,
                  color: Color(0xFFE50914),
                ),
                const SizedBox(height: 8),
                const Text(
                  'MovieFlix',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),

                // 👈 البروفايل النشط
                if (activeProfile != null) ...[
                  const SizedBox(height: 18),
                  InkWell(
                    onTap: _switchProfile,
                    borderRadius: BorderRadius.circular(10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          activeProfile.avatar,
                          style: const TextStyle(fontSize: 26),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          activeProfile.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.swap_horiz,
                          size: 18,
                          color: Colors.white54,
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                TextField(
                  controller: _server,
                  keyboardType: TextInputType.url,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: S.t('login_server'),
                    hintText: 'http://example.com:8080',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _user,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: S.t('login_user'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: S.t('login_pass'),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      S.t(_error!),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(S.t('login')),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  S.t('own_account'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'my_list_screen.dart';
import 'notifier.dart';
import 'profile_screen.dart';
import 'stats_screen.dart';
import 'store.dart';
import 'strings.dart';
import 'user_data.dart';
import 'widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final api = XtreamAPI.instance;
  String _tmdb = '';
  Profile _profile = const Profile(
    id: UD.defaultId,
    name: 'MovieFlix',
    avatar: '👤',
  );
  final Map<String, bool> _flags = {
    'kidsMode': false,
    'dataSaver': false,
    'hideWatched': false,
    'autoNext': true,
  };

  @override
  void initState() {
    super.initState();
    _loadKey();
    _loadProfile();
    _loadFlags();
  }

  Future<void> _loadKey() async {
    final k = await Store.tmdbKey();
    if (mounted) setState(() => _tmdb = k);
  }

  Future<void> _loadProfile() async {
    final p = await UD.activeProfileObj();
    if (mounted) setState(() => _profile = p);
  }

  Future<void> _loadFlags() async {
    final s = await UD.settings();
    if (!mounted) return;
    setState(() {
      for (final k in _flags.keys) {
        final v = s[k];
        if (v is bool) _flags[k] = v;
      }
    });
  }

  Future<void> _setFlag(String key, bool value) async {
    setState(() => _flags[key] = value);
    await UD.setSetting(key, value);
  }

  Future<void> _pickLanguage() async {
    final nav = Navigator.of(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(S.t('choose_language')),
        children: S.supported.entries
            .map(
              (e) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, e.key),
                child: Text(e.value, style: const TextStyle(fontSize: 16)),
              ),
            )
            .toList(),
      ),
    );
    if (choice == null || choice == S.lang.value) return;
    await S.setLang(choice);
    // نعاود بناء التطبيق باش كل الشاشات تاخذ اللغة الجديدة
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (r) => false,
    );
  }

  Future<void> _editTmdb() async {
    final ctrl = TextEditingController(text: _tmdb);
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('tmdb_key')),
        content: TextField(
          controller: ctrl,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(hintText: S.t('tmdb_hint')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.t('save')),
          ),
        ],
      ),
    );
    if (saved == true) {
      await Store.setTmdbKey(ctrl.text);
      await _loadKey();
      messenger.showSnackBar(SnackBar(content: Text(S.t('tmdb_saved'))));
    }
  }

  void _about() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('MovieFlix'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${S.t('version')} 1.1.0'),
            const SizedBox(height: 10),
            Text(S.t('about_text')),
            const SizedBox(height: 10),
            Text(
              S.t('tmdb_credit'),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _openInstagram() async {
    await launchUrl(
      Uri.parse('https://www.instagram.com/sxnaxke'),
      mode: LaunchMode.externalApplication,
    );
  }

  // ====== نسخ احتياطي ======

  Future<void> _exportData() async {
    final json = await UD.exportJson();
    try {
      await Clipboard.setData(ClipboardData(text: json));
    } catch (_) {}
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('export_data')),
        content: SizedBox(
          width: 420,
          height: 320,
          child: SingleChildScrollView(child: SelectableText(json)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.t('save')),
          ),
        ],
      ),
    );
  }

  Future<void> _importData() async {
    final ctrl = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('import_data')),
        content: TextField(
          controller: ctrl,
          maxLines: 8,
          minLines: 5,
          style: const TextStyle(fontSize: 11),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.t('save')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = await UD.importJson(ctrl.text.trim());
    messenger.showSnackBar(
      SnackBar(content: Text(done ? S.t('import_done') : S.t('import_failed'))),
    );
    if (done) {
      await _loadFlags();
      await _loadProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('settings'))),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: pageInset(context)),
        children: [
          // ====== البروفايل ======
          ListTile(
            leading: Text(_profile.avatar, style: const TextStyle(fontSize: 26)),
            title: Text(S.t('active_profile')),
            subtitle: Text(_profile.name),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
              await _loadProfile();
            },
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: Text(S.t('switch_profile')),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProfileScreen(pickerMode: true),
                ),
              );
              await _loadProfile();
            },
          ),
          ListTile(
            leading: const Icon(Icons.dns),
            title: Text(S.t('server')),
            subtitle: Text(api.server, textDirection: TextDirection.ltr),
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: Text(S.t('account')),
            subtitle: Text(api.username, textDirection: TextDirection.ltr),
          ),

          const Divider(),

          ListTile(
            leading: const Icon(Icons.playlist_add_check),
            title: Text(S.t('my_list')),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyListScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.query_stats),
            title: Text(S.t('my_stats')),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StatsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(S.t('language')),
            subtitle: Text(S.supported[S.lang.value] ?? ''),
            onTap: _pickLanguage,
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('سجل المشاهدة'),
            subtitle: const Text('استكمال المحتوى أو إزالة عناصر من السجل'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.event_available),
            title: Text(S.t('tmdb_key')),
            subtitle: Text(_tmdb.isEmpty ? S.t('tmdb_hint') : '••••••••'),
            onTap: _editTmdb,
          ),

          const Divider(),

          // ====== الرقابة parental ======
          ListTile(
            leading: const Icon(Icons.child_care),
            title: Text(S.t('parental_control')),
            subtitle: Text(S.t('kids_mode_desc')),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const _ParentalScreen()),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.family_restroom),
            value: _flags['kidsMode'] ?? false,
            onChanged: (v) => _setFlag('kidsMode', v),
            title: Text(S.t('kids_mode')),
            subtitle: Text(S.t('kids_mode_desc')),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.data_saver_on),
            value: _flags['dataSaver'] ?? false,
            onChanged: (v) => _setFlag('dataSaver', v),
            title: Text(S.t('data_saver')),
            subtitle: Text(S.t('data_saver_desc')),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off),
            value: _flags['hideWatched'] ?? false,
            onChanged: (v) => _setFlag('hideWatched', v),
            title: Text(S.t('hide_watched')),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.skip_next),
            value: _flags['autoNext'] ?? true,
            onChanged: (v) => _setFlag('autoNext', v),
            title: Text(S.t('auto_next')),
          ),

          const Divider(),

          // ====== نسخ احتياطي ======
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: Text(S.t('export_data')),
            onTap: _exportData,
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: Text(S.t('import_data')),
            onTap: _importData,
          ),

          const Divider(),

          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(S.t('about')),
            onTap: _about,
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(S.t('developer')),
            subtitle: const Text('sxnaxke'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: _openInstagram,
          ),

          const Divider(),

          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(S.t('clear_data')),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              for (final r in await Store.reminders()) {
                await Notifier.cancel(r.id);
              }
              await Store.clearUserData();
              await UD.clearAll();
              await _loadFlags();
              messenger.showSnackBar(SnackBar(content: Text(S.t('cleared'))));
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: Text(
              S.t('logout'),
              style: const TextStyle(color: Colors.redAccent),
            ),
            onTap: () async {
              final nav = Navigator.of(context);
              await api.logout();
              nav.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// ====== الرقابة parental: منع فئات معيّنة ======

class _ParentalScreen extends StatefulWidget {
  const _ParentalScreen();

  @override
  State<_ParentalScreen> createState() => _ParentalScreenState();
}

class _ParentalScreenState extends State<_ParentalScreen> {
  final api = XtreamAPI.instance;
  List<dynamic> _vodCats = [], _liveCats = [];
  Set<String> _blocked = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await api.getCategories('vod');
    final l = await api.getCategories('live');
    final b = await UD.blockedCategories();
    if (!mounted) return;
    setState(() {
      _vodCats = v;
      _liveCats = l;
      _blocked = b;
      _loading = false;
    });
  }

  void _toggle(String id) {
    setState(() {
      if (_blocked.contains(id)) {
        _blocked.remove(id);
      } else {
        _blocked.add(id);
      }
    });
    UD.setBlockedCategories(_blocked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('parental_control'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Text(
                    S.t('kids_mode_desc'),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
                if (_vodCats.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      S.t('movies'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                for (final c in _vodCats)
                  CheckboxListTile(
                    dense: true,
                    value: _blocked.contains('${c['category_id']}'),
                    onChanged: (_) => _toggle('${c['category_id']}'),
                    title: Text('${c['category_name'] ?? ''}'),
                  ),
                if (_liveCats.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      S.t('live'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                for (final c in _liveCats)
                  CheckboxListTile(
                    dense: true,
                    value: _blocked.contains('${c['category_id']}'),
                    onChanged: (_) => _toggle('${c['category_id']}'),
                    title: Text('${c['category_name'] ?? ''}'),
                  ),
                const SizedBox(height: 20),
              ],
            ),
    );
  }
}

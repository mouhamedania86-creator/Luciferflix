import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ===== نموذج البروفايل =====
class Profile {
  static String? _decodePin(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    // Backward compatibility: old versions stored PIN as int, losing leading zeros.
    if (value is int && raw.length < 4) return raw.padLeft(4, '0');
    return raw;
  }

  final String id;
  final String name;
  final String avatar;
  final bool isKid;
  final String? pin;

  const Profile({
    required this.id,
    required this.name,
    required this.avatar,
    this.isKid = false,
    this.pin,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatar': avatar,
        'isKid': isKid,
        'pin': pin,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        avatar: (j['avatar'] ?? '🙂').toString(),
        isKid: j['isKid'] == true,
        pin: _decodePin(j['pin']),
      );

  Profile copyWith({
    String? name,
    String? avatar,
    bool? isKid,
    String? pin,
    bool clearPin = false,
  }) =>
      Profile(
        id: id,
        name: name ?? this.name,
        avatar: avatar ?? this.avatar,
        isKid: isKid ?? this.isKid,
        pin: clearPin ? null : (pin ?? this.pin),
      );
}

/// مدى تخطي المقدمة (بالثواني).
class SkipRange {
  final int start;
  final int end;
  const SkipRange(this.start, this.end);

  Map<String, dynamic> toJson() => {'start': start, 'end': end};
  factory SkipRange.fromJson(Map<String, dynamic> j) => SkipRange(
        (j['start'] ?? 0) as int,
        (j['end'] ?? 0) as int,
      );
}

/// إحصائيات المشاهدة المحسوبة من السجل المحلي.
class WatchStats {
  final int totalMinutes;
  final int movies;
  final int series;
  final int live;
  final int episodes;
  final List<Map<String, dynamic>> topItems;
  final List<int> perDay;

  const WatchStats({
    required this.totalMinutes,
    required this.movies,
    required this.series,
    required this.live,
    required this.episodes,
    required this.topItems,
    required this.perDay,
  });

  static const empty = WatchStats(
    totalMinutes: 0,
    movies: 0,
    series: 0,
    live: 0,
    episodes: 0,
    topItems: [],
    perDay: [],
  );
}

/// ===== طبقة بيانات المستخدم =====
class UD {
  UD._();

  static const String defaultId = 'default';

  static final ValueNotifier<String> activeProfile =
      ValueNotifier<String>(defaultId);
  static final ValueNotifier<int> myListVersion = ValueNotifier<int>(0);
  static final ValueNotifier<int> settingsVersion = ValueNotifier<int>(0);
  static final ValueNotifier<int> profilesVersion = ValueNotifier<int>(0);

  static String _k(String key) => '$key::${activeProfile.value}';

  // ---------------- البروفايلات ----------------

  static Future<List<Profile>> profiles() async {
    final p = await SharedPreferences.getInstance();
    final out = <Profile>[];
    for (final s in p.getStringList('profiles') ?? <String>[]) {
      try {
        // 🔸- إصلاح: Map<String, dynamic>.from
        out.add(Profile.fromJson(
          Map<String, dynamic>.from(jsonDecode(s) as Map),
        ));
      } catch (_) {}
    }
    if (out.isEmpty) {
      out.add(const Profile(
        id: defaultId,
        name: 'MovieFlix',
        avatar: '👤',
      ));
    }
    return out;
  }

  static Future<void> _saveProfiles(List<Profile> l) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
        'profiles', l.map((e) => jsonEncode(e.toJson())).toList());
    profilesVersion.value++;
  }

  static Future<Profile> activeProfileObj() async {
    final all = await profiles();
    final id = activeProfile.value;
    for (final x in all) {
      if (x.id == id) return x;
    }
    return all.first;
  }

  static Future<void> setActive(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('active_profile', id);
    activeProfile.value = id;
    myListVersion.value++;
    settingsVersion.value++;
  }

  static Future<Profile> createProfile({
    required String name,
    String avatar = '🙂',
    bool isKid = false,
    String? pin,
  }) async {
    final all = await profiles();
    final id = 'p${DateTime.now().millisecondsSinceEpoch}';
    final prof = Profile(
      id: id,
      name: name.trim().isEmpty ? 'Profile' : name.trim(),
      avatar: avatar,
      isKid: isKid,
      pin: pin != null && pin.trim().isNotEmpty ? pin.trim() : null,
    );
    all.add(prof);
    await _saveProfiles(all);
    return prof;
  }

  static Future<bool> updateProfile(Profile prof) async {
    final all = await profiles();
    final i = all.indexWhere((e) => e.id == prof.id);
    if (i < 0) return false;
    all[i] = prof;
    await _saveProfiles(all);
    return true;
  }

  static Future<bool> deleteProfile(String id) async {
    if (id == defaultId) return false;
    final all = await profiles();
    all.removeWhere((e) => e.id == id);
    await _saveProfiles(all);
    final p = await SharedPreferences.getInstance();
    for (final k in p.getKeys().toList()) {
      if (k.endsWith('::$id')) await p.remove(k);
    }
    if (activeProfile.value == id) await setActive(defaultId);
    return true;
  }

  static Future<bool> verifyPin(String id, String pin) async {
    final all = await profiles();
    for (final x in all) {
      if (x.id == id) {
        if (x.pin == null) return true;
        return '${x.pin}' == pin.trim();
      }
    }
    return false;
  }

  static Future<bool> activeNeedsPin() async {
    final p = await activeProfileObj();
    return p.pin != null;
  }

  // ---------------- قائمتي (My List) ----------------

  static Future<List<Map<String, dynamic>>> myList() async {
    final p = await SharedPreferences.getInstance();
    final out = <Map<String, dynamic>>[];
    for (final s in p.getStringList(_k('my_list')) ?? <String>[]) {
      try {
        out.add(Map<String, dynamic>.from(jsonDecode(s) as Map));
      } catch (_) {}
    }
    return out;
  }

  static Future<bool> inMyList(String type, String id) async {
    for (final e in await myList()) {
      if ((e['_type'] ?? '') == type &&
          '${e['stream_id'] ?? e['series_id'] ?? ''}' == id) {
        return true;
      }
    }
    return false;
  }

  static Future<bool> toggleMyList(String type, dynamic item) async {
    final p = await SharedPreferences.getInstance();
    final list = await myList();
    final id = (type == 'series'
            ? (item as Map)['series_id']
            : (item as Map)['stream_id'])
        .toString();
    final i = list.indexWhere((e) =>
        (e['_type'] ?? '') == type &&
        '${e['stream_id'] ?? e['series_id'] ?? ''}' == id);
    if (i >= 0) {
      list.removeAt(i);
    } else {
      list.insert(
          0, {...Map<String, dynamic>.from(item as Map), '_type': type});
    }
    await p.setStringList(_k('my_list'),
        list.take(200).map((e) => jsonEncode(e)).toList());
    myListVersion.value++;
    return i < 0;
  }

  // ---------------- التقييمات ----------------

  static Future<Map<String, int>> _ratings() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k('ratings'));
    if (raw == null || raw.isEmpty) return {};
    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        return j.map(
            (k, v) => MapEntry(k.toString(), int.tryParse('$v') ?? 0));
      }
    } catch (_) {}
    return {};
  }

  static Future<int?> rating(String type, String id) async =>
      (await _ratings())['$type::$id'];

  static Future<bool> setRating(String type, String id, int value) async {
    final p = await SharedPreferences.getInstance();
    final r = await _ratings();
    final key = '$type::$id';
    final changed = r[key] != value;
    r[key] = value;
    await p.setString(_k('ratings'), jsonEncode(r));
    return changed;
  }

  static Future<void> clearRating(String type, String id) async {
    final p = await SharedPreferences.getInstance();
    final r = await _ratings();
    r.remove('$type::$id');
    await p.setString(_k('ratings'), jsonEncode(r));
  }

  // ---------------- تخطي المقدمة / النهاية ----------------

  static Future<Map<String, dynamic>> _skipIntroMap() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k('skip_intro'));
    if (raw == null || raw.isEmpty) return {};
    try {
      final j = jsonDecode(raw);
      return j is Map ? Map<String, dynamic>.from(j) : {};
    } catch (_) {
      return {};
    }
  }

  static Future<SkipRange?> skipIntro(String seriesId) async {
    final m = await _skipIntroMap();
    final v = m[seriesId];
    if (v == null) return null;
    try {
      return SkipRange.fromJson(Map<String, dynamic>.from(v as Map));
    } catch (_) {
      return null;
    }
  }

  static Future<void> setSkipIntro(
      String seriesId, int startSec, int endSec) async {
    final p = await SharedPreferences.getInstance();
    final m = await _skipIntroMap();
    m[seriesId] = SkipRange(startSec, endSec).toJson();
    await p.setString(_k('skip_intro'), jsonEncode(m));
  }

  static Future<void> clearSkipIntro(String seriesId) async {
    final p = await SharedPreferences.getInstance();
    final m = await _skipIntroMap();
    m.remove(seriesId);
    await p.setString(_k('skip_intro'), jsonEncode(m));
  }

  static Future<int?> skipCreditsStart(String seriesId) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k('skip_credits'));
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        final v = j[seriesId];
        return v == null ? null : int.tryParse('$v');
      }
    } catch (_) {}
    return null;
  }

  static Future<void> setSkipCreditsStart(String seriesId, int sec) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k('skip_credits'));
    Map<String, dynamic> m = {};
    if (raw != null && raw.isNotEmpty) {
      try {
        final j = jsonDecode(raw);
        if (j is Map) m = Map<String, dynamic>.from(j);
      } catch (_) {}
    }
    m[seriesId] = sec;
    await p.setString(_k('skip_credits'), jsonEncode(m));
  }

  // ---------------- الرقابة parental ----------------

  static Future<Set<String>> blockedCategories() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_k('blocked_cats')) ?? <String>[]).toSet();
  }

  static Future<void> setBlockedCategories(Set<String> ids) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_k('blocked_cats'), ids.toList());
    settingsVersion.value++;
  }

  static Future<bool> isBlockedCategory(String id) async =>
      (await blockedCategories()).contains(id);

  // ---------------- إعدادات العرض ----------------

  static const Map<String, dynamic> _defaultSettings = {
    'hideWatched': false,
    'dataSaver': false,
    'autoNext': true,
    'kidsMode': false,
    'showTrailers': true,
  };

  static Future<Map<String, dynamic>> settings() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k('settings'));
    final out = Map<String, dynamic>.from(_defaultSettings);
    if (raw != null && raw.isNotEmpty) {
      try {
        final j = jsonDecode(raw);
        if (j is Map) {
          j.forEach((k, v) => out[k.toString()] = v);
        }
      } catch (_) {}
    }
    return out;
  }

  static Future<bool> getBool(String key, {bool def = false}) async {
    final s = await settings();
    final v = s[key];
    if (v is bool) return v;
    return def;
  }

  static Future<void> setSetting(String key, dynamic value) async {
    final p = await SharedPreferences.getInstance();
    final s = await settings();
    s[key] = value;
    await p.setString(_k('settings'), jsonEncode(s));
    settingsVersion.value++;
  }

  // ---------------- عدّاد التشغيل ----------------

  static Future<void> bumpPlayCount(
      String type, String id, String title) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('play_counts');
    Map<String, dynamic> m = {};
    if (raw != null && raw.isNotEmpty) {
      try {
        final j = jsonDecode(raw);
        if (j is Map) m = Map<String, dynamic>.from(j);
      } catch (_) {}
    }
    final key = '$type::$id';
    final cur = m[key];
    final int prev = (cur is Map) ? ((cur['count'] as int?) ?? 0) : 0;
    m[key] = {
      'type': type,
      'id': id,
      'title': title,
      'count': prev + 1,
    };
    await p.setString('play_counts', jsonEncode(m));
  }

  static Future<List<Map<String, dynamic>>> playCounts() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('play_counts');
    final out = <Map<String, dynamic>>[];
    if (raw == null || raw.isEmpty) return out;
    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        j.forEach((k, v) {
          if (v is Map) {
            out.add({
              'key': k.toString(),
              'type': (v['type'] ?? 'vod').toString(),
              'id': (v['id'] ?? '').toString(),
              'title': (v['title'] ?? '').toString(),
              'count': (v['count'] ?? 0) as int,
            });
          }
        });
      }
    } catch (_) {}
    out.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
    return out;
  }

  // ---------------- إحصائيات ----------------

  static Future<WatchStats> stats() async {
    final p = await SharedPreferences.getInstance();
    final entries = <Map<String, dynamic>>[];
    for (final s in p.getStringList('history') ?? <String>[]) {
      try {
        entries.add(Map<String, dynamic>.from(jsonDecode(s) as Map));
      } catch (_) {}
    }
    if (entries.isEmpty) return WatchStats.empty;

    var total = 0, movies = 0, series = 0, live = 0, episodes = 0;
    final perTitle = <String, Map<String, dynamic>>{};
    final days = List<int>.filled(7, 0);
    final now = DateTime.now();

    for (final e in entries) {
      final pos = int.tryParse('${e['pos'] ?? 0}') ?? 0;
      final dur = int.tryParse('${e['dur'] ?? 0}') ?? 0;
      final type = (e['type'] ?? 'vod').toString();
      final title = (e['title'] ?? '').toString();
      final ts = int.tryParse('${e['ts'] ?? 0}') ?? 0;
      final isDone = e['done'] == true;

      final watchedSec =
          isDone && dur > 0 ? dur : (dur > 0 ? pos.clamp(0, dur) : 0);
      final mins = (watchedSec / 60).round();
      total += mins;

      if (type == 'series') {
        series++;
        episodes++;
      } else if (type == 'live') {
        live++;
      } else {
        movies++;
      }

      final key =
          '$type::${e['item'] is Map ? ((e['item'] as Map)['series_id'] ?? (e['item'] as Map)['stream_id'] ?? title) : title}';
      final cur = perTitle[key];
      if (cur == null) {
        perTitle[key] = {
          'title': title,
          'type': type,
          'count': 1,
          'minutes': mins,
        };
      } else {
        cur['count'] = (cur['count'] as int) + 1;
        cur['minutes'] = (cur['minutes'] as int) + mins;
      }

      if (ts > 0) {
        final d = DateTime.fromMillisecondsSinceEpoch(ts);
        final diff = DateTime(now.year, now.month, now.day)
            .difference(DateTime(d.year, d.month, d.day))
            .inDays;
        if (diff >= 0 && diff < 7) days[6 - diff] += mins;
      }
    }

    final top = perTitle.values.toList()
      ..sort((a, b) => (b['minutes'] as int).compareTo(a['minutes'] as int));

    return WatchStats(
      totalMinutes: total,
      movies: movies,
      series: series,
      live: live,
      episodes: episodes,
      topItems: top.take(10).toList(),
      perDay: days,
    );
  }

  // ---------------- نسخ احتياطي ----------------

  static Future<String> exportJson() async {
    final p = await SharedPreferences.getInstance();
    final data = <String, dynamic>{};
    for (final k in p.getKeys()) {
      final v = p.get(k);
      if (v is String) {
        data[k] = v;
      } else if (v is List) {
        data[k] = v;
      }
    }
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'movieflix',
      'version': 2,
      'exported_at': DateTime.now().toIso8601String(),
      'data': data,
    });
  }

  static Future<bool> importJson(String raw) async {
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return false;
      final data = j['data'];
      if (data is! Map) return false;
      final p = await SharedPreferences.getInstance();
      // 🔸- حلقة for بدل forEach (forEach مع async لا ينتظر)
      for (final entry in data.entries) {
        final k = entry.key.toString();
        final v = entry.value;
        if (v is String) {
          await p.setString(k, v);
        } else if (v is List && v.every((e) => e is String)) {
          await p.setStringList(k, List<String>.from(v));
        } else if (v is bool) {
          await p.setBool(k, v);
        } else if (v is int) {
          await p.setInt(k, v);
        } else if (v is double) {
          await p.setDouble(k, v);
        }
      }
      myListVersion.value++;
      settingsVersion.value++;
      profilesVersion.value++;
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clearAll() async {
    final p = await SharedPreferences.getInstance();
    for (final k in p.getKeys().toList()) {
      if (k.startsWith('my_list::') ||
          k.startsWith('ratings::') ||
          k.startsWith('skip_intro::') ||
          k.startsWith('skip_credits::') ||
          k.startsWith('blocked_cats::') ||
          k.startsWith('settings::') ||
          k == 'play_counts') {
        await p.remove(k);
      }
    }
    myListVersion.value++;
    settingsVersion.value++;
  }
}
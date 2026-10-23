import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'user_data.dart';

/// توصيات محلية (من غير سيرفر): "لأنك شفت X" + Top 10.
class Recommend {
  Recommend._();

  /// عناصر مشابهة لمن شاهده المستخدم: نفس الفئة (category_id) أو نفس النوع.
  ///
  /// [watchedKeys] مفاتيح من الشكل `vod_123` / `series_456` (نفس `WatchEntry.key`).
  static List<Map<String, dynamic>> becauseYouWatched({
    required List<dynamic> allItems,
    required Set<String> watchedKeys,
    String type = 'vod',
    int limit = 20,
  }) {
    // 1) اجمع الفئات الأكثر مشاهدة
    final catScore = <String, int>{};
    for (final it in allItems) {
      final m = Map<String, dynamic>.from(it as Map);
      final key = '${type}_${_idOf(m, type)}';
      if (watchedKeys.contains(key)) {
        final cat = '${m['category_id'] ?? ''}';
        catScore[cat] = (catScore[cat] ?? 0) + 1;
      }
    }
    if (catScore.isEmpty) return const [];

    // 2) رتّب العناصر حسب نقاط الفئة، مع تفضيل الأحدث
    final scored = <MapEntry<Map<String, dynamic>, int>>[];
    for (final it in allItems) {
      final m = Map<String, dynamic>.from(it as Map);
      final key = '${type}_${_idOf(m, type)}';
      if (watchedKeys.contains(key)) continue;
      final cat = '${m['category_id'] ?? ''}';
      final base = catScore[cat] ?? 0;
      if (base == 0) continue;
      final added = _int(m['added']);
      scored.add(MapEntry(m, base * 100000 + added));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));

    return scored
        .take(limit)
        .map((e) => {...e.key, '_type': type})
        .toList(growable: false);
  }

  /// Top 10 من عدّاد التشغيل المحلي.
  static List<Map<String, dynamic>> top10FromCounts(
    List<Map<String, dynamic>> counts, {
    int limit = 10,
  }) {
    return counts.take(limit).toList(growable: false);
  }

  /// أكثر الفئات مشاهدة (للاستعمال في "الأكثر مشاهدة حسب الفئة").
  static List<Map<String, String>> topCategories({
    required List<dynamic> allItems,
    required Set<String> watchedKeys,
    String type = 'vod',
    int limit = 8,
  }) {
    final score = <String, int>{};
    for (final it in allItems) {
      final m = Map<String, dynamic>.from(it as Map);
      final key = '${type}_${_idOf(m, type)}';
      if (!watchedKeys.contains(key)) continue;
      final cat = '${m['category_id'] ?? ''}';
      if (cat.isEmpty) continue;
      score[cat] = (score[cat] ?? 0) + 1;
    }
    final entries = score.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .take(limit)
        .map((e) => MapEntry(e.key, e.value.toString()))
        .toList(growable: false);
  }

  /// يجمع مفاتيح ما تم مشاهدته من سجل المشاهدة الحالي.
  static Set<String> watchedKeysFrom(List<Map<String, dynamic>> history) {
    final out = <String>{};
    for (final e in history) {
      final type = (e['type'] ?? 'vod').toString();
      final item = e['item'];
      final id = item is Map
          ? (type == 'series'
              ? (item['series_id'] ?? '')
              : (item['stream_id'] ?? ''))
          : '';
      out.add('${type}_$id');
    }
    return out;
  }

  /// نجمع سجل المشاهدة بصيغة خرائط (نفس المفتاح 'history' اللي تكتبه Store).
  static Future<List<Map<String, dynamic>>> rawHistory() async {
    final p = await SharedPreferences.getInstance();
    final out = <Map<String, dynamic>>[];
    for (final s in p.getStringList('history') ?? <String>[]) {
      try {
        out.add(Map<String, dynamic>.from(jsonDecode(s) as Map));
      } catch (_) {}
    }
    return out;
  }

  static String _idOf(Map<String, dynamic> m, String type) =>
      (type == 'series' ? m['series_id'] : m['stream_id']).toString();

  static int _int(dynamic v) {
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }
}

/// مساعدة: نجمع مفاتيح ما تم مشاهدته (نسخة top-level للتوافق).
Set<String> watchedKeysFrom(List<Map<String, dynamic>> history) =>
    Recommend.watchedKeysFrom(history);

/// مساعدة: نجمع سجل المشاهدة (نسخة top-level للتوافق).
Future<List<Map<String, dynamic>>> rawHistory() => Recommend.rawHistory();

/// إعدادات سريعة: هل المستخدم طلب إخفاء ما شاهده؟
Future<bool> hideWatchedEnabled() => UD.getBool('hideWatched');

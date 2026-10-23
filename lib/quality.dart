import 'dart:convert';

/// خيارات الجودة (multi-stream) لسيرفرات Xtream.
///
/// أغلب البانلات ترجّع أكثر من ستريم لنفس الفيلم: mp4 / mkv / ts، وأحياناً
/// 4K. هنا نحوّلهم لبطاقات مفهومة للمستخدم.
class QualityOption {
  final String id; // stream_id
  final String ext; // container_extension
  final String label; // 4K / FHD / HD / SD
  final int? width;
  final int? height;
  final int? bitrate;

  const QualityOption({
    required this.id,
    required this.ext,
    required this.label,
    this.width,
    this.height,
    this.bitrate,
  });

  String get resolution =>
      (width != null && height != null) ? '${width}x$height' : label;

  Map<String, dynamic> toJson() => {
        'id': id,
        'ext': ext,
        'label': label,
        'width': width,
        'height': height,
        'bitrate': bitrate,
      };
}

class Quality {
  Quality._();

  /// يحوّل ستريمات Xtream إلى خيارات جودة مرتبة من الأعلى للأقل.
  static List<QualityOption> fromStreams(List<Map<String, dynamic>> streams) {
    final out = <QualityOption>[];
    final seen = <String>{};

    for (final s in streams) {
      final id = (s['stream_id'] ?? s['id'] ?? '').toString();
      if (id.isEmpty || !seen.add(id)) continue;
      final ext = (s['container_extension'] ?? 'mp4').toString().toLowerCase();
      final v = s['video'];
      int? w, h;
      if (v is Map) {
        w = _int(v['width']);
        h = _int(v['height']);
      } else if (v is String && v.isNotEmpty) {
        // بعض البانلات ترجّع JSON كنص
        try {
          final j = _decodeMap(v);
          if (j != null) {
            w = _int(j['width']);
            h = _int(j['height']);
          }
        } catch (_) {}
      }
      out.add(QualityOption(
        id: id,
        ext: ext,
        label: labelFor(h),
        width: w,
        height: h,
        bitrate: _int(s['bitrate']),
      ));
    }

    out.sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
    return out;
  }

  /// التسمية حسب الارتفاع.
  static String labelFor(int? h) {
    if (h == null || h <= 0) return 'SD';
    if (h >= 2000) return '4K';
    if (h >= 1400) return 'QHD';
    if (h >= 1000) return 'FHD';
    if (h >= 700) return 'HD';
    return 'SD';
  }

  /// هل هذا الامتداد آمن للتشغيل المباشر؟ (mp4/mkv أفضل من ts للتحميل)
  static bool isDirectFriendly(String ext) =>
      ext == 'mp4' || ext == 'mkv' || ext == 'm4v';

  static int _int(dynamic v) {
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }

  // 🔸- إصلاح: jsonDecode بدل _jsonDecode
  static Map<String, dynamic>? _decodeMap(String s) {
    try {
      final j = jsonDecode(s);
      return j is Map ? Map<String, dynamic>.from(j) : null;
    } catch (_) {
      return null;
    }
  }
}
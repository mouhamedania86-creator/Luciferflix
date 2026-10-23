import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'api.dart';
import 'player_screen.dart';
import 'store.dart';

/// ====== المشغّل المصغّر (Mini Player) ======
///
/// لما المستخدم يصغّر الفيديو، يبقى شغّال تحت الشاشات الأخرى (NetFlix style).
/// نفس الـ Player instance ينتقل من شاشة المشغّل إلى المشغّل المصغّر.
class MiniPlayerController extends ChangeNotifier {
  MiniPlayerController._();

  static final MiniPlayerController instance = MiniPlayerController._();

  Player? _player;
  VideoController? _video;
  String? _title;
  String? _subtitle;
  String? _url;
  String? _type;
  String? _mediaId;
  String? _ext;
  WatchEntry? _watch;

  Player? get player => _player;
  VideoController? get video => _video;
  String? get title => _title;
  String? get subtitle => _subtitle;
  String? get url => _url;
  String? get type => _type;
  String? get mediaId => _mediaId;
  String? get ext => _ext;
  WatchEntry? get watch => _watch;

  bool get isActive => _player != null;

  void attach(
    Player p,
    VideoController v, {
    required String title,
    String? subtitle,
    String? url,
    String? type,
    String? mediaId,
    String? ext,
    WatchEntry? watch,
  }) {
    _player = p;
    _video = v;
    _title = title;
    _subtitle = subtitle;
    _url = url;
    _type = type;
    _mediaId = mediaId;
    _ext = ext;
    _watch = watch;
    notifyListeners();
  }

  /// يتخلص من المشغّل ويحرّر الموارد.
  void detach() {
    final p = _player;
    _player = null;
    _video = null;
    _title = null;
    _subtitle = null;
    _url = null;
    _type = null;
    _mediaId = null;
    _ext = null;
    _watch = null;
    notifyListeners();
    try {
      WakelockPlus.disable();
    } catch (_) {}
    if (p != null) {
      try {
        p.dispose();
      } catch (_) {}
    }
  }

  void togglePlay() {
    final p = _player;
    if (p == null) return;
    try {
      p.playOrPause();
    } catch (_) {}
  }

  void close() => detach();
}

/// الغلاف اللي يرسم المشغّل المصغّر فوق أي محتوى.
class MiniPlayerHost extends StatelessWidget {
  final Widget child;
  const MiniPlayerHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedBuilder(
            animation: MiniPlayerController.instance,
            builder: (context, _) {
              final c = MiniPlayerController.instance;
              if (!c.isActive) return const SizedBox.shrink();
              return _MiniBar(controller: c);
            },
          ),
        ),
      ],
    );
  }
}

class _MiniBar extends StatelessWidget {
  final MiniPlayerController controller;
  const _MiniBar({required this.controller});

  String _fullUrl() {
    final url = controller.url;
    if (url != null && url.isNotEmpty) return url;
    final api = XtreamAPI.instance;
    final id = controller.mediaId ?? '';
    final ext = controller.ext ?? 'mp4';
    if (controller.type == 'series') return api.buildSeriesUrl(id, ext);
    return api.buildMovieUrl(id, ext);
  }

  @override
  Widget build(BuildContext context) {
    final player = controller.player;
    final video = controller.video;
    if (player == null || video == null) return const SizedBox.shrink();

    final bottom = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(left: 10, right: 10, bottom: bottom + 58),
      child: Material(
        color: const Color(0xFF14151B),
        borderRadius: BorderRadius.circular(10),
        elevation: 8,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            final w = controller.watch;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlayerScreen(
                  url: _fullUrl(),
                  title: controller.title ?? '',
                  watch: w,
                  itemType: controller.type,
                  seriesId: controller.type == 'series' ? controller.mediaId : null,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 92,
                    height: 52,
                    child: Video(controller: video, controls: NoVideoControls),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      if ((controller.subtitle ?? '').isNotEmpty)
                        Text(
                          controller.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      StreamBuilder<Duration>(
                        stream: player.stream.position,
                        builder: (context, snap) {
                          final pos = snap.data?.inSeconds ?? 0;
                          final dur = player.state.duration.inSeconds;
                          final v = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: LinearProgressIndicator(
                              value: v,
                              minHeight: 3,
                              color: const Color(0xFFE50914),
                              backgroundColor: Colors.white12,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                StreamBuilder<bool>(
                  stream: player.stream.playing,
                  builder: (context, snap) {
                    final playing = snap.data ?? false;
                    return IconButton(
                      tooltip: playing ? 'إيقاف' : 'تشغيل',
                      icon: Icon(
                        playing
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                        color: Colors.white,
                      ),
                      onPressed: controller.togglePlay,
                    );
                  },
                ),
                IconButton(
                  tooltip: 'إغلاق',
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: controller.close,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'api.dart';
import 'device.dart';
import 'episodes.dart';
import 'mini_player.dart';
import 'player_overlays.dart';
import 'quality.dart';
import 'store.dart';
import 'strings.dart';
import 'user_data.dart';

class PlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  final String? fallbackUrl;
  final bool isLive;
  final WatchEntry? watch;

  final List<Map<String, dynamic>>? episodes;
  final String? seriesId;
  final String? itemType;

  const PlayerScreen({
    super.key,
    required this.url,
    required this.title,
    this.fallbackUrl,
    this.isLive = false,
    this.watch,
    this.episodes,
    this.seriesId,
    this.itemType,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _video;
  final List<StreamSubscription> _subs = [];
  Timer? _saver;

  bool _triedFallback = false;
  bool _completed = false;
  bool _resumePending = false;
  bool _advancing = false;
  int _pos = 0;
  final ValueNotifier<int> _posNotifier = ValueNotifier<int>(0);
  int _dur = 0;
  int _gen = 0;

  late String _title;
  WatchEntry? _watch;
  List<Map<String, dynamic>>? _episodes;
  int _index = -1;

  SkipRange? _skipIntro;
  int? _skipCredits;
  bool _showNextOverlay = false;
  int _nextCountdown = 15;
  Timer? _countdownTimer;
  String? _seekText;
  Timer? _seekTimer;
  String? _resumeMsg;
  Timer? _resumeTimer;
  bool _showStats = false;
  Timer? _sleepTimer;
  int? _sleepRemaining;
  Timer? _sleepTick;
  bool _handedOff = false;
  bool _mobilePadVisible = false;
  Timer? _padTimer;
  List<QualityOption> _qualities = const [];
  bool _loadingQuality = false;

  bool get _hasPrev => _episodes != null && _index > 0;
  bool get _hasNext =>
      _episodes != null && _index >= 0 && _index < _episodes!.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _title = widget.title;
    _watch = widget.watch;
    _episodes = widget.episodes;
    _index = _indexOfCurrent();

    if (Device.isTouchMobile) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }

    _player = Player(
        configuration:
            const PlayerConfiguration(bufferSize: 64 * 1024 * 1024));
    _video = VideoController(_player);

    _subs.add(_player.stream.position.listen((p) {
      if (!mounted) return;
      final seconds = p.inSeconds < 0 ? 0 : p.inSeconds;
      _pos = _dur > 0 ? seconds.clamp(0, _dur).toInt() : seconds;
      _posNotifier.value = _pos;
    }));
    _subs.add(_player.stream.duration.listen((d) {
      if (!mounted) return;
      final seconds = d.inSeconds < 0 ? 0 : d.inSeconds;
      setState(() {
        _dur = seconds;
        if (_dur > 0 && _pos > _dur) _pos = _dur;
        _posNotifier.value = _pos;
      });
    }));
    _subs.add(_player.stream.completed.listen(_onCompleted));
    _subs.add(_player.stream.error.listen(_onError));
    _saver = Timer.periodic(const Duration(seconds: 20), (_) => _save());

    _loadSkipMarkers();
    _open(widget.url);
    _ensureEpisodes();
    _keepAwake(true);
  }

  // ---------------- Skip markers ----------------

  Future<void> _loadSkipMarkers() async {
    final sid = widget.seriesId;
    if (sid == null || sid.isEmpty) return;
    try {
      final intro = await UD.skipIntro(sid);
      final credits = await UD.skipCreditsStart(sid);
      if (!mounted) return;
      setState(() {
        _skipIntro =
            intro != null && intro.start >= 0 && intro.end > intro.start
                ? intro
                : null;
        _skipCredits = credits != null && credits >= 0 ? credits : null;
      });
    } catch (_) {}
  }

  bool get _inIntro {
    final r = _skipIntro;
    if (r == null) return false;
    return _pos >= r.start && _pos <= r.end;
  }

  bool get _inCredits {
    final c = _skipCredits;
    if (c == null) return false;
    return _pos >= c && (_dur <= 0 || _pos < _dur - 60);
  }

  void _skipIntroNow() {
    final r = _skipIntro;
    if (r == null) return;
    _player.seek(Duration(seconds: r.end));
    _flashSeek('+${r.end - r.start}s');
  }

  void _skipCreditsNow() {
    if (_dur <= 0) return;
    _player.seek(Duration(seconds: (_dur - 5).clamp(0, _dur)));
  }

  Future<void> _showSkipMarkersDialog() async {
    final sid = widget.seriesId;
    if (sid == null || sid.isEmpty) {
      _toast('هذا المحتوى ليس مسلسلاً');
      return;
    }
    final current = _pos;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('set_skip_range')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الموضع الحالي: ${_fmt(current)}'),
            if (_skipIntro != null)
              Text(
                'المدى الحالي: ${_fmt(_skipIntro!.start)} → ${_fmt(_skipIntro!.end)}',
                style:
                    const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.play_arrow, size: 16),
                onPressed: () async {
                  await UD.setSkipIntro(sid, current, current + 60);
                  if (!mounted) return;
                  setState(() =>
                      _skipIntro = SkipRange(current, current + 60));
                  Navigator.pop(ctx);
                  _toast(S.t('skip_marker_set'));
                },
                label: Text(
                    '${S.t('mark_intro_start')} (${_fmt(current)})'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.stop, size: 16),
                onPressed: _skipIntro == null
                    ? null
                    : () async {
                        final s = _skipIntro!.start;
                        if (current <= s) {
                          _toast('النهاية يجب أن تكون بعد البداية');
                          return;
                        }
                        await UD.setSkipIntro(sid, s, current);
                        if (!mounted) return;
                        setState(() =>
                            _skipIntro = SkipRange(s, current));
                        Navigator.pop(ctx);
                        _toast(S.t('skip_marker_set'));
                      },
                label: Text(
                    '${S.t('mark_intro_end')} (${_fmt(current)})'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.skip_next, size: 16),
                onPressed: () async {
                  await UD.setSkipCreditsStart(sid, current);
                  if (!mounted) return;
                  setState(() => _skipCredits = current);
                  Navigator.pop(ctx);
                  _toast('تم تحديد بداية التتر');
                },
                label: Text('بداية التتر (${_fmt(current)})'),
              ),
            ),
            if (_skipIntro != null || _skipCredits != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 16),
                onPressed: () async {
                  await UD.clearSkipIntro(sid);
                  if (!mounted) return;
                  setState(() {
                    _skipIntro = null;
                    _skipCredits = null;
                  });
                  Navigator.pop(ctx);
                },
                label: const Text('حذف كل العلامات'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.t('cancel')),
          ),
        ],
      ),
    );
  }

  // ---------------- Next episode ----------------

  void _onCompleted(bool c) {
    if (!c || widget.isLive) return;
    if (_dur > 0 && _pos < _dur - 90) return;
    _completed = true;
    if (_hasNext && !_advancing) {
      _showNextEpisodeOverlay();
    }
  }

  void _showNextEpisodeOverlay() {
    if (!mounted || _showNextOverlay) return;
    setState(() {
      _showNextOverlay = true;
      _nextCountdown = 15;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_nextCountdown <= 1) {
        t.cancel();
        _playNext();
        return;
      }
      setState(() => _nextCountdown--);
    });
  }

  void _cancelNext() {
    _countdownTimer?.cancel();
    if (mounted) setState(() => _showNextOverlay = false);
  }

  Future<void> _playNext() async {
    _countdownTimer?.cancel();
    if (mounted) setState(() => _showNextOverlay = false);
    await _goTo(_index + 1);
  }

  // ---------------- Open / switch ----------------

  int _indexOfCurrent() {
    final w = _watch;
    final eps = _episodes;
    if (w == null || eps == null) return -1;
    return eps.indexWhere((e) => e['id'] == w.mediaId);
  }

  Future<void> _ensureEpisodes() async {
    final w = _watch;
    if (_episodes != null || w == null || w.type != 'series') return;
    try {
      final info = await XtreamAPI.instance.getSeriesInfo(w.itemId);
      final flat = flattenEpisodes(info?['episodes']);
      final idx = flat.indexWhere((e) => e['id'] == w.mediaId);
      if (!mounted || idx < 0) return;
      setState(() {
        _episodes = flat;
        _index = idx;
      });
    } catch (_) {}
  }

  Future<void> _open(String url) async {
    final gen = ++_gen;
    _triedFallback = false;
    Duration? start;
    final w = _watch;
    if (!widget.isLive && w != null) {
      final saved = await Store.entry(w.key);
      if (saved != null && !saved.done && saved.pos > 10) {
        start = Duration(seconds: saved.pos);
        if (mounted) {
          setState(() =>
              _resumeMsg = '${S.t('resume_at')} ${_fmt(saved.pos)}');
          _resumeTimer?.cancel();
          _resumeTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) setState(() => _resumeMsg = null);
          });
        }
      }
    }
    if (!mounted || gen != _gen) return;

    _resumePending = start != null;
    try {
      await _player.open(Media(url, start: start), play: true);
      if (start != null) await _seekWhenReady(start, gen);
    } catch (e) {
      if (mounted && gen == _gen) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'تعذّر تشغيل المحتوى. تحقق من الرابط أو اتصال الإنترنت ثم أعد المحاولة.')),
        );
      }
      return;
    } finally {
      if (gen == _gen) _resumePending = false;
    }

    if (w != null) {
      try {
        await UD.bumpPlayCount(w.type, w.mediaId, w.title);
      } catch (_) {}
    }
  }

  Future<void> _seekWhenReady(Duration target, int gen) async {
    try {
      if (_player.state.duration <= Duration.zero) {
        await _player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 25));
      }
      for (var i = 0; i < 3; i++) {
        if (!mounted || gen != _gen) return;
        final cur = _player.state.position;
        if ((target - cur).inSeconds.abs() <= 5) return;
        await _player.seek(target);
        await Future.delayed(const Duration(milliseconds: 1200));
      }
    } catch (_) {}
  }

  Future<void> _goTo(int i) async {
    final eps = _episodes;
    final w = _watch;
    if (eps == null || w == null || i < 0 || i >= eps.length) return;

    _save();
    final ep = eps[i];
    final sub = 'S${ep['season']} E${ep['num']}';
    final nw = WatchEntry.forEpisode(
        w.item, '${ep['id'] ?? ''}', '${ep['ext'] ?? 'mp4'}', sub);

    setState(() {
      _index = i;
      _watch = nw;
      _title = nw.fullTitle;
      _completed = false;
      _pos = 0;
      _posNotifier.value = 0;
      _dur = 0;
      _showNextOverlay = false;
      _skipIntro = null;
      _skipCredits = null;
    });
    await _loadSkipMarkers();
    await _open(XtreamAPI.instance.buildSeriesUrl(nw.mediaId, nw.ext));
  }

  void _onError(String error) {
    if (!mounted) return;
    if (widget.isLive && widget.fallbackUrl != null && !_triedFallback) {
      _triedFallback = true;
      _player.open(Media(widget.fallbackUrl!), play: true);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.t('player_fail'))));
    }
  }

  void _save() {
    final w = _watch;
    if (widget.isLive || w == null || _resumePending) return;
    final dur = _dur > 0 ? _dur : _player.state.duration.inSeconds;
    if (dur <= 0) return;
    final done = _completed || (dur > 120 && _pos >= dur - 60);
    if (!done && _pos < 10) return;
    Store.saveWatch(w.copyWith(
      pos: done ? dur : _pos,
      dur: dur,
      ts: DateTime.now().millisecondsSinceEpoch,
      done: done,
    ));
  }

  // ---------------- Sleep timer ----------------

  Future<void> _pickSleepTimer() async {
    final choice = await showModalBottomSheet<int?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.bedtime_outlined),
              title: Text(S.t('sleep_timer')),
            ),
            for (final m in [0, 15, 30, 45, 60])
              ListTile(
                title: Text(m == 0 ? S.t('sleep_off') : S.t('sleep_$m')),
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    _sleepTimer?.cancel();
    _sleepTick?.cancel();
    if (choice == 0) {
      if (mounted) setState(() => _sleepRemaining = null);
      return;
    }
    if (mounted) setState(() => _sleepRemaining = choice * 60);
    _sleepTimer = Timer(Duration(minutes: choice), () async {
      try {
        await _player.pause();
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${S.t('sleep_timer')} — ${S.t('sleep_off')}')),
        );
        Navigator.of(context).maybePop();
      }
    });
    _sleepTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        final v = (_sleepRemaining ?? 0) - 1;
        _sleepRemaining = v <= 0 ? null : v;
      });
    });
  }

  // ---------------- Quality ----------------

  Future<void> _pickQuality() async {
    if (widget.isLive) {
      _toast('اختيار الجودة متاح للأفلام والمسلسلات');
      return;
    }
    final w = _watch;
    if (w == null) return;
    if (_loadingQuality) return;
    setState(() => _loadingQuality = true);
    List<QualityOption> opts = const [];
    try {
      final streams = await XtreamAPI.instance.getVodStreams(w.mediaId);
      opts = Quality.fromStreams(streams);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loadingQuality = false);
    if (opts.length <= 1) {
      _toast('ما كاينش إلا جودة وحدة متوفرة');
      return;
    }
    final chosen = await showModalBottomSheet<QualityOption>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.high_quality),
              title: Text(S.t('quality')),
            ),
            for (final o in opts)
              ListTile(
                title: Text(o.resolution),
                subtitle: Text('${o.ext.toUpperCase()} · ${o.id}'),
                onTap: () => Navigator.pop(ctx, o),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    final url = widget.itemType == 'series'
        ? XtreamAPI.instance.buildSeriesUrl(chosen.id, chosen.ext)
        : XtreamAPI.instance.buildMovieUrl(chosen.id, chosen.ext);
    _save();
    await _open(url);
  }

  // ---------------- Tracks (AUDIO / SUBTITLE) ----------------

  Future<void> _pickTrack({required bool audio}) async {
    final tracks =
        audio ? _player.state.tracks.audio : _player.state.tracks.subtitle;
    if (tracks.isEmpty) {
      _toast(audio
          ? 'ما كاينش مسار صوت إضافي'
          : 'ما كاينش ترجمة في هذا الملف');
      return;
    }
    final chosen = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: Icon(
                  audio ? Icons.record_voice_over : Icons.closed_caption),
              title: Text(audio ? S.t('audio') : S.t('subtitles')),
            ),
            if (!audio)
              ListTile(
                title: Text(S.t('off')),
                onTap: () => Navigator.pop(ctx, -1),
              ),
            for (var i = 0; i < tracks.length; i++)
              ListTile(
                title: Text(
                  (tracks[i].title ?? '').isNotEmpty
                      ? tracks[i].title!
                      : '${audio ? 'Audio' : 'Subtitle'} ${i + 1}',
                ),
                subtitle: (tracks[i].language ?? '').isNotEmpty
                    ? Text(tracks[i].language!)
                    : null,
                onTap: () => Navigator.pop(ctx, i),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    try {
      if (audio) {
        // 🔸- إصلاح: AudioTrack.uri بدل tracks[chosen] مباشرة
        await _player.setAudioTrack(
          AudioTrack.uri(tracks[chosen].id ?? ''),
        );
      } else {
        if (chosen == -1) {
          await _player.setSubtitleTrack(SubtitleTrack.no());
        } else {
          // 🔸- إصلاح: SubtitleTrack.uri بدل tracks[chosen] مباشرة
          await _player.setSubtitleTrack(
            SubtitleTrack.uri(tracks[chosen].id ?? ''),
          );
        }
      }
    } catch (_) {}
  }

  // ---------------- Mini player ----------------

  Future<void> _minimize() async {
    final w = _watch;
    _handedOff = true;
    _save();
    MiniPlayerController.instance.attach(
      _player,
      _video,
      title: _title,
      subtitle: w?.subtitle,
      url: widget.url,
      type: widget.itemType ?? w?.type,
      mediaId: w?.mediaId,
      ext: w?.ext,
      watch: w,
    );
    if (mounted) Navigator.of(context).maybePop();
  }

  void _keepAwake(bool on) {
    try {
      if (on) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    } catch (_) {}
  }

  // ---------------- Helpers ----------------

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _flashSeek(String text) {
    _seekTimer?.cancel();
    if (mounted) setState(() => _seekText = text);
    _seekTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekText = null);
    });
  }

  void _showPad() {
    _padTimer?.cancel();
    setState(() => _mobilePadVisible = true);
    _padTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _mobilePadVisible = false);
    });
  }

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Map<String, String> _stats() {
    final st = _player.state;
    final w = st.width;
    final h = st.height;
    final ab = st.audioBitrate;
    final buf = st.buffer;
    return {
      S.t('resolution'): (w != null && h != null) ? '${w}x$h' : '—',
      S.t('bitrate'): ab != null ? '${ab.toStringAsFixed(0)} kbps' : '—',
      S.t('buffer'): buf != null ? _fmt(buf.inSeconds) : '—',
      'Position': '${_fmt(_pos)} / ${_fmt(_dur)}',
    };
  }

  // ---------------- Shortcuts ----------------

  Map<ShortcutActivator, VoidCallback> _shortcuts() {
    void seekBy(int seconds) {
      var p = _player.state.position + Duration(seconds: seconds);
      if (p < Duration.zero) p = Duration.zero;
      _player.seek(p);
    }

    void volumeBy(double d) {
      _player
          .setVolume((_player.state.volume + d).clamp(0.0, 100.0).toDouble());
    }

    return {
      const SingleActivator(LogicalKeyboardKey.mediaPlay): () =>
          _player.play(),
      const SingleActivator(LogicalKeyboardKey.mediaPause): () =>
          _player.pause(),
      const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () =>
          _player.playOrPause(),
      const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () {
        if (_hasNext) _goTo(_index + 1);
      },
      const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): () {
        if (_hasPrev) _goTo(_index - 1);
      },
      const SingleActivator(LogicalKeyboardKey.space): () =>
          _player.playOrPause(),
      const SingleActivator(LogicalKeyboardKey.select): () =>
          _player.playOrPause(),
      const SingleActivator(LogicalKeyboardKey.enter): () =>
          _player.playOrPause(),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => seekBy(-10),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => seekBy(10),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => volumeBy(5),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => volumeBy(-5),
    };
  }

  // ---------------- Lifecycle ----------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _save();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gen++;
    _saver?.cancel();
    _countdownTimer?.cancel();
    _seekTimer?.cancel();
    _resumeTimer?.cancel();
    _sleepTimer?.cancel();
    _sleepTick?.cancel();
    _padTimer?.cancel();
    if (!_handedOff) {
      _save();
      _keepAwake(false);
    }
    for (final s in _subs) {
      s.cancel();
    }
    _posNotifier.dispose();
    if (!_handedOff) {
      _player.dispose();
    }
    if (Device.isTouchMobile) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topBar = <Widget>[
      IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 200,
        child: Text(
          _title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      const Spacer(),
      if (_sleepRemaining != null)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bedtime_outlined,
                  color: Colors.white70, size: 18),
              const SizedBox(width: 4),
              Text(
                _fmt(_sleepRemaining!),
                style:
                    const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      if (_hasPrev)
        IconButton(
          icon: const Icon(Icons.skip_previous, color: Colors.white),
          onPressed: () => _goTo(_index - 1),
        ),
      if (_hasNext)
        IconButton(
          icon: const Icon(Icons.skip_next, color: Colors.white),
          onPressed: () => _goTo(_index + 1),
        ),
      IconButton(
        tooltip: S.t('quality'),
        icon: const Icon(Icons.high_quality, color: Colors.white),
        onPressed: _pickQuality,
      ),
      IconButton(
        tooltip: S.t('audio'),
        icon: const Icon(Icons.record_voice_over, color: Colors.white),
        onPressed: () => _pickTrack(audio: true),
      ),
      IconButton(
        tooltip: S.t('subtitles'),
        icon: const Icon(Icons.closed_caption, color: Colors.white),
        onPressed: () => _pickTrack(audio: false),
      ),
      IconButton(
        tooltip: S.t('stats_for_nerds'),
        icon: Icon(
          Icons.speed,
          color: _showStats ? const Color(0xFFE50914) : Colors.white,
        ),
        onPressed: () => setState(() => _showStats = !_showStats),
      ),
      IconButton(
        tooltip: S.t('sleep_timer'),
        icon: const Icon(Icons.bedtime_outlined, color: Colors.white),
        onPressed: _pickSleepTimer,
      ),
      PopupMenuButton<double>(
        icon: const Icon(Icons.speed, color: Colors.white),
        initialValue: _player.state.rate,
        onSelected: (value) {
          _player.setRate(value);
          setState(() {});
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 0.5, child: Text('0.5x')),
          PopupMenuItem(value: 0.75, child: Text('0.75x')),
          PopupMenuItem(value: 1.0, child: Text('1x')),
          PopupMenuItem(value: 1.25, child: Text('1.25x')),
          PopupMenuItem(value: 1.5, child: Text('1.5x')),
          PopupMenuItem(value: 2.0, child: Text('2x')),
        ],
      ),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: Colors.white),
        onSelected: (v) {
          if (v == 'watched') _markWatched();
          if (v == 'skip') _showSkipMarkersDialog();
          if (v == 'mini') _minimize();
        },
        itemBuilder: (context) => [
          PopupMenuItem(
              value: 'watched', child: Text(S.t('mark_watched'))),
          PopupMenuItem(
              value: 'skip', child: Text(S.t('set_skip_range'))),
          const PopupMenuItem(
              value: 'mini',
              child: Text('تصغير (مشغّل مصغّر)')),
        ],
      ),
    ];

    final Widget video;
    if (Device.useDesktopControls) {
      final t = MaterialDesktopVideoControlsThemeData(
        topButtonBar: topBar,
        seekBarPositionColor: Colors.red,
        seekBarThumbColor: Colors.red,
        keyboardShortcuts: _shortcuts(),
      );
      video = MaterialDesktopVideoControlsTheme(
        normal: t,
        fullscreen: t,
        child:
            Video(controller: _video, controls: MaterialDesktopVideoControls),
      );
    } else {
      final t = MaterialVideoControlsThemeData(
        volumeGesture: true,
        brightnessGesture: true,
        seekGesture: true,
        seekBarPositionColor: Colors.red,
        seekBarThumbColor: Colors.red,
        topButtonBar: topBar,
      );
      video = MaterialVideoControlsTheme(
        normal: t,
        fullscreen: t,
        child: Video(controller: _video, controls: MaterialVideoControls),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Device.isTouchMobile
                ? GestureDetector(
                    onTap: () => _showPad(),
                    onDoubleTapDown: (details) {
                      final w = MediaQuery.of(context).size.width;
                      final cur = _player.state.position;
                      if (details.globalPosition.dx > w / 2) {
                        _player
                            .seek(cur + const Duration(seconds: 10));
                        _flashSeek('+10s');
                      } else {
                        final p = cur - const Duration(seconds: 10);
                        _player
                            .seek(p < Duration.zero ? Duration.zero : p);
                        _flashSeek('-10s');
                      }
                    },
                    child: video,
                  )
                : video,
          ),

          if (_showStats)
            Positioned(
              left: 16,
              top: 90,
              child: StatsOverlay(
                  title: S.t('stats_for_nerds'), rows: _stats()),
            ),

          if (_resumeMsg != null)
            Positioned(
              top: 90,
              left: 0,
              right: 0,
              child:
                  Center(child: ResumeToast(message: _resumeMsg!)),
            ),

          if (_seekText != null)
            Positioned.fill(
              child: Center(child: SeekIndicator(text: _seekText!)),
            ),

          if (Device.isTouchMobile && _mobilePadVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 140,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                    ),
                    onPressed: () {
                      _player.seek(_player.state.position -
                          const Duration(seconds: 10));
                      _flashSeek('-10s');
                    },
                    icon: const Icon(Icons.replay_10),
                    label: const Text('10s'),
                  ),
                  const SizedBox(width: 18),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                    ),
                    onPressed: () {
                      _player.seek(_player.state.position +
                          const Duration(seconds: 30));
                      _flashSeek('+30s');
                    },
                    icon: const Icon(Icons.forward_30),
                    label: const Text('30s'),
                  ),
                ],
              ),
            ),

          // Skip buttons — تراقب _posNotifier
          ValueListenableBuilder<int>(
            valueListenable: _posNotifier,
            builder: (context, position, child) => _inIntro
                ? Positioned(
                    right: 20,
                    bottom: 120,
                    child: SkipButton(
                      label: S.t('skip_intro'),
                      icon: Icons.fast_forward,
                      onPressed: _skipIntroNow,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          ValueListenableBuilder<int>(
            valueListenable: _posNotifier,
            builder: (context, position, child) => _inCredits
                ? Positioned(
                    right: 20,
                    bottom: 120,
                    child: SkipButton(
                      label: S.t('skip_credits'),
                      icon: Icons.fast_forward,
                      onPressed: _skipCreditsNow,
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          if (_showNextOverlay && _hasNext)
            Positioned(
              right: 20,
              bottom: 120,
              child: NextEpisodeOverlay(
                episodeTitle: _nextTitle(),
                secondsLeft: _nextCountdown,
                onPlayNow: _playNext,
                onCancel: _cancelNext,
              ),
            ),
        ],
      ),
    );
  }

  String _nextTitle() {
    final eps = _episodes;
    if (eps == null || _index < 0 || _index + 1 >= eps.length) return '';
    final ep = eps[_index + 1];
    return 'S${ep['season']} E${ep['num']}';
  }

  void _markWatched() {
    final w = _watch;
    if (w == null) return;
    Store.saveWatch(w.copyWith(
      pos: _dur > 0 ? _dur : 0,
      dur: _dur,
      ts: DateTime.now().millisecondsSinceEpoch,
      done: true,
    ));
    _toast(S.t('mark_watched'));
  }
}
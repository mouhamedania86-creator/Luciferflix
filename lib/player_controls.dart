import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// ====== طبقة التحكم الخاصة بينا (بدل controls جاهزة) ======
///
/// علاش ما نعتمدوش على ضوابط media_kit الجاهزة؟
///
/// 1. الضوابط الجاهزة تختفي بعد 3 ثواني وفيه حالات (خصوصاً الأندرويد)
///    ما تظهرش نهائياً → المستخدم يلقى شاشة سوداء بلا أي زر.
/// 2. الضوابط الجاهزة ما تخدمش ملي نمرّو فوق stack فيه overlays.
/// 3. نحتاج تحكّم كامل: شريط تقدّم + سرعة + تخطي + أزرار الجودة/الصوت.
///
/// هاذي الطبقة ترسم كلشي بوحدها فوق الفيديو — **دايماً ظاهرة كي تطلبها**،
/// وتختفي تلقائياً بعد 3.5 ثانية بلا تفاعل.

class PlayerControls extends StatefulWidget {
  final Player player;
  final String title;

  /// أزرار الشريط العلوي (الجودة، الصوت، الترجمة، الإحصائيات…).
  final List<Widget> topActions;

  /// زر الرجوع (الافتراضي: زر back في الشريط العلوي).
  final VoidCallback? onBack;

  /// لوحات إضافية فوق الفيديو (تخطي المقدمة، الحلقة الجاية…).
  final Widget? overlay;

  /// نقر مزدوج على الفيديو (تقديم/تأخير 10 ثواني).
  final void Function(TapDownDetails details)? onDoubleTapDown;

  /// 🔸 تنداءو كي المستخدم يسحب/يتحرك في الفيديو — باش الشاشة الأم تعرف
  /// الموضع الجديد وتحفظه (كي ما يبقاش الاستئناف في بلاصة غلط).
  final void Function(Duration position)? onSeek;

  /// هل نعرض أدوات الكمبيوتر (الصوت، ملء الشاشة)؟
  final bool desktop;

  const PlayerControls({
    super.key,
    required this.player,
    required this.title,
    this.topActions = const [],
    this.onBack,
    this.overlay,
    this.onDoubleTapDown,
    this.onSeek,
    this.desktop = false,
  });

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  final List<StreamSubscription> _subs = [];
  Timer? _hideTimer;

  bool _visible = true;
  bool _playing = false;
  bool _buffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _dragValue = -1; // -1 = ما كايناش سحب
  bool _dragging = false;
  /// 🔸 كنوقفو تحديث الموضع من الـ stream وقت الـ seek — باش الشريط
  /// ما يرجعش للموقع القديم (كان كيرجع ويقطّع الفيديو).
  bool _seeking = false;

  @override
  void initState() {
    super.initState();
    final p = widget.player;
    _subs.add(p.stream.playing.listen((v) {
      if (mounted) setState(() => _playing = v);
    }));
    _subs.add(p.stream.buffering.listen((v) {
      if (mounted) setState(() => _buffering = v);
    }));
    _subs.add(p.stream.position.listen((v) {
      if (mounted && !_dragging && !_seeking) setState(() => _position = v);
    }));
    _subs.add(p.stream.duration.listen((v) {
      if (mounted) setState(() => _duration = v);
    }));
    _restartHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    if (!mounted) return;
    setState(() => _visible = true);
    _hideTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted && !_dragging) setState(() => _visible = false);
    });
  }

  void _toggleVisibility() {
    if (_visible) {
      _hideTimer?.cancel();
      setState(() => _visible = false);
    } else {
      _restartHideTimer();
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  /// 🔸 السحب: نسكيو **مرة وحدة**، نتأكدو من الوصول، وإذا ماوصلش نعاودو
  /// (mpv أحياناً يطنّش الـ seek وقت البفر).
  ///
  /// ⚠️ المشكل اللي كان:
  /// - `state.duration` ممكن يكون 0 → السحب كان **ما يعملش أصلاً**
  ///   (الشريط يتحرّك والفيديو ما يتحرّكش).
  /// - بعد `onChangeEnd` كنا نحبسو `_dragging` فنجمدو الشريط → كيرجع
  ///   للموقع القديم ويقطّع الفيديو.
  Future<void> _seekTo(double value) async {
    // نستعملو نفس المدة ديال الـ Slider (من الـ stream) باش ما يبقاش
    //_skوت_ بيناتهم، مع الـ state كـ fallback.
    var durationMs = _duration.inMilliseconds;
    if (durationMs <= 0) durationMs = widget.player.state.duration.inMilliseconds;
    if (durationMs <= 0) return;
    final targetMs = value.round().clamp(0, durationMs);
    await _seekToPosition(Duration(milliseconds: targetMs));
  }

  /// سكتة واحدة + تأكيد + (إعادة محاولة وحدة إذا ماوصلش).
  Future<void> _seekToPosition(Duration target) async {
    if (!mounted) return;
    setState(() {
      _seeking = true;
      _position = target; // الشريط يبقى في البلاصة الجديدة
    });
    widget.onSeek?.call(target);

    var reached = false;
    final wasPlaying = widget.player.state.playing;
    for (var attempt = 0; attempt < 3 && !reached; attempt++) {
      try {
        // 🔸 pause → seek → play
        // كان الفيديو كيمشي شويي من الموضع القديم قبل ما يطير للمكان
        // الجديد (ki يطلع "يمشي ويتقطع"). بالإيقاف قبل السكتة، mpv
        // يفكّ الترميز في الموضع الجديد مباشرةً → انتقال نظيف.
        if (wasPlaying) await widget.player.pause();
        await widget.player.seek(target);
        if (wasPlaying) await widget.player.play();
      } catch (_) {}
      final until = DateTime.now().add(const Duration(milliseconds: 1400));
      while (DateTime.now().isBefore(until)) {
        await Future.delayed(const Duration(milliseconds: 150));
        final cur = widget.player.state.position;
        if ((cur - target).inMilliseconds.abs() <= 3000) {
          reached = true;
          break;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _seeking = false;
      _dragging = false;
      _dragValue = -1;
      // إذا ماوصلناش، نوريو الحقيقة (ما نكذبوش على المستخدم).
      if (!reached) _position = widget.player.state.position;
    });
    _restartHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration.inMilliseconds.toDouble();
    final pos = _dragging ? _dragValue : _position.inMilliseconds.toDouble();
    final max = total <= 0 ? 1.0 : total;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleVisibility,
      onDoubleTapDown: widget.onDoubleTapDown,
      child: Stack(
        children: [
          // -------- الشريط العلوي --------
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_visible,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon:
                            const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: widget.onBack ??
                            () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      ...widget.topActions,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // -------- لوحات إضافية (تخطي/الحلقة الجاية) --------
          if (widget.overlay != null) Positioned.fill(child: widget.overlay!),

          // -------- مؤشر التحميل --------
          if (_buffering)
            const Positioned.fill(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFE50914)),
              ),
            ),

          // -------- الشريط السفلي --------
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_visible,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 18, 10, 10),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            _fmt(_dragging
                                ? Duration(milliseconds: _dragValue.round())
                                : _position),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 14),
                                activeTrackColor: const Color(0xFFE50914),
                                inactiveTrackColor: Colors.white24,
                                thumbColor: const Color(0xFFE50914),
                              ),
                              child: Slider(
                                min: 0,
                                max: max,
                                value: pos.clamp(0, max),
                                onChangeStart: (v) {
                                  setState(() {
                                    _dragging = true;
                                    _dragValue = v;
                                  });
                                  _hideTimer?.cancel();
                                },
                                onChanged: (v) =>
                                    setState(() => _dragValue = v),
                                onChangeEnd: (v) {
                                  // 🔸 ما نحبسوش _dragging هنا — نخلّيو
                                  // _seekToPosition يتكفّل بالConfirm
                                  // (هكذا الشريط ما يرجعش للموقع القديم).
                                  _seekTo(v);
                                },
                              ),
                            ),
                          ),
                          Text(
                            _fmt(_duration),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: '-10s',
                            icon: const Icon(Icons.replay_10,
                                color: Colors.white, size: 26),
                            onPressed: () {
                              final p = widget.player.state.position -
                                  const Duration(seconds: 10);
                              _seekToPosition(
                                  p < Duration.zero ? Duration.zero : p);
                            },
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            iconSize: 40,
                            icon: Icon(
                              _playing
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_fill,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              widget.player.playOrPause();
                              _restartHideTimer();
                            },
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: '+30s',
                            icon: const Icon(Icons.forward_30,
                                color: Colors.white, size: 26),
                            onPressed: () {
                              _seekToPosition(
                                widget.player.state.position +
                                    const Duration(seconds: 30),
                              );
                            },
                          ),
                          if (widget.desktop) ...[
                            const SizedBox(width: 10),
                            IconButton(
                              icon: Icon(
                                widget.player.state.volume == 0
                                    ? Icons.volume_off
                                    : Icons.volume_up,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                final v = widget.player.state.volume;
                                widget.player.setVolume(v == 0 ? 80 : 0);
                                _restartHideTimer();
                              },
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

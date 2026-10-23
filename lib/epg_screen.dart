import 'package:flutter/material.dart';

import 'api.dart';
import 'player_screen.dart';
import 'strings.dart';
import 'widgets.dart';

/// ====== دليل البرامج (EPG) ======
///
/// نعرض برنامج اليوم على شكل شريط زمني (من الآن حتى +24 ساعة)، والبرنامج
/// الجاري مُبرز، والبرنامج القديم متاح للإعادة عبر Timeshift.

class EpgScreen extends StatefulWidget {
  final String streamId;
  final String channelName;
  final String logoUrl;

  const EpgScreen({
    super.key,
    required this.streamId,
    required this.channelName,
    required this.logoUrl,
  });

  @override
  State<EpgScreen> createState() => _EpgScreenState();
}

class _EpgScreenState extends State<EpgScreen> {
  List<Map<String, String>> _programs = [];
  bool _loading = true;
  bool _error = false;

  static const double _trackW = 190;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final p = await XtreamAPI.instance.getEPG(widget.streamId, limit: 240);
      if (!mounted) return;
      setState(() {
        _programs = p;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _programs = [];
        _loading = false;
        _error = true;
      });
    }
  }

  DateTime? _parse(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s.trim());
  }

  String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final windowEnd = now.add(const Duration(hours: 24));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (widget.logoUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  widget.logoUrl,
                  width: 34,
                  height: 34,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox(width: 34),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.channelName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const ShimmerLoading(itemCount: 5)
          : _error || _programs.isEmpty
              ? MessageView(text: S.t('no_epg'), onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  children: [
                    _ruler(now, windowEnd),
                    const SizedBox(height: 10),
                    for (final p in _programs)
                      _programRow(p, now, windowEnd),
                  ],
                ),
    );
  }

  /// محور الوقت (كل ساعة = خط صغير).
  Widget _ruler(DateTime now, DateTime end) {
    return Row(
      children: [
        const SizedBox(width: 92),
        SizedBox(
          width: _trackW,
          height: 22,
          child: LayoutBuilder(
            builder: (context, box) => Stack(
              children: [
                for (var i = 0; i <= 24; i += 2)
                  Positioned(
                    left: (box.maxWidth * i / 24) - 1,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 1, color: Colors.white12),
                  ),
                Positioned(
                  left: 0,
                  top: 0,
                  child: Text(
                    _hhmm(now),
                    style: const TextStyle(fontSize: 10, color: Colors.white54),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Text(
                    _hhmm(end),
                    style: const TextStyle(fontSize: 10, color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _programRow(Map<String, String> p, DateTime now, DateTime windowEnd) {
    final start = _parse(p['start']);
    final end = _parse(p['end']);
    if (start == null) return const SizedBox.shrink();

    final isNow = now.isAfter(start) && (end == null || now.isBefore(end));
    final isPast = end != null && now.isAfter(end);
    final total = windowEnd.difference(now).inSeconds;
    final offset = start.difference(now).inSeconds;
    final span = (end ?? start.add(const Duration(hours: 1)))
        .difference(start)
        .inSeconds;

    double left = 0, width = 0;
    if (total > 0 && _trackW > 2) {
      left = (offset / total * _trackW).clamp(0.0, _trackW - 2).toDouble();
      final maxWidth = (_trackW - left).clamp(2.0, _trackW).toDouble();
      width = (span / total * _trackW).clamp(2.0, maxWidth).toDouble();
    }

    return InkWell(
      onTap: () => _showProgram(p, start, end, isPast),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _hhmm(start),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isNow ? const Color(0xFFE50914) : Colors.white,
                    ),
                  ),
                  if (end != null)
                    Text(
                      _hhmm(end),
                      style: const TextStyle(fontSize: 10, color: Colors.white38),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: _trackW,
              height: 44,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  Positioned(
                    left: left,
                    top: 0,
                    bottom: 0,
                    width: width,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isNow
                            ? const Color(0xFFE50914)
                            : (isPast ? Colors.white12 : Colors.white24),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        p['title'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isNow ? Colors.white : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p['title'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isNow ? FontWeight.w800 : FontWeight.w600,
                      color: isNow ? const Color(0xFFE50914) : Colors.white,
                    ),
                  ),
                  if (isNow)
                    Text(
                      S.t('now_playing'),
                      style: const TextStyle(fontSize: 10, color: Colors.white54),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ورقة البرنامج: مشاهدة الآن أو إعادة (Timeshift).
  void _showProgram(
    Map<String, String> p,
    DateTime start,
    DateTime? end,
    bool isPast,
  ) {
    final title = p['title'] ?? '';
    final desc = p['description'] ?? '';
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                '${_hhmm(start)}${end != null ? ' - ${_hhmm(end)}' : ''}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  desc,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE50914),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        final item = <String, dynamic>{
                          'stream_id': widget.streamId,
                          'name': widget.channelName,
                          'stream_icon': widget.logoUrl,
                          '_type': 'live',
                        };
                        openItem(ctx, item, 'live');
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: Text(S.t('watch_from_start')),
                    ),
                  ),
                  if (isPast) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _replay(title, start);
                        },
                        icon: const Icon(Icons.replay),
                        label: Text(S.t('timeshift')),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// إعادة برنامج سابق عبر رابط Timeshift.
  void _replay(String title, DateTime start) {
    try {
      final now = DateTime.now();
      final seconds = now.difference(start).inSeconds;
      if (seconds <= 60) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ما يمكنش إعادة هالبرنامج')),
        );
        return;
      }
      final url = XtreamAPI.instance.buildTimeshiftUrl(
        widget.streamId,
        duration: seconds,
        start: start.millisecondsSinceEpoch ~/ 1000,
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            url: url,
            title: title,
            isLive: false,
            itemType: 'live',
          ),
        ),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ماقدرناش نشغلوا الإعادة')),
      );
    }
  }
}

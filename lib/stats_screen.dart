import 'package:flutter/material.dart';

import 'strings.dart';
import 'user_data.dart';
import 'widgets.dart';

/// ====== إحصائيات المشاهدة (NetFlix-like) ======

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  WatchStats _stats = WatchStats.empty;
  bool _loading = true;

  static const List<String> _days = [
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await UD.stats();
    if (!mounted) return;
    setState(() {
      _stats = s;
      _loading = false;
    });
  }

  String _fmtDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return S.t('minutes_only').replaceAll('{m}', '$m');
    return S.t('hours_minutes').replaceAll('{h}', '$h').replaceAll('{m}', '$m');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('my_stats'))),
      body: _loading
          ? const ShimmerLoading(itemCount: 4)
          : _stats.totalMinutes == 0 && _stats.topItems.isEmpty
              ? const EmptyState(
                  icon: Icons.query_stats,
                  message: 'ما كاينش إحصائيات بعد — شغل شي حاجة',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    _card(
                      S.t('total_watch_time'),
                      _fmtDuration(_stats.totalMinutes),
                      Icons.schedule,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _card(
                            S.t('movies_watched'),
                            '${_stats.movies}',
                            Icons.movie,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _card(
                            S.t('series_watched'),
                            '${_stats.series}',
                            Icons.tv,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _card(
                            S.t('episodes_watched'),
                            '${_stats.episodes}',
                            Icons.playlist_play,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _card(
                            S.t('live_watched'),
                            '${_stats.live}',
                            Icons.live_tv,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      S.t('last_7_days'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 180,
                      padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF14151B),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _WeekChart(
                        values: _stats.perDay,
                        labels: _days,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      S.t('most_watched'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final t in _stats.topItems)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.play_circle_outline,
                            color: Color(0xFFE50914)),
                        title: Text(
                          '${t['title'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          (t['type'] ?? 'vod') == 'series'
                              ? S.t('series')
                              : S.t('movies'),
                        ),
                        trailing: Text(
                          _fmtDuration((t['minutes'] ?? 0) as int),
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _card(String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF14151B),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFE50914), size: 20),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
      );
}

/// رسم بياني بسيط للأيام السبعة (بلا أي حزمة خارجية).
class _WeekChart extends StatelessWidget {
  final List<int> values;
  final List<String> labels;

  const _WeekChart({required this.values, required this.labels});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final n = 7;
        final maxV = values.isEmpty
            ? 1
            : values.reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);
        final barW = (box.maxWidth - (n - 1) * 6) / n;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < n; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      i < values.length && values[i] > 0 ? '${values[i]}' : '',
                      style: const TextStyle(fontSize: 9, color: Colors.white54),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      width: barW,
                      height: 12 +
                          (box.maxHeight - 46) *
                              ((i < values.length ? values[i] : 0) / maxV),
                      decoration: BoxDecoration(
                        color: (i < values.length && values[i] > 0)
                            ? const Color(0xFFE50914)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 5),
                    SizedBox(
                      width: barW,
                      child: Text(
                        i < labels.length ? labels[i].substring(0, 3) : '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 9, color: Colors.white38),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

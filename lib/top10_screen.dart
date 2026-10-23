import 'package:flutter/material.dart';

import 'strings.dart';
import 'user_data.dart';
import 'widgets.dart';

/// ====== Top 10: الأكثر تشغيلاً على الجهاز ======

class Top10Screen extends StatefulWidget {
  const Top10Screen({super.key});

  @override
  State<Top10Screen> createState() => _Top10ScreenState();
}

class _Top10ScreenState extends State<Top10Screen> {
  List<Map<String, dynamic>> _counts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await UD.playCounts();
    if (!mounted) return;
    setState(() {
      _counts = c.take(10).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('top10'))),
      body: _loading
          ? const ShimmerLoading(itemCount: 5)
          : _counts.isEmpty
              ? const EmptyState(
                  icon: Icons.leaderboard_outlined,
                  message: 'شغل حاجة باش يبان الترتيب',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  itemCount: _counts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final c = _counts[i];
                    final title = (c['title'] ?? '').toString();
                    final type = (c['type'] ?? 'vod').toString();
                    final count = (c['count'] ?? 0) as int;
                    return ListTile(
                      leading: SizedBox(
                        width: 46,
                        child: Text(
                          '${i + 1}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFE50914),
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      ),
                      title: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        type == 'series'
                            ? S.t('series')
                            : type == 'live'
                                ? S.t('live')
                                : S.t('movies'),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            color: Color(0xFFE50914),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

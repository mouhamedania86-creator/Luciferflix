import 'package:flutter/material.dart';
import 'store.dart';
import 'strings.dart';
import 'widgets.dart';

/// سجل المشاهدة المحلي: يسمح باستكمال المحتوى أو إزالة عنصر من السجل.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Future<List<WatchEntry>> _load() => Store.history();

  Future<void> _remove(WatchEntry entry) async {
    await Store.removeWatch(entry.key);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل المشاهدة'),
        actions: [
          IconButton(
            tooltip: 'مسح السجل',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('مسح سجل المشاهدة؟'),
                  content: const Text('سيتم حذف تقدم المشاهدة المحفوظ محليًا.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(S.t('cancel'))),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('مسح')),
                  ],
                ),
              );
              if (ok == true) {
                for (final entry in await Store.history()) {
                  await Store.removeWatch(entry.key);
                }
                if (mounted) setState(() {});
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<List<WatchEntry>>(
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: ShimmerLoading(itemCount: 3));
          }
          final entries = snapshot.data ?? <WatchEntry>[];
          if (entries.isEmpty) return const Center(child: Text('سجل المشاهدة فارغ'));
          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final percent = entry.dur > 0 ? (entry.fraction * 100).round() : 0;
              return ListTile(
                leading: SizedBox(width: 54, child: Poster(url: posterOf(entry.item))),
                title: Text(entry.fullTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(entry.done ? 'تمت المشاهدة' : entry.dur > 0 ? '$percent% مكتمل' : 'لم يبدأ بعد'),
                onTap: () => resumeEntry(context, entry),
                trailing: IconButton(
                  tooltip: 'إزالة من السجل',
                  icon: const Icon(Icons.close),
                  onPressed: () => _remove(entry),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

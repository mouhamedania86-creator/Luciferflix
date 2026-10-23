import 'package:flutter/material.dart';

import 'strings.dart';
import 'user_data.dart';
import 'widgets.dart';

/// ====== "قائمتي" (My List) ======
///
/// قائمة شخصية يجمع فيها المستخدم ما يحب (أفلام/مسلسلات/قنوات) — مستقلة
/// عن المفضلة القديمة وتخزّن محلياً في البروفايل النشط.

class MyListScreen extends StatefulWidget {
  const MyListScreen({super.key});

  @override
  State<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends State<MyListScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    UD.myListVersion.addListener(_load);
  }

  @override
  void dispose() {
    UD.myListVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final l = await UD.myList();
    if (!mounted) return;
    setState(() {
      _items = l;
      _loading = false;
    });
  }

  String _idOf(Map<String, dynamic> m) =>
      '${m['stream_id'] ?? m['series_id'] ?? ''}';

  Future<void> _remove(Map<String, dynamic> item) async {
    final type = (item['_type'] ?? 'vod').toString();
    await UD.toggleMyList(type, item);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(S.t('removed_from_list'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const ShimmerLoading(itemCount: 4);

    if (_items.isEmpty) {
      return EmptyState(
        icon: Icons.playlist_add,
        message: S.t('my_list_empty'),
      );
    }

    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 700;
        final cols = wide
            ? (box.maxWidth / 200).floor().clamp(3, 8)
            : (box.maxWidth / 140).floor().clamp(2, 5);
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 0.58,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: _items.length,
          itemBuilder: (context, i) {
            final item = _items[i];
            final type = (item['_type'] ?? 'vod').toString();
            return Stack(
              children: [
                Positioned.fill(
                  child: Tappable(
                    radius: 10,
                    onTap: () => openItem(context, item, type),
                    child: Column(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Poster(
                              url: posterOf(item),
                              fit: type == 'live'
                                  ? BoxFit.contain
                                  : BoxFit.cover,
                              width: double.infinity,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (item['name'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    tooltip: S.t('removed_from_list'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.remove_circle, color: Colors.white),
                    onPressed: () => _remove(item),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

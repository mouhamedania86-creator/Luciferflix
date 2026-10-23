import 'package:flutter/material.dart';

import 'api.dart';
import 'epg_screen.dart';
import 'strings.dart';
import 'widgets.dart';

/// ====== التلفزيون المباشر: قنوات + فئات + بحث + EPG ======

class LiveTab extends StatefulWidget {
  const LiveTab({super.key});

  @override
  State<LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<LiveTab> {
  final api = XtreamAPI.instance;
  static final Map<String, List<dynamic>> _channelCache = {};
  static final Map<String, DateTime> _channelCacheAt = {};
  static const Duration _channelCacheTtl = Duration(minutes: 5);

  List<dynamic> _cats = [];
  List<dynamic> _channels = [];
  List<Map<String, dynamic>> _favs = [];
  String? _cat;
  String _sort = 'num';
  bool _onlyFavs = false;
  bool _loading = true;
  bool _error = false;
  final TextEditingController _search = TextEditingController();
  String _query = '';
  List<dynamic> _cachedVisible = const [];

  void _rebuildVisible() {
    _cachedVisible = _visible();
  }

  @override
  void initState() {
    super.initState();
    _loadCats();
    _loadChannels();
    _loadFavs();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadCats() async {
    final c = await api.getCategories('live');
    if (mounted) setState(() => _cats = c);
  }

  Future<void> _loadFavs() async {
    final f = await api.getFavorites();
    if (mounted) {
      setState(() { _favs = f.where((e) => (e['_type'] ?? '') == 'live').toList(); _rebuildVisible(); });
    }
  }

  Future<void> _loadChannels() async {
    final cacheKey = _cat ?? 'all';
    final cached = _channelCache[cacheKey];
    final cachedAt = _channelCacheAt[cacheKey];
    if (cached != null && cachedAt != null &&
        DateTime.now().difference(cachedAt) < _channelCacheTtl) {
      if (!mounted) return;
      setState(() { _channels = List<dynamic>.from(cached); _loading = false; _error = false; _rebuildVisible(); });
      return;
    }
    try {
      final l = await api.getStreams('live', categoryId: _cat);
      if (!mounted) return;
      _channelCache[cacheKey] = List<dynamic>.from(l);
      _channelCacheAt[cacheKey] = DateTime.now();
      setState(() {
        _channels = l;
        _loading = false;
        _error = false;
        _rebuildVisible();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  void _selectCat(String? id) {
    setState(() {
      _cat = id;
      _loading = true;
      _error = false;
    });
    _loadChannels();
  }

  /// القنوات بعد الفلترة (بحث + المفضلة) والترتيب.
  List<dynamic> _visible() {
    var list = List<dynamic>.from(_channels);

    if (_onlyFavs) {
      final ids = _favs.map((f) => '${f['stream_id'] ?? ''}').toSet();
      list = list.where((c) => ids.contains('${c['stream_id'] ?? ''}')).toList();
    }

    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      list = list
          .where((c) => '${c['name'] ?? ''}'.toLowerCase().contains(q))
          .toList();
    }

    if (_sort == 'name') {
      list.sort((a, b) =>
          '${a['name'] ?? ''}'.toLowerCase().compareTo('${b['name'] ?? ''}'.toLowerCase()));
    } else {
      list.sort((a, b) {
        int n(dynamic x) => int.tryParse('${x['num'] ?? 0}') ?? 0;
        return n(a).compareTo(n(b));
      });
    }
    return list;
  }

  Future<void> _toggleFav(dynamic item) async {
    await api.toggleFavorite('live', item);
    await _loadFavs();
  }

  bool _isFav(dynamic item) {
    final id = '${item['stream_id'] ?? ''}';
    return _favs.any((f) => '${f['stream_id'] ?? ''}' == id);
  }

  @override
  Widget build(BuildContext context) {
    final items = _cachedVisible;

    return Column(
      children: [
        // شريط البحث + الترتيب + المفضلة
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _search,
                    onChanged: (v) => setState(() { _query = v; _rebuildVisible(); }),
                    decoration: InputDecoration(
                      hintText: S.t('search_channels'),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFF14151B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.sort, color: Colors.white70),
                initialValue: _sort,
                onSelected: (v) => setState(() { _sort = v; _rebuildVisible(); }),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'num', child: Text('الرقم')),
                  PopupMenuItem(value: 'name', child: Text('الاسم')),
                ],
              ),
              IconButton(
                tooltip: S.t('favorite_channels'),
                icon: Icon(
                  _onlyFavs ? Icons.favorite : Icons.favorite_border,
                  color: _onlyFavs ? Colors.red : Colors.white70,
                ),
                onPressed: () => setState(() { _onlyFavs = !_onlyFavs; _rebuildVisible(); }),
              ),
            ],
          ),
        ),

        // فئات القنوات
        if (_cats.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _cats.length + 1,
              itemBuilder: (context, i) {
                final id = i == 0 ? null : _cats[i - 1]['category_id'].toString();
                final label =
                    i == 0 ? S.t('all') : (_cats[i - 1]['category_name'] ?? '').toString();
                return Padding(
                  padding: const EdgeInsets.all(5),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _cat == id,
                    onSelected: (_) => _selectCat(id),
                  ),
                );
              },
            ),
          ),

        Expanded(
          child: _loading
              ? const ShimmerLoading(itemCount: 4)
              : _error
                  ? MessageView(text: S.t('load_fail'), onRetry: _loadChannels)
                  : items.isEmpty
                      ? MessageView(text: S.t('no_channels'), onRetry: _loadChannels)
                      : RefreshIndicator(
                          onRefresh: _loadChannels,
                          child: LayoutBuilder(
                            builder: (context, box) {
                              final wide = box.maxWidth >= 700;
                              final cols = wide
                                  ? (box.maxWidth / 220).floor().clamp(3, 8)
                                  : (box.maxWidth / 130).floor().clamp(2, 5);
                              return GridView.builder(
                                padding: const EdgeInsets.all(12),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: cols,
                                  childAspectRatio: wide ? 1.25 : 0.95,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                                itemCount: items.length,
                                itemBuilder: (context, i) =>
                                    _ChannelCard(
                                  item: items[i],
                                  isFav: _isFav(items[i]),
                                  onFav: () => _toggleFav(items[i]),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

class _ChannelCard extends StatelessWidget {
  final dynamic item;
  final bool isFav;
  final VoidCallback onFav;

  const _ChannelCard({
    required this.item,
    required this.isFav,
    required this.onFav,
  });

  @override
  Widget build(BuildContext context) {
    final name = (item['name'] ?? '').toString();
    final id = (item['stream_id'] ?? '').toString();
    final cat = (item['category_name'] ?? '').toString();
    final num = (item['num'] ?? '').toString();

    return Tappable(
      onTap: () => openItem(context, item, 'live'),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF14151B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Poster(url: posterOf(item), fit: BoxFit.contain),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        isFav ? Icons.favorite : Icons.favorite_border,
                        color: isFav ? Colors.red : Colors.white70,
                        size: 20,
                      ),
                      onPressed: onFav,
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.black54,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        minimumSize: const Size(0, 28),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EpgScreen(
                              streamId: id,
                              channelName: name,
                              logoUrl: posterOf(item),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.schedule, size: 14, color: Colors.white70),
                      label: const Text('EPG', style: TextStyle(fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    num.isEmpty ? name : '$num · $name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  if (cat.isNotEmpty)
                    Text(
                      cat,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
}

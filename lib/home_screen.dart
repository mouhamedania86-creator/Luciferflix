import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'coming_soon_screen.dart';
import 'live_screen.dart';
import 'my_list_screen.dart';
import 'notifications_screen.dart';
import 'recommend.dart';
import 'settings_screen.dart';
import 'store.dart';
import 'strings.dart';
import 'tmdb.dart';
import 'user_data.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  final Set<int> _visited = {0}; // التبويبات تتحمل عند أول زيارة فقط
  int _favVersion = 0;

  void _select(int i) => setState(() {
        _index = i;
        _visited.add(i);
        if (i == 5) _favVersion++; // تحديث المفضلة عند فتحها
      });

  Widget _tab(int i) {
    if (!_visited.contains(i)) return const SizedBox.shrink();
    switch (i) {
      case 0:
        return const HomeTab();
      case 1:
        return const CategoryTab(type: 'vod');
      case 2:
        return const CategoryTab(type: 'series');
      case 3:
        return FutureBuilder<bool>(
          future: UD.getBool('kidsMode'),
          builder: (context, snapshot) => snapshot.data == true
              ? const Center(child: Text('هذا القسم غير متاح في وضع الأطفال'))
              : const LiveTab(),
        );
      case 4:
        return const MyListScreen();
      default:
        return FavoritesTab(key: ValueKey(_favVersion));
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 700; // كمبيوتر / تلفزة / تابلت
    const icons = [
      Icons.home,
      Icons.movie,
      Icons.tv,
      Icons.live_tv,
      Icons.playlist_add_check,
      Icons.favorite,
    ];
    final labels = [
      S.t('home'),
      S.t('movies'),
      S.t('series'),
      S.t('live'),
      S.t('my_list'),
      S.t('favorites'),
    ];

    final content = Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: XtreamAPI.instance.offline,
          builder: (context, off, _) => off
              ? Container(
                  width: double.infinity,
                  color: Colors.orange.shade800,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    S.t('offline'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: IndexedStack(index: _index, children: List.generate(6, _tab)),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MOVIEFLIX',
          style: TextStyle(
            color: Color(0xFFE50914),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            fontSize: 22,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => showSearch(context: context, delegate: ItemSearchDelegate()),
          ),
          ValueListenableBuilder<int>(
            valueListenable: Store.unread,
            builder: (context, n, _) => IconButton(
              icon: Badge(
                isLabelVisible: n > 0,
                label: Text('$n'),
                child: const Icon(Icons.notifications_outlined),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              ),
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: UD.settingsVersion,
            builder: (context, _, __) => FutureBuilder<bool>(
              future: UD.getBool('kidsMode'),
              builder: (context, snapshot) => snapshot.data == true
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const Icon(Icons.settings),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  backgroundColor: const Color(0xFF101116),
                  selectedIndex: _index,
                  onDestinationSelected: _select,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (var i = 0; i < 6; i++)
                      NavigationRailDestination(
                        icon: Icon(icons[i]),
                        label: Text(labels[i]),
                      ),
                  ],
                ),
                Expanded(child: content),
              ],
            )
          : content,
      bottomNavigationBar: wide
          ? null
          : BottomNavigationBar(
              backgroundColor: const Color(0xFF101116),
              selectedItemColor: const Color(0xFFE50914),
              unselectedItemColor: Colors.grey,
              type: BottomNavigationBarType.fixed,
              currentIndex: _index,
              onTap: _select,
              items: [
                for (var i = 0; i < 6; i++)
                  BottomNavigationBarItem(icon: Icon(icons[i]), label: labels[i]),
              ],
            ),
    );
  }
}

// ======================= الرئيسية (مثل Netflix) =======================
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final api = XtreamAPI.instance;
  List<dynamic> _movies = [], _series = [], _latestM = [], _latestS = [];
  List<dynamic> _vodCats = [], _serCats = [];
  List<WatchEntry> _history = [];
  List<Upcoming> _upcoming = [];
  List<Map<String, dynamic>> _counts = [];
  Set<String> _watchedKeys = {};
  Set<String> _blocked = {};
  bool _hideWatched = false;
  bool _needKey = false;
  bool _loading = true, _error = false;

  @override
  void initState() {
    super.initState();
    Store.historyVersion.addListener(_loadHistory);
    _loadHistory();
    _load();
  }

  @override
  void dispose() {
    Store.historyVersion.removeListener(_loadHistory);
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final h = await Store.history();
    if (mounted) setState(() => _history = h);
  }

  List<dynamic> _latest(List<dynamic> l, String key) {
    final c = List<dynamic>.from(l);
    int v(dynamic x) => int.tryParse('${x[key]}') ?? 0;
    c.sort((a, b) => v(b).compareTo(v(a)));
    return c.take(15).toList();
  }

  Future<void> _load() async {
    try {
      final m = await api.getStreams('vod');
      final s = await api.getStreams('series');
      if (!mounted) return;
      setState(() {
        _movies = m;
        _series = s;
        _latestM = _latest(m, 'added');
        _latestS = _latest(s, 'last_modified');
        _loading = false;
        _error = false;
      });
      _loadExtras();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  Future<void> _loadExtras() async {
    Store.processDue();
    final vc = await api.getCategories('vod');
    final sc = await api.getCategories('series');
    final counts = await UD.playCounts();
    final hist = await Recommend.rawHistory();
    final hide = await UD.getBool('hideWatched');
    final blocked = await UD.blockedCategories();
    if (mounted) {
      setState(() {
        _vodCats = vc;
        _serCats = sc;
        _counts = counts;
        _watchedKeys = Recommend.watchedKeysFrom(hist);
        _hideWatched = hide;
        _blocked = blocked;
      });
    }
    _checkNew();
    _loadUpcoming();
  }

  /// إذا ظهر محتوى جديد من آخر زيارة نزيدو في الإشعارات.
  Future<void> _checkNew() async {
    final seen = await Store.seenIds();
    final keys = <String, String>{};
    for (final it in _latestM.take(10)) {
      keys['vod_${XtreamAPI.idOf(it, 'vod')}'] = (it['name'] ?? '').toString();
    }
    for (final it in _latestS.take(10)) {
      keys['series_${XtreamAPI.idOf(it, 'series')}'] = (it['name'] ?? '').toString();
    }
    if (seen.isNotEmpty) {
      var n = 0;
      for (final e in keys.entries) {
        if (!seen.contains(e.key) && n < 3) {
          await Store.addInbox(S.t('new_added'), e.value);
          n++;
        }
      }
    }
    await Store.setSeenIds({...seen, ...keys.keys});
  }

  Future<void> _loadUpcoming() async {
    final key = await Store.tmdbKey();
    if (key.isEmpty) {
      if (mounted) setState(() => _needKey = true);
      return;
    }
    try {
      final l = await Tmdb.upcoming(key, S.tmdbLang);
      if (mounted) {
        setState(() {
          _upcoming = l;
          _needKey = false;
        });
      }
    } catch (_) {}
  }

  static bool _isAdult(String name) =>
      RegExp(r'xxx|adult|porn|18\+|sex', caseSensitive: false).hasMatch(name);

  List<Map<String, dynamic>> _heroEntries() {
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < 4; i++) {
      if (i < _latestM.length) out.add({'item': _latestM[i], 'type': 'vod'});
      if (i < _latestS.length) out.add({'item': _latestS[i], 'type': 'series'});
    }
    return out;
  }

  // ====== Top 10 (من عدّاد التشغيل المحلي) ======
  List<Map<String, dynamic>> _top10Items() {
    final out = <Map<String, dynamic>>[];
    for (final c in _counts) {
      final id = '${c['id']}';
      Map<String, dynamic>? found;
      for (final m in _movies) {
        if ('${m['stream_id']}' == id) {
          found = Map<String, dynamic>.from(m as Map);
          break;
        }
      }
      if (found == null) {
        for (final s in _series) {
          if ('${s['series_id']}' == id) {
            found = Map<String, dynamic>.from(s as Map);
            break;
          }
        }
      }
      if (found != null) {
        found['_type'] = c['type'];
        out.add(found);
      }
      if (out.length >= 10) break;
    }
    return out;
  }

  /// "لأنك شفت" — نفس الفئة.
  List<Map<String, dynamic>> _becauseYouWatched() {
    final a = Recommend.becauseYouWatched(
      allItems: _movies,
      watchedKeys: _watchedKeys,
      type: 'vod',
      limit: 15,
    );
    final b = Recommend.becauseYouWatched(
      allItems: _series,
      watchedKeys: _watchedKeys,
      type: 'series',
      limit: 15,
    );
    return [...a, ...b];
  }

  /// يخفي اللي شفته (حسب الإعداد).
  List<dynamic> _filterWatched(List<dynamic> items, String type) {
    if (!_hideWatched) return items;
    return items
        .where((it) => !_watchedKeys.contains('${type}_${XtreamAPI.idOf(it, type)}'))
        .toList();
  }

  Widget _row(String title, List<Widget> cards) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: cardRowHeight(context),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => cards[i],
          ),
        ),
      ],
    );
  }

  List<Widget> _categoryRows(
    List<dynamic> items,
    List<dynamic> cats,
    String type,
    int maxRows,
  ) {
    final byCat = <String, List<dynamic>>{};
    for (final it in items) {
      (byCat['${it['category_id']}'] ??= <dynamic>[]).add(it);
    }
    final rows = <Widget>[];
    for (final c in cats) {
      if (rows.length >= maxRows) break;
      final name = (c['category_name'] ?? '').toString();
      if (name.isEmpty || _isAdult(name)) continue;
      final catId = '${c['category_id']}';
      if (_blocked.contains(catId)) continue; // 🔸 الرقابة parental
      final list = byCat[catId];
      if (list == null || list.length < 6) continue;
      final filtered = _filterWatched(list, type).take(15).toList();
      if (filtered.isEmpty) continue;
      final label = '${S.t(type == 'vod' ? 'movies' : 'series')} • $name';
      rows.add(
        _row(
          label,
          filtered
              .map<Widget>(
                (it) => PosterCard(item: it, type: type),
              )
              .toList(),
        ),
      );
    }
    return rows;
  }

  Widget _comingSoon() {
    if (_needKey) {
      return Card(
        margin: const EdgeInsets.all(16),
        child: ListTile(
          leading: const Icon(Icons.event_available),
          title: Text(S.t('coming_soon')),
          subtitle: Text(S.t('tmdb_need_key')),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
      );
    }
    return _row(
      S.t('coming_soon'),
      _upcoming.map<Widget>((u) => _UpcomingCard(u: u)).toList(),
    );
  }

  Future<void> _toggleHideWatched() async {
    final v = !_hideWatched;
    await UD.setSetting('hideWatched', v);
    if (mounted) setState(() => _hideWatched = v);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const ShimmerLoading();
    if (_error || (_movies.isEmpty && _series.isEmpty)) {
      return MessageView(
        text: S.t('load_fail'),
        onRetry: () {
          setState(() {
            _loading = true;
            _error = false;
          });
          _load();
        },
      );
    }

    final cont = Store.continueList(_history);
    final watched = Store.watchedList(_history);
    final hero = _heroEntries();
    final top10 = _top10Items();
    final because = _becauseYouWatched();

    return RefreshIndicator(
      onRefresh: () async {
        api.clearMemory();
        await _load();
      },
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (hero.isNotEmpty) HeroCarousel(entries: hero),
          if (cont.isNotEmpty)
            _row(
              S.t('continue_watching'),
              cont
                  .map<Widget>(
                    (e) => PosterCard(
                      item: e.item,
                      type: e.type,
                      progress: e.fraction,
                      subtitle: e.subtitle,
                      onTap: () => resumeEntry(context, e),
                    ),
                  )
                  .toList(),
            ),

          // 🔸 Top 10
          if (top10.isNotEmpty)
            _row(
              S.t('top10'),
              [
                for (var i = 0; i < top10.length; i++)
                  Top10Card(
                    item: top10[i],
                    type: (top10[i]['_type'] ?? 'vod').toString(),
                    rank: i + 1,
                  ),
              ],
            ),

          // 🔸 لأنك شفت
          if (because.isNotEmpty)
            _row(
              S.t('because_you_watched'),
              because
                  .map<Widget>(
                    (it) => PosterCard(
                      item: it,
                      type: (it['_type'] ?? 'vod').toString(),
                    ),
                  )
                  .toList(),
            ),

          // 🔸 وصل حديثاً
          if (_latestM.isNotEmpty)
            _row(
              S.t('new_releases'),
              _filterWatched(_latestM, 'vod')
                  .map<Widget>((it) => PosterCard(item: it, type: 'vod'))
                  .toList(),
            ),

          _comingSoon(),
          ..._categoryRows(_movies, _vodCats, 'vod', 4),
          ..._categoryRows(_series, _serCats, 'series', 3),
          if (watched.isNotEmpty)
            _row(
              S.t('watched'),
              watched
                  .map<Widget>(
                    (e) => PosterCard(
                      item: e.item,
                      type: e.type,
                      watched: true,
                      subtitle: e.subtitle,
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  final Upcoming u;
  const _UpcomingCard({required this.u});

  @override
  Widget build(BuildContext context) {
    final w = cardWidth(context);
    return Tappable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ComingSoonScreen(u: u)),
      ),
      child: SizedBox(
        width: w,
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Poster(url: u.posterUrl, width: w, height: w * 1.42),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      color: Colors.black54,
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        fmtDate(u.date),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              u.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------- شريط الأفلام/المسلسلات الأحدث (يتبدل كل 5 ثواني) -----------
class HeroCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> entries; // {item, type}
  const HeroCarousel({super.key, required this.entries});
  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final PageController _pc = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pc.hasClients || widget.entries.isEmpty) return;
      final next = (_page + 1) % widget.entries.length;
      _pc.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pc.dispose();
    super.dispose();
  }

  Widget _buttons(dynamic item, String type, MainAxisAlignment align) {
    return Row(
      mainAxisAlignment: align,
      children: [
        FilledButton.icon(
          onPressed: () =>
              type == 'vod' ? playMovie(context, item) : openItem(context, item, type),
          icon: const Icon(Icons.play_arrow, size: 22),
          label: Text(
            S.t('play'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: () => openItem(context, item, type),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white38),
          ),
          icon: const Icon(Icons.info_outline),
          label: Text(S.t('info')),
        ),
      ],
    );
  }

  Widget _narrow(dynamic item, String type, String name) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Poster(url: posterOf(item), fit: BoxFit.cover),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xAA050505), Color(0x22050505), Color(0xF208090D)],
              stops: [0, 0.32, 1],
            ),
          ),
        ),
        Positioned(
          top: 18,
          left: 18,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFE50914),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'FEATURED',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 36,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 27,
                  height: 1.05,
                  letterSpacing: -0.4,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                type == 'vod' ? 'MOVIE  •  مختارات لك' : 'SERIES  •  تابع الحكاية',
                style: const TextStyle(
                  color: Color(0xFFE50914),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 12),
              _buttons(item, type, MainAxisAlignment.center),
            ],
          ),
        ),
      ],
    );
  }

  Widget _wide(dynamic item, String type, String name) {
    return Container(
      color: const Color(0xFF101116),
      padding: const EdgeInsets.fromLTRB(48, 24, 48, 36),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.t(type == 'vod' ? 'movies' : 'series'),
                  style: const TextStyle(color: Color(0xFFE50914), fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 38,
                    height: 1.05,
                    letterSpacing: -0.8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 20),
                _buttons(item, type, MainAxisAlignment.start),
              ],
            ),
          ),
          const SizedBox(width: 24),
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Poster(url: posterOf(item), fit: BoxFit.cover),
            ),
          ),
        ],
      ),
    );
  }

  Widget _page0(Map<String, dynamic> e) {
    final item = e['item'];
    final type = e['type'] as String;
    final name = (item['name'] ?? '').toString();
    final wide = MediaQuery.of(context).size.width >= 700;
    return GestureDetector(
      onTap: () => openItem(context, item, type),
      child: wide ? _wide(item, type, name) : _narrow(item, type, name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.entries.length;
    final wide = MediaQuery.of(context).size.width >= 700;
    return SizedBox(
      height: wide ? 420 : 470,
      child: Stack(
        children: [
          Listener(
            onPointerDown: (_) => _start(), // إعادة العد بعد اللمس
            child: PageView.builder(
              controller: _pc,
              itemCount: n,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => _page0(widget.entries[i]),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                n,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? const Color(0xFFE50914) : Colors.white38,
                    borderRadius: BorderRadius.circular(3),
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

// ======================= أفلام / مسلسلات مع الفئات =======================
class CategoryTab extends StatefulWidget {
  final String type; // vod | series
  const CategoryTab({super.key, required this.type});
  @override
  State<CategoryTab> createState() => _CategoryTabState();
}

class _CategoryTabState extends State<CategoryTab> {
  final api = XtreamAPI.instance;
  List<dynamic> _cats = [], _items = [];
  String? _cat;
  String _sort = 'popular';
  bool _loading = true, _error = false;

  @override
  void initState() {
    super.initState();
    _loadCats();
    _loadItems();
  }

  Future<void> _loadCats() async {
    final c = await api.getCategories(widget.type);
    if (mounted) setState(() => _cats = c);
  }

  Future<void> _loadItems() async {
    try {
      final l = await api.getStreams(widget.type, categoryId: _cat);
      if (!mounted) return;
      _sortItems(l);
      setState(() {
        _items = l;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  void _sortItems(List<dynamic> items) {
    int numValue(dynamic item, String key) =>
        int.tryParse('${item[key] ?? 0}') ?? 0;
    double rating(dynamic item) =>
        double.tryParse('${item['rating'] ?? item['rating_5based'] ?? 0}') ?? 0;
    switch (_sort) {
      case 'name':
        items.sort((a, b) => '${a['name'] ?? ''}'
            .toLowerCase()
            .compareTo('${b['name'] ?? ''}'.toLowerCase()));
        break;
      case 'year':
        items.sort((a, b) => numValue(b, 'year').compareTo(numValue(a, 'year')));
        break;
      case 'rating':
        items.sort((a, b) => rating(b).compareTo(rating(a)));
        break;
      default:
        items.sort((a, b) => numValue(b, 'added').compareTo(numValue(a, 'added')));
    }
  }

  void _changeSort(String? value) {
    if (value == null) return;
    setState(() {
      _sort = value;
      _sortItems(_items);
    });
  }

  void _select(String? id) {
    setState(() {
      _cat = id;
      _loading = true;
      _error = false;
    });
    _loadItems();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.sort, size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              const Text('ترتيب:', style: TextStyle(color: Colors.white70)),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _sort,
                dropdownColor: const Color(0xFF18191F),
                items: const [
                  DropdownMenuItem(value: 'popular', child: Text('الأحدث / المضاف')),
                  DropdownMenuItem(value: 'name', child: Text('الاسم')),
                  DropdownMenuItem(value: 'year', child: Text('السنة')),
                  DropdownMenuItem(value: 'rating', child: Text('التقييم')),
                ],
                onChanged: _changeSort,
              ),
            ],
          ),
        ),
        if (_cats.isNotEmpty)
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _cats.length + 1,
              itemBuilder: (context, i) {
                final String? id =
                    i == 0 ? null : _cats[i - 1]['category_id'].toString();
                final label =
                    i == 0 ? S.t('all') : (_cats[i - 1]['category_name'] ?? '').toString();
                return Padding(
                  padding: const EdgeInsets.all(6),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _cat == id,
                    onSelected: (_) => _select(id),
                  ),
                );
              },
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: ShimmerLoading(itemCount: 3))
              : _error
                  ? MessageView(text: S.t('load_fail'), onRetry: () => _select(_cat))
                  : PosterGrid(items: _items, type: widget.type),
        ),
      ],
    );
  }
}

// ======================= المفضلة =======================
class FavoritesTab extends StatefulWidget {
  const FavoritesTab({super.key});
  @override
  State<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<FavoritesTab> {
  late final Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = XtreamAPI.instance.getFavorites();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: ShimmerLoading(itemCount: 3));
        }
        return PosterGrid(items: snap.data ?? [], emptyText: S.t('no_favs'));
      },
    );
  }
}

// ======================= بحث فوري + سجل البحث =======================
class ItemSearchDelegate extends SearchDelegate<void> {
  @override
  String get searchFieldLabel => S.t('search');

  @override
  List<Widget> buildActions(BuildContext context) => [
        IconButton(
          tooltip: 'مسح البحث',
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
      ];

  @override
  Widget buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.trim().length >= 2) {
      return FutureBuilder<List<Map<String, dynamic>>>(
        future: XtreamAPI.instance.search(query),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: ShimmerLoading(itemCount: 3));
          }
          final items = snap.data ?? [];
          if (items.isEmpty) return Center(child: Text(S.t('search_none')));
          return ListView.builder(
            itemCount: items.length.clamp(0, 30).toInt(),
            itemBuilder: (context, i) {
              final item = items[i];
              final type = (item['_type'] ?? 'vod').toString();
              return ListTile(
                leading: SizedBox(width: 48, child: Poster(url: posterOf(item))),
                title: Text(
                  (item['name'] ?? '').toString(),
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
                onTap: () async {
                  await Store.addSearchQuery(query);
                  close(context, null);
                  openItem(context, item, type);
                },
              );
            },
          );
        },
      );
    }
    return FutureBuilder<List<String>>(
      future: Store.searchHistory(),
      builder: (context, snap) {
        final history = snap.data ?? <String>[];
        if (history.isEmpty) return Center(child: Text(S.t('search_prompt')));
        return ListView(
          children: [
            ListTile(
              title: const Text('عمليات البحث الأخيرة'),
              trailing: TextButton(
                onPressed: () async {
                  await Store.clearSearchHistory();
                  showSuggestions(context);
                },
                child: const Text('مسح'),
              ),
            ),
            for (final q in history)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(q),
                onTap: () {
                  query = q;
                  showResults(context);
                },
                trailing: IconButton(
                  icon: const Icon(Icons.north_west),
                  onPressed: () {
                    query = q;
                    showSuggestions(context);
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    if (query.trim().length < 2) return Center(child: Text(S.t('search_min')));
    Store.addSearchQuery(query);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: XtreamAPI.instance.search(query),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: ShimmerLoading(itemCount: 3));
        }
        return PosterGrid(items: snap.data ?? [], emptyText: S.t('search_none'));
      },
    );
  }
}

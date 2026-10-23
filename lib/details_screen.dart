import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'epg_screen.dart';
import 'episodes.dart';
import 'player_screen.dart';
import 'store.dart';
import 'strings.dart';
import 'tmdb.dart';
import 'user_data.dart';
import 'widgets.dart';

class DetailsScreen extends StatefulWidget {
  final dynamic item;
  final String type; // vod | series | live
  const DetailsScreen({super.key, required this.item, required this.type});

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  final api = XtreamAPI.instance;
  late final String _id;
  Map<String, dynamic>? _info;
  Map<String, dynamic>? _tmdbInfo;
  List<Map<String, String>> _epg = [];
  bool _loading = true;
  bool _isFav = false;
  bool _inMyList = false;
  int? _rating; // 1 = إعجاب، 2 = غير مهتم

  @override
  void initState() {
    super.initState();
    _id = XtreamAPI.idOf(widget.item, widget.type);
    _load();
  }

  Future<void> _load() async {
    try {
      _isFav = await api.isFavorite(widget.type, _id);
    } catch (_) {}
    try {
      _inMyList = await UD.inMyList(widget.type, _id);
    } catch (_) {}
    try {
      _rating = await UD.rating(widget.type, _id);
    } catch (_) {}
    try {
      if (widget.type == 'vod') {
        _info = await api.getVodInfo(_id);
      } else if (widget.type == 'series') {
        _info = await api.getSeriesInfo(_id);
      } else {
        _epg = await api.getShortEPG(_id);
      }
    } catch (_) {}
    if (widget.type == 'vod' || widget.type == 'series') {
      try {
        final key = await Store.tmdbKey();
        final name = (widget.item['name'] ?? '').toString();
        _tmdbInfo = await Tmdb.enrichTitle(key, name, widget.type, S.tmdbLang);
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleFav() async {
    final now = await api.toggleFavorite(widget.type, widget.item);
    if (mounted) setState(() => _isFav = now);
  }

  Future<void> _toggleMyList() async {
    final added = await UD.toggleMyList(widget.type, widget.item);
    if (!mounted) return;
    setState(() => _inMyList = added);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added ? S.t('added_to_list') : S.t('removed_from_list')),
      ),
    );
  }

  Future<void> _rate(int value) async {
    if (_rating == value) {
      await UD.clearRating(widget.type, _id);
      if (mounted) setState(() => _rating = null);
      return;
    }
    await UD.setRating(widget.type, _id, value);
    if (mounted) setState(() => _rating = value);
  }

  Future<void> _share(String title) async {
    final text = '${S.t('share_text')}: $title';
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${S.t('share')} — $text')),
      );
    } catch (_) {}
  }

  void _play(
    String url,
    String title, {
    WatchEntry? watch,
    bool live = false,
    String? fallback,
    List<Map<String, dynamic>>? episodes,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          url: url,
          title: title,
          watch: watch,
          fallbackUrl: fallback,
          isLive: live,
          episodes: episodes,
          itemType: widget.type,
          seriesId: widget.type == 'series' ? _id : null,
        ),
      ),
    );
  }

  /// يرجع المواسم والحلقات بشكل موحد.
  Map<String, List<dynamic>> _episodes() {
    final e = _info?['episodes'];
    final out = <String, List<dynamic>>{};
    if (e is Map) {
      e.forEach((k, v) => out[k.toString()] = v is List ? v : <dynamic>[]);
    } else if (e is List) {
      for (var i = 0; i < e.length; i++) {
        out['${i + 1}'] = e[i] is List ? List<dynamic>.from(e[i] as List) : <dynamic>[];
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final rawInfo = _info?['info'];
    final Map infoMap = rawInfo is Map ? rawInfo : {};
    final title = (infoMap['name'] ?? widget.item['name'] ?? '').toString();
    final plot = (infoMap['plot'] ??
            infoMap['description'] ??
            _tmdbInfo?['overview'] ??
            '')
        .toString();
    final poster = posterOf(widget.item);
    final backdropPath = (_tmdbInfo?['backdrop_path'] ?? '').toString();
    final backdrop = backdropPath.isEmpty
        ? poster
        : 'https://image.tmdb.org/t/p/w1280$backdropPath';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: const Color(0xFF0B1220),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Poster(url: backdrop, fit: BoxFit.cover),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x22000000), Color(0xFF090909)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _isFav ? Icons.favorite : Icons.favorite_border,
                  color: _isFav ? Colors.red : Colors.white,
                ),
                onPressed: _toggleFav,
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: pageInset(context),
                vertical: 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_tmdbInfo != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        if ((_tmdbInfo!['release_date'] ??
                                    _tmdbInfo!['first_air_date'] ??
                                    '')
                                .toString()
                                .isNotEmpty)
                          _metaChip(
                            (_tmdbInfo!['release_date'] ??
                                    _tmdbInfo!['first_air_date'])
                                .toString()
                                .split('-')
                                .first,
                          ),
                        if (_tmdbInfo!['vote_average'] != null)
                          _metaChip(
                            '★ ${(num.tryParse('${_tmdbInfo!['vote_average']}') ?? 0).toStringAsFixed(1)}/10',
                          ),
                        if (_tmdbInfo!['runtime'] != null &&
                            _tmdbInfo!['runtime'] is num &&
                            (_tmdbInfo!['runtime'] as num) > 0)
                          _metaChip('${_tmdbInfo!['runtime']} min'),
                        if (_tmdbInfo!['number_of_seasons'] != null)
                          _metaChip('${_tmdbInfo!['number_of_seasons']} seasons'),
                      ],
                    ),
                  ],
                  if (plot.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(plot, style: const TextStyle(color: Colors.grey)),
                  ],

                  const SizedBox(height: 16),
                  _actions(title),

                  if (plot.isNotEmpty) const SizedBox(height: 20),
                  if (_tmdbInfo != null) ..._tmdbSections(),
                  ..._body(title),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ====== أزرار الإجراءات (NetFlix style) ======
  Widget _actions(String title) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () {
              if (widget.type == 'vod') {
                final w = WatchEntry.forMovie(widget.item);
                _play(api.buildMovieUrl(_id, w.ext), title, watch: w);
              } else if (widget.type == 'live') {
                _play(
                  api.buildLiveUrl(_id),
                  title,
                  live: true,
                  fallback: api.buildLiveUrlTs(_id),
                );
              } else {
                final eps = _episodes();
                final first = eps.values.isNotEmpty && eps.values.first.isNotEmpty
                    ? eps.values.first.first
                    : null;
                if (first == null) return;
                final ext = (first['container_extension'] ?? 'mp4').toString();
                final w = WatchEntry.forEpisode(
                  widget.item,
                  first['id'].toString(),
                  ext,
                  'S1 E${first['episode_num'] ?? ''}',
                );
                _play(
                  api.buildSeriesUrl(w.mediaId, w.ext),
                  w.fullTitle,
                  watch: w,
                  episodes: flattenEpisodes(_info?['episodes']),
                );
              }
            },
            icon: const Icon(Icons.play_arrow),
            label: Text(
              widget.type == 'live' ? S.t('watch_channel') : S.t('play'),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _roundButton(
          icon: Icons.info_outline,
          tooltip: S.t('info'),
          onTap: () {},
        ),
        _roundButton(
          icon: _inMyList ? Icons.check_circle : Icons.add_circle_outline,
          tooltip: S.t('add_to_list'),
          color: _inMyList ? const Color(0xFFE50914) : Colors.white,
          onTap: _toggleMyList,
        ),
        _roundButton(
          icon: Icons.thumb_up,
          tooltip: S.t('liked'),
          color: _rating == 1 ? const Color(0xFFE50914) : Colors.white,
          onTap: () => _rate(1),
        ),
        _roundButton(
          icon: Icons.thumb_down,
          tooltip: S.t('disliked'),
          color: _rating == 2 ? const Color(0xFFE50914) : Colors.white,
          onTap: () => _rate(2),
        ),
        _roundButton(
          icon: Icons.share,
          tooltip: S.t('share'),
          onTap: () => _share(title),
        ),
      ],
    );
  }

  Widget _roundButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, color: color),
    );
  }

  Widget _metaChip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      );

  List<Widget> _tmdbSections() {
    final info = _tmdbInfo!;
    final widgets = <Widget>[];
    final credits = info['credits'];
    final cast = credits is Map && credits['cast'] is List
        ? List<dynamic>.from(credits['cast'] as List)
        : <dynamic>[];
    if (cast.isNotEmpty) {
      widgets.add(const SizedBox(height: 20));
      widgets.add(
        const Text(
          'طاقم التمثيل',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      );
      widgets.add(const SizedBox(height: 8));
      widgets.add(
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cast.take(12).length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final person = cast[i] as Map;
              final profile = (person['profile_path'] ?? '').toString();
              return SizedBox(
                width: 82,
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 29,
                      backgroundColor: Colors.white12,
                      backgroundImage: profile.isEmpty
                          ? null
                          : NetworkImage(
                              'https://image.tmdb.org/t/p/w185$profile',
                            ),
                      child: profile.isEmpty
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      (person['name'] ?? '').toString(),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    }
    final videos = info['videos'];
    final results = videos is Map && videos['results'] is List
        ? List<dynamic>.from(videos['results'] as List)
        : <dynamic>[];
    dynamic trailer;
    for (final v in results) {
      if (v is Map && v['site'] == 'YouTube' && v['type'] == 'Trailer') {
        trailer = v;
        break;
      }
    }
    if (trailer is Map && (trailer['key'] ?? '').toString().isNotEmpty) {
      widgets.add(const SizedBox(height: 16));
      widgets.add(
        OutlinedButton.icon(
          icon: const Icon(Icons.ondemand_video),
          label: const Text('مشاهدة التريلر'),
          onPressed: () => launchUrl(
            Uri.parse(
              'https://www.youtube.com/watch?v=${trailer['key']}',
            ),
            mode: LaunchMode.externalApplication,
          ),
        ),
      );
    }
    final similar = info['similar'];
    final sims = similar is Map && similar['results'] is List
        ? List<dynamic>.from(similar['results'] as List)
        : <dynamic>[];
    if (sims.isNotEmpty) {
      widgets.add(const SizedBox(height: 20));
      widgets.add(
        const Text(
          'أعمال مشابهة',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      );
      widgets.add(const SizedBox(height: 8));
      widgets.add(
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: sims.take(12).length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final sim = sims[i] as Map;
              final path = (sim['poster_path'] ?? '').toString();
              final t = (sim['title'] ?? sim['name'] ?? '').toString();
              return SizedBox(
                width: 95,
                child: Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Poster(
                          url: path.isEmpty
                              ? ''
                              : 'https://image.tmdb.org/t/p/w342$path',
                          width: 95,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      t,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    }
    return widgets;
  }

  List<Widget> _body(String title) {
    if (widget.type == 'vod') {
      final md = _info?['movie_data'];
      final ext = (widget.item['container_extension'] ??
              (md is Map ? md['container_extension'] : null) ??
              'mp4')
          .toString();
      return [
        _playButton(S.t('watch_movie'), () {
          final w = WatchEntry.forMovie(widget.item);
          _play(api.buildMovieUrl(_id, ext), title, watch: w);
        }),
      ];
    }

    if (widget.type == 'live') {
      return [
        _playButton(
          S.t('watch_channel'),
          () => _play(
            api.buildLiveUrl(_id),
            title,
            live: true,
            fallback: api.buildLiveUrlTs(_id),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white38),
            minimumSize: const Size(double.infinity, 46),
          ),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EpgScreen(
                streamId: _id,
                channelName: title,
                logoUrl: posterOf(widget.item),
              ),
            ),
          ),
          icon: const Icon(Icons.schedule),
          label: Text(S.t('epg_guide')),
        ),
        const SizedBox(height: 20),
        if (_epg.isNotEmpty) ...[
          Text(
            S.t('epg'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._epg.map(
            (e) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(e['title'] ?? ''),
              subtitle: Text(
                e['description'] ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                e['start'] ?? '',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      ];
    }

    // مسلسل
    final eps = _episodes();
    if (eps.isEmpty) return [Text(S.t('no_episodes'))];
    final seasons = eps.keys.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    return [
      Text(
        S.t('seasons'),
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 10),
      for (final s in seasons)
        ExpansionTile(
          title: Text('${S.t('season')} $s'),
          children: [
            for (final ep in eps[s]!)
              ListTile(
                leading: const Icon(
                  Icons.play_circle,
                  color: Color(0xFFE50914),
                ),
                title: Text('${S.t('episode')} ${ep['episode_num'] ?? ''}'),
                subtitle: (ep['title'] ?? '').toString().isEmpty
                    ? null
                    : Text(ep['title'].toString()),
                onTap: () {
                  final epId = ep['id'].toString();
                  final ext = (ep['container_extension'] ?? 'mp4').toString();
                  final sub = 'S$s E${ep['episode_num'] ?? ''}';
                  final w = WatchEntry.forEpisode(widget.item, epId, ext, sub);
                  _play(
                    api.buildSeriesUrl(epId, ext),
                    w.fullTitle,
                    watch: w,
                    episodes: flattenEpisodes(_info?['episodes']),
                  );
                },
              ),
          ],
        ),
      const SizedBox(height: 10),
      _skipMarkersRow(),
    ];
  }

  /// إعدادات تخطي المقدمة (تظهر في صفحة المسلسل).
  Widget _skipMarkersRow() {
    return FutureBuilder<SkipRange?>(
      future: UD.skipIntro(_id),
      builder: (context, snap) {
        final r = snap.data;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.fast_forward, color: Color(0xFFE50914)),
          title: Text(S.t('skip_intro')),
          subtitle: Text(
            r == null
                ? S.t('set_skip_range')
                : '${S.t('skip_intro')}: ${r.start}s → ${r.end}s',
          ),
          trailing: r == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () async {
                    await UD.clearSkipIntro(_id);
                    if (mounted) setState(() {});
                  },
                ),
        );
      },
    );
  }

  Widget _playButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFE50914),
          foregroundColor: Colors.white,
        ),
        onPressed: onPressed,
        icon: const Icon(Icons.play_arrow),
        label: Text(label),
      ),
    );
  }
}

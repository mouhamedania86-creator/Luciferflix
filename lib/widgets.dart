import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'details_screen.dart';
import 'player_screen.dart';
import 'store.dart';
import 'strings.dart';

/// Placeholder لامع يظهر أثناء تحميل المحتوى بدل دائرة الانتظار.
class ShimmerLoading extends StatefulWidget {
  final int itemCount;
  const ShimmerLoading({super.key, this.itemCount = 5});
  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _block(double width, double height, {double radius = 8}) => AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(-1.5 + 3 * _controller.value, 0),
            end: Alignment(-0.5 + 3 * _controller.value, 0),
            colors: const [Color(0xFF202733), Color(0xFF3B4656), Color(0xFF202733)],
            stops: const [0.1, 0.5, 0.9],
          ).createShader(bounds),
          blendMode: BlendMode.srcATop,
          child: child,
        ),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFF202733),
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _block(double.infinity, 190, radius: 14),
          const SizedBox(height: 22),
          _block(170, 18),
          const SizedBox(height: 12),
          SizedBox(
            height: 218,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.itemCount,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _block(118, 158, radius: 10),
                  const SizedBox(height: 9),
                  _block(100, 12),
                  const SizedBox(height: 6),
                  _block(70, 10),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _block(145, 18),
          const SizedBox(height: 12),
          SizedBox(
            height: 218,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.itemCount,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _block(118, 158, radius: 10),
                  const SizedBox(height: 9),
                  _block(100, 12),
                  const SizedBox(height: 6),
                  _block(70, 10),
                ],
              ),
            ),
          ),
        ],
      );
}

String posterOf(dynamic item) =>
    (item['stream_icon'] ?? item['cover'] ?? '').toString();

String fmtDate(DateTime? d) {
  if (d == null) return '';
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ---------------- مقاسات حسب الشاشة (هاتف / كمبيوتر / تلفزة) ----------------
double cardWidth(BuildContext c) {
  final w = MediaQuery.of(c).size.width;
  if (w >= 1400) return 180;
  if (w >= 900) return 150;
  return 120;
}

double cardRowHeight(BuildContext c) => cardWidth(c) * 1.42 + 76;

/// هامش أفقي يخلي المحتوى في الوسط (أقصى عرض 900) على الشاشات الكبيرة.
double pageInset(BuildContext c) =>
    math.max(16.0, (MediaQuery.of(c).size.width - 900) / 2);

double loginInset(BuildContext c) =>
    math.max(24.0, (MediaQuery.of(c).size.width - 420) / 2);

void openItem(BuildContext context, dynamic item, String type) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => DetailsScreen(item: item, type: type)),
  );
}

/// تشغيل فيلم مباشرة (يكمل من آخر نقطة تلقائياً).
void playMovie(BuildContext context, dynamic item) {
  final api = XtreamAPI.instance;
  final w = WatchEntry.forMovie(item);
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PlayerScreen(
        url: api.buildMovieUrl(w.mediaId, w.ext),
        title: w.fullTitle,
        watch: w,
        itemType: 'vod',
      ),
    ),
  );
}

/// متابعة المشاهدة من "تابع المشاهدة".
void resumeEntry(BuildContext context, WatchEntry e) {
  final api = XtreamAPI.instance;
  final url = e.type == 'vod'
      ? api.buildMovieUrl(e.mediaId, e.ext)
      : api.buildSeriesUrl(e.mediaId, e.ext);
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PlayerScreen(
        url: url,
        title: e.fullTitle,
        watch: e,
        itemType: e.type,
        seriesId: e.type == 'series' ? e.itemId : null,
      ),
    ),
  );
}

/// عنصر قابل للنقر باللمس أو الماوس أو ريموت التلفزة (إطار يبين العنصر المحدد).
class Tappable extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  final double radius;
  const Tappable({
    super.key,
    required this.onTap,
    required this.child,
    this.radius = 8,
  });

  @override
  State<Tappable> createState() => _TappableState();
}

class _TappableState extends State<Tappable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap();
          return null;
        }),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius + 2),
            border: Border.all(
              color: _focused ? const Color(0xFFE50914) : Colors.transparent,
              width: 3,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class Poster extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final double? width, height;
  const Poster({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  Widget _placeholder() => Container(
        width: width,
        height: height,
        color: Colors.grey[850],
        child: const Icon(Icons.movie, color: Colors.grey),
      );

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return _placeholder();
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      errorWidget: (_, __, ___) => _placeholder(),
    );
  }
}

/// ====== عناصر جديدة (NetFlix style) ======

/// علامة "تمت المشاهدة" (دائرة حمراء بعلامة صح).
class WatchedBadge extends StatelessWidget {
  final double size;
  const WatchedBadge({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(size * 0.18),
      decoration: const BoxDecoration(
        color: Color(0xFFE50914),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.check, size: size * 0.7, color: Colors.white),
    );
  }
}

/// شريط عنوان قسم مع زر "شوف الكل" اختياري.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: const TextStyle(color: Color(0xFFE50914)),
              ),
            ),
        ],
      ),
    );
  }
}

/// حالة فارغة (قائمة فارغة / لا نتائج).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: Colors.white24),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// بطاقة Top 10: رقم كبير beside البوستر.
class Top10Card extends StatelessWidget {
  final dynamic item;
  final String type;
  final int rank;
  final VoidCallback? onTap;

  const Top10Card({
    super.key,
    required this.item,
    required this.type,
    required this.rank,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final w = cardWidth(context);
    return Tappable(
      onTap: onTap ?? () => openItem(context, item, type),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: 46,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFE50914),
                fontSize: 52,
                fontWeight: FontWeight.w900,
                height: 0.9,
                shadows: [
                  Shadow(color: Colors.black87, blurRadius: 10, offset: Offset(2, 4)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 2),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Poster(
                  url: posterOf(item),
                  width: w,
                  height: w * 1.42,
                  fit: type == 'live' ? BoxFit.contain : BoxFit.cover,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: w,
                child: Text(
                  (item['name'] ?? '').toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// بطاقة أفقية (للصفوف) مع خط أحمر للتقدم وعلامة "تمت مشاهدته".
class PosterCard extends StatelessWidget {
  final dynamic item;
  final String type;
  final double? width, height;
  final double? progress;
  final bool watched;
  final String? subtitle;
  final VoidCallback? onTap;

  /// 👈 جديد
  final bool inMyList;
  final bool liked;
  final bool blocked;
  final VoidCallback? onLongPress;

  const PosterCard({
    super.key,
    required this.item,
    required this.type,
    this.width,
    this.height,
    this.progress,
    this.watched = false,
    this.subtitle,
    this.onTap,
    this.inMyList = false,
    this.liked = false,
    this.blocked = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final w = width ?? cardWidth(context);
    final h = height ?? w * 1.42;
    return Tappable(
      onTap: onTap ?? () => openItem(context, item, type),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Poster(
                  url: posterOf(item),
                  width: w,
                  height: h,
                  fit: type == 'live' ? BoxFit.contain : BoxFit.cover,
                ),
                if (progress != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      color: Colors.red,
                      backgroundColor: Colors.black54,
                    ),
                  ),
                if (watched)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: const WatchedBadge(),
                  ),
                if (inMyList)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.white24,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, size: 14, color: Colors.white),
                    ),
                  ),
                if (liked)
                  Positioned(
                    bottom: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE50914),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.thumb_up, size: 12, color: Colors.white),
                    ),
                  ),
                if (blocked)
                  Positioned.fill(
                    child: Container(color: Colors.black54),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            (item['name'] ?? '').toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
          if (subtitle != null && subtitle!.isNotEmpty)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
        ],
      ),
    );
  }
}

/// بطاقة تظهر معلومات إضافية عند التحويم/التركيز (Desktop + TV).
class HoverPosterCard extends StatefulWidget {
  final dynamic item;
  final String type;
  final double? progress;
  final bool watched;
  final String? subtitle;

  const HoverPosterCard({
    super.key,
    required this.item,
    required this.type,
    this.progress,
    this.watched = false,
    this.subtitle,
  });

  @override
  State<HoverPosterCard> createState() => _HoverPosterCardState();
}

class _HoverPosterCardState extends State<HoverPosterCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final w = cardWidth(context);
    final h = w * 1.42;
    final name = (widget.item['name'] ?? '').toString();
    final rating = (widget.item['rating'] ?? widget.item['rating_5based'] ?? '')
        .toString();

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tappable(
        onTap: () => openItem(context, widget.item, widget.type),
        child: SizedBox(
          width: w,
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    Poster(
                      url: posterOf(widget.item),
                      width: w,
                      height: h,
                      fit: widget.type == 'live' ? BoxFit.contain : BoxFit.cover,
                    ),
                    if (widget.progress != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: widget.progress,
                          minHeight: 4,
                          color: Colors.red,
                          backgroundColor: Colors.black54,
                        ),
                      ),
                    if (widget.watched)
                      const Positioned(top: 6, right: 6, child: WatchedBadge()),
                    // طبقة المعلومات (تظهر عند التحويم)
                    AnimatedOpacity(
                      opacity: _hover ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Container(
                        width: w,
                        height: h,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.05),
                              Colors.black.withOpacity(0.85),
                            ],
                          ),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (rating.isNotEmpty)
                              Text(
                                '★ $rating',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white70,
                                ),
                              ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _round(Icons.play_arrow, () {
                                  if (widget.type == 'vod') {
                                    playMovie(context, widget.item);
                                  } else {
                                    openItem(context, widget.item, widget.type);
                                  }
                                }),
                                const SizedBox(width: 8),
                                _round(Icons.info_outline, () {
                                  openItem(context, widget.item, widget.type);
                                }),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
              if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                Text(
                  widget.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _round(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(
            color: Colors.white24,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      );
}

class PosterGrid extends StatelessWidget {
  final List<dynamic> items;
  final String? type; // إذا كان null يؤخذ النوع من الحقل _type
  final String? emptyText;
  const PosterGrid({
    super.key,
    required this.items,
    this.type,
    this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return EmptyState(message: emptyText ?? S.t('no_content'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        childAspectRatio: 0.6,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        final t = (item['_type'] ?? type ?? 'vod').toString();
        return Tappable(
          radius: 10,
          onTap: () => openItem(context, item, t),
          child: Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Poster(
                    url: posterOf(item),
                    fit: t == 'live' ? BoxFit.contain : BoxFit.cover,
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
        );
      },
    );
  }
}

class MessageView extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;
  const MessageView({super.key, required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: Text(S.t('retry'))),
          ],
        ],
      ),
    );
  }
}

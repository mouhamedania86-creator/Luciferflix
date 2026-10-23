# MovieFlix v1.1.0 — التحديثة "Netflix-like"

## 📦 كيفاش تطبّق التحديثة

1. فكّ ضغط الـ zip.
2. انسخ **محتوى `lib/`** فوق `lib/` في مشروعك (الملفات القديمة تنبدل، الجديدة تنضاف).
3. انسخ `pubspec.yaml` و `.github/workflows/build.yml` و `README.md` فوق نسخك.
4. نفّذ:

```bash
flutter pub get
flutter run
```

الملفات القديمة اللي ما touchedntش (مثل `store.dart`, `tmdb.dart`, `episodes.dart`, `disk_cache.dart`,
`device.dart`, `notifier.dart`, `history_screen.dart`, `notifications_screen.dart`,
`coming_soon_screen.dart`) — بقوا كما همو ⚠️ **ما تنسخهمش** إلا إذا حبيت تستعمل
النسخة المجدولة ديالهم.

---

## 🆕 ملفات جديدة (زيدهم)

| الملف | شنو فيه |
|---|---|
| `lib/user_data.dart` | طبقة البيانات الجديدة: البروفايلات + PIN، قائمتي، التقييمات، تخطي المقدمة/النهاية، الرقابة parental، الإحصائيات، النسخ الاحتياطي |
| `lib/recommend.dart` | "لأنك شفت" + Top 10 (توصيات محلية) |
| `lib/quality.dart` | تحويل ستريمات Xtream لخيارات جودة (4K/FHD/HD/SD) |
| `lib/player_overlays.dart` | عناصر المشغّل: زر التخطي، لوحة الحلقة الجاية بالعد التنازلي، إحصائيات التشغيل، رسالة الاستئناف، مؤشر ±10s |
| `lib/mini_player.dart` | المشغّل المصغّر (تصغّر الفيديو ويبقى شغّال) |
| `lib/live_screen.dart` | التلفزيون المباشر الجديد (فئات + بحث + مفضلة + EPG) |
| `lib/epg_screen.dart` | دليل البرامج + إعادة (Timeshift) |
| `lib/my_list_screen.dart` | شاشة "قائمتي" |
| `lib/top10_screen.dart` | شاشة Top 10 |

## ✏️ ملفات معدّلة (بدّلهم)

| الملف | شنو تغيّر |
|---|---|
| `lib/player_screen.dart` | إعادة كتابة: تخطي المقدمة/النهاية، لوحة الحلقة الجاية، اختيار الجودة، الصوت/الترجمة، مؤقت النوم، إحصائيات، أزرار 10s/30s، المشغّل المصغّر، Wakelock، عدّاد Top 10 |
| `lib/home_screen.dart` | 6 تبويبات، صف Top 10، صف "لأنك شفت"، "وصل حديثاً"، إخفاء ما شفته، الرقابة parental، تبويب التلفاز الجديد |
| `lib/widgets.dart` | `Top10Card`, `WatchedBadge`, `SectionHeader`, `EmptyState`, `HoverPosterCard` + `PosterCard` بمعطيات جديدة (قائمتي/إعجاب) |
| `lib/details_screen.dart` | أزرار: تشغيل، مفضلة، قائمتي، تقييم، مشاركة + قسم تخطي المقدمة + زر دليل البرامج |
| `lib/settings_screen.dart` | البروفايل، قائمتي، الإحصائيات، الرقابة parental، وضع الأطفال، ترشيد البيانات، إخفاء ما شفته، النسخ الاحتياطي |
| `lib/login_screen.dart` | اختيار/تبديل البروفايل |
| `lib/profile_screen.dart` | **جديد**: شبكة البروفايلات + PIN + إنشاء/تعديل/حذف |
| `lib/stats_screen.dart` | **جديد**: إحصائيات + رسم بياني للأيام السبعة |
| `lib/main.dart` | بوابة البروفايل (قفل الأطفال) + المشغّل المصغّر فوق كل الشاشات + تحديث رقم الإصدار |
| `lib/onboarding_screen.dart` | يمرّ على بوابة البروفايل |
| `lib/api.dart` | `getVodStreams` (الجودات)، `getEPG`، `buildTimeshiftUrl`، `getLiveInfo`، عميل HTTP مشترك (أسرع) |
| `lib/strings.dart` | +90 مفتاح ترجمة (عربي/فرنسي/إنجليزي) + توحيد الهوية MovieFlix |
| `pubspec.yaml` | `wakelock_plus` + الإصدار 1.1.0+2 |
| `.github/workflows/build.yml` | job لويندوز + job iOS + صلاحيات WAKE_LOCK + hardwareAccelerated |

---

## ⚠️ قبل ما تبدا

1. **`flutter pub get`** (لأن `wakelock_plus` زيد).
2. **ما تحطّش `android/`** في المشروع — الـ CI يولّدها. أي تعديل Gradle لازم يكون في `.github/workflows/build.yml`.
3. **النسخ الاحتياطي**: أول ما تدخل الإعدادات، صدّر بياناتك (تصدير/استيراد) باش ما تخسرش المفضلة.
4. **وضع الأطفال/الرقابة parental** تنطبق على البروفايل النشط فقط.
5. لو استعملت `server.json` فيه `server/username/password`، خليه في سيرفر خاص بيك — الإعدادات تخدم لكل المستخدمين.

---

## 🧪 اختبر بالترتيب

1. `flutter analyze` — لازم يطلع 0 errors.
2. افتح التطبيق → البروفايل الافتراضي → دخّل ببياناتك.
3. جرّب: المفضلة، قائمتي، التقييم، Top 10 (شغّل فيلمين باش يطلع).
4. جرّب المشغّل: تخطي المقدمة (من صفحة المسلسل "اضبط البداية/النهاية")، الحلقة الجاية، الجودة، مصغّر.
5. جرّب التلفاز: تبويب "مباشر" + EPG + إعادة.
6. جرّب الإحصائيات بعد المشاهدة + تصدير/استيراد.

# 🚀 دليل النشر النهائي — Neon Horde

كل شيء مبني وجاهز. المتبقي خطوات لا يستطيع الوكيل تنفيذها لأنها تتطلب
هويتك أو حسابك المدفوع. المدة الإجمالية بعد تفعيل العضوية: **~15 دقيقة عمل يدوي**.

## 1) عضوية Apple Developer (إن لم تكتمل بعد)
- سجّل في https://developer.apple.com/programs/enroll ($99/سنة) بحساب
  belal.alswerki@gmail.com — **الاسم القانوني مطابقاً لهويتك + فعّل المصادقة الثنائية**.
- التفعيل رسمياً 24-48 ساعة (تقارير 2026 تذكر أحياناً أسابيع — قدّم مبكراً).

## 2) مفتاح App Store Connect API (~3 دقائق)
1. App Store Connect → Users and Access → Integrations → App Store Connect API
2. Generate API Key بدور **Admin** → نزّل ملف `.p8` (يُحمَّل مرة واحدة فقط!)
3. أنشئ الملف `~/.appstoreconnect/neonhorde.env`:
```
ASC_KEY_ID=XXXXXXXXXX
ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ASC_KEY_PATH=$HOME/.appstoreconnect/AuthKey_XXXXXXXXXX.p8
REVIEW_FIRST_NAME=Belal
REVIEW_LAST_NAME=Alswerki
REVIEW_PHONE=+XXXXXXXXXXX
REVIEW_EMAIL=belal.alswerki@gmail.com
```

## 3) إنشاء سجل التطبيق (~دقيقتان — لا يمكن أتمتته بمفتاح API)
App Store Connect → My Apps → **+** → New App:
- Platform: iOS | Name: `Neon Horde — Arena Survivor`
  (إن كان محجوزاً: `Neon Horde: Survive`)
- Primary language: English (U.S.) | Bundle ID: `com.belalalswerki.neonhorde`
- SKU: `neonhorde-001`

وأنت هناك أنجز أيضاً (إلزاميات الإرسال):
- **Age rating questionnaire**: الأجوبة الجاهزة في `STORE_ANSWERS.md` (المتوقع 9+)
- **App Privacy** → "we do not collect data" → **Data Not Collected**
- **EU DSA**: أقرّ بحالة **Non-trader** (Business → Digital Services Act)
- **Pricing**: Free (0) + كل الدول

## 4) نشر موقع الدعم/الخصوصية (~دقيقتان — النشر العلني يحتاج قرارك)
```bash
cd /Users/devbms/Games/NeonHorde/site
gh repo create neonhorde-site --public --source . --push
gh api -X POST repos/dev1bms/neonhorde-site/pages -f 'source[branch]=main' -f 'source[path]=/'
```
الروابط في الميتاداتا مضبوطة مسبقاً على:
`https://dev1bms.github.io/neonhorde-site/` و `…/privacy.html`

## 5) الإطلاق (أمر واحد)
```bash
cd /Users/devbms/Games/NeonHorde && ./scripts/release.sh
```
السكربت: يتحقق من المفاتيح → يبني أرشيفاً موقّعاً سحابياً → يرفع إلى TestFlight
(3 محاولات — عثرات التوقيع السحابي معروفة) → يدفع الميتاداتا والست لقطات →
يقدّم للمراجعة بملاحظات المراجع الجاهزة.

## 6) بعد الإرسال
- المراجعة عادة 24-48 ساعة. أي رفض يصل في Resolution Center — عالج الملاحظة
  وأعد `fastlane release`.
- على TestFlight جرّب على جهاز حقيقي: الاهتزاز (لا يعمل على المحاكي) وثبات
  الإطارات على أقدم جهاز لديك.

## اختيارية (جودة أعلى)
- صوتيات AI بدل المُصنّع: ولّد ملفات §6 من ART_PROMPTS.md وضعها في
  `ArtDrop/audio/` باسم `ext_<name>.mp3` ثم انسخها إلى `App/Resources/Audio/`
  وأعد البناء — تحلّ تلقائياً محل المولّد.
- أصول فنية فردية أنقى (بلا أشباح ملصقات): ولّد كل برومبت من ART_PROMPTS.md
  في صورة مستقلة، ضعها بأسمائها في `ArtDrop/` وأخبر الوكيل ليعيد الدمج.

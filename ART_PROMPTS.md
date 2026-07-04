# Forest Warrior — AI Art Generation Prompts

**للمالك:** انسخ كل برومبت كما هو إلى ChatGPT (توليد الصور) أو Midjourney/DALL·E.
بعد التوليد، احفظ كل صورة بالاسم المذكور داخل المجلد:
`/Users/devbms/Games/NeonHorde/ArtDrop/`
ثم قل لي "الصور جاهزة" وسأدمجها في اللعبة.

**قواعد مهمة لكل الصور:**
- اطلب دائماً: خلفية شفافة (transparent background) إلا حيث مذكور غير ذلك
- ارفض أي صورة فيها نص أو توقيع أو علامة مائية
- إن خرجت الإطارات غير متساقة في sprite sheet، أعد التوليد أو اطلب "same character, identical style"
- الحجم المطلوب مذكور في كل برومبت (ولو خرج مقاس مختلف سأتعامل معه)

---

## كتلة الأسلوب المشتركة (تُلصق في نهاية كل برومبت)

> **STYLE BLOCK:** hand-painted stylized fantasy game art, rich painterly detail,
> dark enchanted forest palette (deep greens, teal moonlight, warm amber torch
> highlights), strong silhouette readability for a mobile game viewed from a
> top-down ¾ angle, crisp rim lighting, no outlines, no text, no watermark,
> transparent PNG background.

## كتلة الشخصية الثابتة (تُلصق في كل برومبت يخص البطل)

> **HERO BLOCK (must stay identical across all images):** a young forest
> ranger-warrior, athletic build, short dark hair, weathered light-leather armor
> with a moss-green hooded cloak (hood down), a faintly glowing teal short-sword
> in his right hand, determined expression, seen from a top-down ¾ game
> perspective (like classic action-RPG sprites), facing RIGHT.

---

## 1) البطل — sprite sheets (أهم الصور)

### P1 — player_run.png (1536×512)
```
Sprite sheet for a mobile action game: EXACTLY 6 frames in a single horizontal
row, each frame 256×512 px, of the SAME character in a smooth run cycle facing
right (contact, down, pass, up positions). Identical proportions, identical
lighting and camera angle in every frame, evenly spaced, transparent background.
[HERO BLOCK] [STYLE BLOCK]
```

### P2 — player_idle.png (1024×512)
```
Sprite sheet: EXACTLY 4 frames in one horizontal row, 256×512 px each, of the
SAME character standing in a ready combat idle, subtle breathing motion between
frames (sword slightly rising/falling), facing right. Identical style across
frames, transparent background.
[HERO BLOCK] [STYLE BLOCK]
```

### P3 — player_attack.png (1536×512)
```
Sprite sheet: EXACTLY 6 frames in one horizontal row, 256×512 px each, of the
SAME character performing one fast glowing-sword slash from wind-up to
follow-through, teal energy arc trailing the blade in frames 3-5, facing right.
Identical style across frames, transparent background.
[HERO BLOCK] [STYLE BLOCK]
```

### P4 — player_death.png (1536×512)
```
Sprite sheet: EXACTLY 6 frames in one horizontal row, 256×512 px each, of the
SAME character staggering, dropping to one knee, and collapsing forward,
sword light fading out across the frames, facing right, no blood.
Identical style across frames, transparent background.
[HERO BLOCK] [STYLE BLOCK]
```

**ملاحظة تطور المراحل:** لا نحتاج طقماً لكل مرحلة — سأضيف توهجاً/هالة تتصاعد
بالكود مع كل مرحلة (درع أزرق → بنفسجي → ذهبي) فوق نفس الرسوم.

---

## 2) الوحوش (كل صورة: 3 لقطات في صف واحد 1536×512 — مشي أ، مشي ب، هجوم)

### M1 — monster_wolf.png (سريع — يستبدل المثلثات)
```
Sprite sheet: EXACTLY 3 frames in one horizontal row, 512×512 each, of the SAME
shadow-wolf creature: lean feral wolf with smoky black-green fur and glowing
amber eyes, top-down ¾ view facing LEFT — frame1 mid-sprint pose A, frame2
mid-sprint pose B, frame3 lunging bite attack. Identical creature and style in
all frames, transparent background. [STYLE BLOCK]
```

### M2 — monster_troll.png (دبابة بطيئة — يستبدل المربعات)
```
Sprite sheet: EXACTLY 3 frames in one horizontal row, 512×512 each, of the SAME
moss-covered forest troll: hulking stone-skinned brute with bark growths and
small red eyes, top-down ¾ view facing LEFT — frame1 heavy step A, frame2 heavy
step B, frame3 overhead club smash. Identical creature and style in all frames,
transparent background. [STYLE BLOCK]
```

### M3 — monster_slime.png (ينقسم عند موته — يستبدل الخماسيات)
```
Sprite sheet: EXACTLY 3 frames in one horizontal row, 512×512 each, of the SAME
toxic forest slime: translucent green-black blob with bone fragments floating
inside and a faint inner glow, top-down ¾ view — frame1 compressed squash,
frame2 tall stretch, frame3 splitting apart into two smaller blobs. Identical
style in all frames, transparent background. [STYLE BLOCK]
```

### M4 — monster_wraith.png (متعرج سريع — يستبدل المعينات)
```
Sprite sheet: EXACTLY 3 frames in one horizontal row, 512×512 each, of the SAME
forest wraith: tattered floating spirit with antler crown and trailing mist,
teal ghost-light core, top-down ¾ view facing LEFT — frame1 drift pose A,
frame2 drift pose B, frame3 claws-out swoop. Identical style in all frames,
transparent background. [STYLE BLOCK]
```

### M5 — monster_shaman.png (رامٍ من بعيد — يستبدل السداسيات)
```
Sprite sheet: EXACTLY 3 frames in one horizontal row, 512×512 each, of the SAME
goblin shaman: hunched small creature in ragged crow-feather robes holding a
gnarled staff with a green flame, top-down ¾ view facing LEFT — frame1 walking,
frame2 staff raised charging spell, frame3 hurling a green fireball. Identical
style in all frames, transparent background. [STYLE BLOCK]
```

### M6 — monster_shot.png (قذيفة الشامان والزعيم، 512×512، إطار واحد)
```
Single game VFX sprite, 512×512: a swirling sickly-green spectral fireball with
wispy flame tail, painted style, high contrast core, transparent background.
[STYLE BLOCK]
```

### B1 — boss_prime.png (الزعيم — 3 لقطات 2048×1024)
```
Sprite sheet: EXACTLY 3 frames in one horizontal row, ~680×1024 each, of the
SAME colossal boss: an ancient corrupted treant-demon, massive twisted oak body
with a burning amber heart visible in its ribcage of roots, crown of broken
branches, glowing runes on the bark, top-down ¾ view facing LEFT — frame1
towering idle, frame2 both root-arms raised to slam, frame3 roaring with heart
blazing. Identical creature and style in all frames, transparent background.
[STYLE BLOCK]
```

---

## 3) بيئة الغابة والمراحل (3 مراحل: غابة الفجر → الغابة العميقة → الغابة الملعونة)

### E1/E2/E3 — ground_stage1/2/3.png (1024×1024، بدون شفافية، قابلة للتكرار)
```
Seamless TILEABLE top-down game ground texture, 1024×1024, edges must wrap
perfectly (seamless when repeated in a grid): [VARIANT]. Subtle detail that
does not distract from gameplay characters, painted style, no text.
[STYLE BLOCK — but OPAQUE, no transparency]

VARIANT for E1: sunlit forest floor — mossy grass, scattered leaves, thin roots
VARIANT for E2: deep forest floor — darker moss, mushroom clusters, thick roots, faint teal fog patches
VARIANT for E3: cursed forest floor — ashen soil, black roots, ember cracks, faint red glow veins
```

### E4 — props_sheet.png (2048×1024، شفافة)
```
Game prop sprite sheet on transparent background, 2048×1024, containing 8
SEPARATE forest props arranged in a loose grid with clear space between them:
2 twisted trees (different shapes), 1 mossy boulder, 1 dead stump, 1 glowing
blue mushroom cluster, 1 broken stone pillar with runes, 1 thorn bush, 1 old
wooden signpost (blank, no text). Top-down ¾ game view, consistent painted
style and lighting. [STYLE BLOCK]
```

---

## 4) واجهة المستخدم (GUI حديث)

### U1 — ui_kit.png (2048×1024، شفافة)
```
Modern fantasy mobile-game UI kit on transparent background, 2048×1024, clean
separated elements: 1 large ornate panel frame with carved-wood-and-teal-glow
style (rounded corners, empty center), 1 wide button in normal state and 1 in
pressed state (bark texture with teal gem accents, empty label area), 1 health
bar frame + its red-orange fill strip, 1 XP bar frame + teal fill strip, 1
circular rune-styled pause icon, 1 gold coin/shard gem icon. Crisp edges,
consistent style, mobile-friendly readability, no text anywhere. [STYLE BLOCK]
```

### U2 — weapon_icons.png (2048×1024، شفافة)
```
Fantasy skill-icon set on transparent background, 2048×1024: EXACTLY 8 square
rune-framed icons in two rows of 4, same frame style, glowing teal-on-dark:
1 sword bolt, 2 orbiting blades, 3 radial shockwave, 4 piercing lance beam,
5 chain lightning, 6 homing spirit missiles, 7 ground rune trap, 8 rotating
light beam. Painted, consistent, readable at small size, no text. [STYLE BLOCK]
```

---

## 5) أيقونة التطبيق

### I1 — app_icon.png (1024×1024، **معتمة — بدون شفافية إطلاقاً**)
```
iOS app icon, 1024×1024, FULLY OPAQUE (no transparency): dramatic close-up of
the young forest ranger-warrior (short dark hair, green hooded cloak, glowing
teal short-sword raised) facing a horde of glowing-eyed shadow monsters
encircling him in a dark enchanted forest, teal moonlight rim lighting versus
warm amber monster eyes, painted cinematic style, centered hero composition
that stays readable at small sizes, square full-bleed image, no text, no border,
no watermark.
```

---

## 6) برومبتات الصوت (اختيارية — لأدوات مثل ElevenLabs SFX)

احفظها في `ArtDrop/audio/` بنفس الأسماء إن ولّدتها:
- `sfx_slash.mp3`: "fast heavy sword slash with a subtle magical shimmer tail, tight, punchy, 0.4s"
- `sfx_monster_hit.mp3`: "wet creature impact thud with a short growl grunt, 0.3s"
- `sfx_monster_die.mp3`: "creature death shriek dissolving into mist whoosh, 0.7s"
- `sfx_pickup.mp3`: "soft crystalline chime pickup, warm, pleasant, 0.25s"
- `sfx_levelup.mp3`: "triumphant short magical fanfare with rising shimmer, 0.8s"
- `sfx_boss_roar.mp3`: "colossal ancient tree monster roar, deep wooden creaking layered with beast growl, 1.5s"
- `ambience_forest.mp3`: "dark enchanted forest ambience loop, night crickets, distant owl, low wind through leaves, subtle eerie undertone, seamless loop, 60s"
- موسيقى (لأداة مثل Suno): "dark fantasy action loop, 110 BPM, hybrid orchestral-electronic, driving percussion, ominous strings, heroic brass hints, seamless loop, instrumental, 2:20"

**إن لم تولّد الصوتيات، لا مشكلة** — سأحسّن الصوت المُولَّد برمجياً (طبقات أغنى،
صدى، خامات أعمق) لكن سقف "الواقعية" للزئير والأجواء أعلى بكثير مع ملفات مولّدة.

---

## ماذا سيحدث بعد أن تضع الصور في ArtDrop/؟
1. أبني خط أنابيب السبرايت (تقطيع الإطارات، أطالس، أنيميشن حالات: idle/run/attack/death)
2. أستبدل الأشكال الهندسية بالشخصيات مع الحفاظ على كل التوازن المُختبر
3. نظام المراحل الثلاث: تغيير الأرضية والإضاءة والأجواء كل ~3 دقائق + بوابة انتقال + تطور بصري للبطل
4. GUI جديد من ui_kit (لوحات، أزرار، شرائط دم/خبرة، بطاقات ترقية)
5. الأيقونة الجديدة تحل محل المولّدة
6. أي صورة ناقصة → أُبقي البديل الإجرائي مؤقتاً (اللعبة تبقى قابلة للبناء دائماً)

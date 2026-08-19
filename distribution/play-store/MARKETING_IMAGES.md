# Google Play Console marketing images

Source-of-truth brief for the Play Store listing graphics of **Finance Suit**
(`com.buildingsuit.finance`). Each entry below gives:

1. the **title and slogan** to be rendered on the image, and
2. an **image-generation prompt** that composes an advertising frame around a
   real app screenshot, with the screenshot embedded **unmodified**.

## Asset specifications

| Asset | Size | Format | Count |
| --- | --- | --- | --- |
| Phone screenshots | 1080 x 1920 px (9:16) | PNG, 24-bit, no alpha | 8 (frames 1-8) |
| Feature graphic | 1024 x 500 px | PNG, 24-bit, no alpha | 1 (frame 9) |
| App icon | 512 x 512 px | PNG, 32-bit | already produced from `assets/branding/finance_suit_app_icon.svg` |

Play requires at least 2 phone screenshots; 8 is the maximum and is what this
brief covers. Frames are ordered for the listing carousel.

## Brand constants (use verbatim in every prompt)

| Token | Value |
| --- | --- |
| Building Navy | `#16293B` |
| Deep Structure Navy | `#0D1B28` |
| Premium Gold | `#D89B42` |
| Highlight Gold | `#EBB45A` |
| Gold 300 | `#F4CE86` |
| Pearl White | `#F7F8FA` |
| Dark background | `#0E1114` |
| Dark surface | `#151A1F` |
| Latin typeface | Manrope (Bold for titles, Medium for slogans) |
| Arabic typeface | IBM Plex Sans Arabic |
| Brand mark | `assets/branding/finance_suit_mark.png` (finance-ledger `F`) |

## Screenshot capture list

Capture on a 1080 x 2400 device with demo data before generating any frame.

| Frame | Screen | Route source |
| --- | --- | --- |
| 1 | Dashboard | `lib/features/dashboard/presentation/screens/home_screen.dart` |
| 2 | Salary period detail | `lib/features/salary/presentation/screens/salary_period_detail_screen.dart` |
| 3 | Work month | `lib/features/work/presentation/screens/work_screen.dart` |
| 4 | Income automations | `lib/features/finance/presentation/screens/income_sources_screen.dart` |
| 5 | Credit facility | `lib/features/finance/presentation/screens/facility_payment_screen.dart` |
| 6 | Reports | `lib/features/reports/presentation/screens/reports_screen.dart` |
| 7 | Unified history | history tab of the shell |
| 8 | Dashboard, Arabic + dark mode | `home_screen.dart` with locale `ar` |

## Hard rule for every prompt

> The supplied screenshot is a finished UI capture. Reproduce it pixel-for-pixel
> inside the frame: do not redraw, restyle, recolor, translate, crop, blur,
> upscale with invention, add or remove UI elements, or overlay anything on top
> of it. Generate only the surrounding advertising composition.

---

## Frame 1 - Dashboard

**Title:** Your whole month, one screen

**Slogan:** Balances, salary, and cash flow in a single glance.

**Prompt:**

```
Create a 1080x1920 px vertical Google Play screenshot for "Finance Suit", a
personal finance app.

Background: a deep vertical gradient from Building Navy #16293B at the top to
Deep Structure Navy #0D1B28 at the bottom, with a subtle Premium Gold #D89B42
radial glow at 8% opacity behind the device.

Top area (top 22% of the canvas), centered, generous margins:
- Title on one or two lines: "Your whole month, one screen" in Manrope Bold,
  Pearl White #F7F8FA, ~78 px, tight line height.
- Slogan directly under it: "Balances, salary, and cash flow in a single
  glance." in Manrope Medium, ~40 px, Pearl White at 78% opacity.
- A 64 px Premium Gold #D89B42 accent rule between title and slogan.

Device area (bottom 78%): place the PROVIDED SCREENSHOT inside a modern
Android phone mockup - flat matte dark frame, 48 px corner radius, thin
1 px Highlight Gold #EBB45A rim light on the upper-left edge, soft drop shadow
below. The phone is centered, tilted 0 degrees (straight on), and cropped by
the bottom canvas edge so roughly 88% of the device height is visible.

CRITICAL: The provided screenshot must appear inside the phone frame exactly as
supplied - pixel-for-pixel identical. Do not redraw, restyle, recolor,
translate, crop, blur, reinterpret, or overlay any graphic, text, badge, hand,
cursor, or glare on top of it. Generate only the background, typography, and
device frame around it.

No logos other than the Finance Suit "F" mark, no stock photography, no
lorem ipsum, no invented UI. Flat, premium, fintech aesthetic.
```

---

## Frame 2 - Salary

**Title:** Know your salary before payday

**Slogan:** Every allowance, deduction, and overtime hour, calculated.

**Prompt:**

```
Create a 1080x1920 px vertical Google Play screenshot for "Finance Suit".

Background: solid Deep Structure Navy #0D1B28 with a faint diagonal grid of
1 px Premium Gold #D89B42 lines at 6% opacity running from lower-left to
upper-right.

Top area (top 24%), left-aligned with a 96 px left margin:
- Small eyebrow label "SALARY ESTIMATE" in Manrope Bold, 30 px, letter-spaced
  0.18em, Premium Gold #D89B42.
- Title: "Know your salary before payday" in Manrope Bold, ~76 px, Pearl White
  #F7F8FA.
- Slogan: "Every allowance, deduction, and overtime hour, calculated." in
  Manrope Medium, ~38 px, Pearl White at 75% opacity.

Device area: place the PROVIDED SCREENSHOT in a flat dark Android phone mockup,
44 px corner radius, rotated 6 degrees clockwise, positioned right-of-center and
bleeding off the right and bottom canvas edges. Soft ambient shadow, subtle
Highlight Gold #EBB45A edge light on the left rim.

CRITICAL: The provided screenshot must be embedded exactly as supplied -
pixel-for-pixel identical, including its own colors, typography, numbers, and
layout. Do not redraw, restyle, recolor, translate, crop into, blur, or place
anything on top of it. Rotation of the whole device mockup is allowed; altering
the screenshot content is not. Generate only the background, typography, and
device frame.

Flat premium fintech style, no stock photos, no invented UI elements.
```

---

## Frame 3 - Work tracking

**Title:** Every extra hour counts

**Slogan:** Log overtime, extra days, and holidays worked.

**Prompt:**

```
Create a 1080x1920 px vertical Google Play screenshot for "Finance Suit".

Background: split composition - upper 30% in Building Navy #16293B, lower 70%
in Deep Structure Navy #0D1B28, separated by a 4 px Premium Gold #D89B42
horizontal rule that fades to transparent at both ends.

Top area (upper 30%), centered:
- Title: "Every extra hour counts" in Manrope Bold, ~80 px, Pearl White
  #F7F8FA.
- Slogan: "Log overtime, extra days, and holidays worked." in Manrope Medium,
  ~38 px, Gold 300 #F4CE86.

Device area: place the PROVIDED SCREENSHOT in a flat dark Android phone mockup
with 48 px corner radius, centered horizontally, straight on, the top of the
device overlapping the gold rule by about 40 px so it breaks the divider. The
bottom of the device is cropped by the canvas edge. Add a soft downward shadow.

CRITICAL: The provided screenshot must be shown exactly as supplied -
pixel-for-pixel identical. Do not redraw, restyle, recolor, translate, crop,
blur, or overlay callouts, arrows, badges, hands, or highlights on top of it.
Generate only the background, typography, and device frame around it.

Flat premium fintech style. No stock photography, no invented interface.
```

---

## Frame 4 - Income automations

**Title:** Income that splits itself

**Slogan:** Approve once, and every account gets its share.

**Prompt:**

```
Create a 1080x1920 px vertical Google Play screenshot for "Finance Suit".

Background: Building Navy #16293B base, with three concentric arcs of Premium
Gold #D89B42 at 10% opacity radiating from the lower-right corner, suggesting
flow and distribution.

Top area (top 23%), left-aligned with a 96 px left margin:
- Title on two lines: "Income that splits itself" in Manrope Bold, ~80 px,
  Pearl White #F7F8FA.
- Slogan: "Approve once, and every account gets its share." in Manrope Medium,
  ~38 px, Pearl White at 76% opacity.
- A 6 px x 96 px vertical Premium Gold #D89B42 bar to the left of the title
  block.

Device area: place the PROVIDED SCREENSHOT in a flat dark Android phone mockup,
44 px corner radius, straight on, centered, cropped by the bottom canvas edge.
Behind the phone, a soft elliptical Highlight Gold #EBB45A glow at 12% opacity.

CRITICAL: The provided screenshot must appear exactly as supplied -
pixel-for-pixel identical. Do not redraw, restyle, recolor, translate, crop,
blur, annotate, or overlay arrows, connectors, or labels on top of it. Any
graphic suggesting flow must live in the background only, never over the
screen. Generate only the background, typography, and device frame.

Flat premium fintech style, no stock photography, no invented UI.
```

---

## Frame 5 - Cards and installments

**Title:** Never miss an installment

**Slogan:** Track credit limits, dues, and payment plans.

**Prompt:**

```
Create a 1080x1920 px vertical Google Play screenshot for "Finance Suit".

Background: Deep Structure Navy #0D1B28 with a large, very subtle outline of a
credit card shape drawn in 2 px Premium Gold #D89B42 at 8% opacity, rotated 20
degrees, occupying the upper-right quadrant. No card artwork or brand marks.

Top area (top 24%), centered:
- Eyebrow label "CARDS & DUES" in Manrope Bold, 30 px, letter-spaced 0.18em,
  Premium Gold #D89B42.
- Title: "Never miss an installment" in Manrope Bold, ~78 px, Pearl White
  #F7F8FA.
- Slogan: "Track credit limits, dues, and payment plans." in Manrope Medium,
  ~38 px, Pearl White at 76% opacity.

Device area: place the PROVIDED SCREENSHOT in a flat dark Android phone mockup,
48 px corner radius, rotated 4 degrees counter-clockwise, centered slightly
left, cropped by the bottom canvas edge, with a soft shadow and a thin
Highlight Gold #EBB45A rim light on the right edge.

CRITICAL: The provided screenshot must be embedded exactly as supplied -
pixel-for-pixel identical, with its own amounts, dates, colors, and layout
untouched. Do not redraw, restyle, recolor, translate, crop, blur, or place any
badge, sticker, arrow, or highlight over it. Generate only the background,
typography, and device frame.

Flat premium fintech style. No real bank names or logos, no stock photography.
```

---

## Frame 6 - Reports

**Title:** See where the money goes

**Slogan:** Cash-flow, category, and balance reports over any range.

**Prompt:**

```
Create a 1080x1920 px vertical Google Play screenshot for "Finance Suit".

Background: vertical gradient from Deep Structure Navy #0D1B28 at the top to
Building Navy #16293B at the bottom, overlaid with an abstract line-chart
silhouette drawn in 3 px Premium Gold #D89B42 at 12% opacity that sweeps across
the lower third of the canvas, behind the device.

Top area (top 23%), centered:
- Title: "See where the money goes" in Manrope Bold, ~78 px, Pearl White
  #F7F8FA.
- Slogan: "Cash-flow, category, and balance reports over any range." in Manrope
  Medium, ~37 px, Pearl White at 76% opacity.
- A 64 px Premium Gold #D89B42 accent rule above the title.

Device area: place the PROVIDED SCREENSHOT in a flat dark Android phone mockup,
48 px corner radius, straight on, centered, cropped by the bottom canvas edge.

CRITICAL: The provided screenshot must be shown exactly as supplied -
pixel-for-pixel identical. Its charts, colors, legends, and values are final:
do not redraw, restyle, recolor, translate, re-plot, crop, blur, or extend any
chart, and do not overlay data labels, arrows, or callouts on it. The decorative
chart line belongs to the background only and must never cross the device
screen. Generate only the background, typography, and device frame.

Flat premium fintech style, no stock photography, no invented data visuals.
```

---

## Frame 7 - Unified history

**Title:** One timeline for everything

**Slogan:** Income, expenses, transfers, and work, by business date.

**Prompt:**

```
Create a 1080x1920 px vertical Google Play screenshot for "Finance Suit".

Background: Building Navy #16293B with a single vertical Premium Gold #D89B42
timeline line at 14% opacity running down the left third of the canvas, dotted
with four small gold nodes, behind the device.

Top area (top 24%), left-aligned with a 110 px left margin:
- Title on two lines: "One timeline for everything" in Manrope Bold, ~78 px,
  Pearl White #F7F8FA.
- Slogan: "Income, expenses, transfers, and work, by business date." in Manrope
  Medium, ~37 px, Pearl White at 76% opacity.

Device area: place the PROVIDED SCREENSHOT in a flat dark Android phone mockup,
44 px corner radius, straight on, offset to the right so the background timeline
stays visible on the left, cropped by the right and bottom canvas edges.

CRITICAL: The provided screenshot must be embedded exactly as supplied -
pixel-for-pixel identical. Do not redraw, restyle, recolor, translate, reorder,
crop, blur, or overlay any element on top of it. The decorative timeline stays
in the background and must not touch the device screen. Generate only the
background, typography, and device frame.

Flat premium fintech style, no stock photography, no invented UI.
```

---

## Frame 8 - Arabic and dark mode

**Title:** Arabic and English, light and dark

**Slogan:** Full right-to-left support, built in.

**Prompt:**

```
Create a 1080x1920 px vertical Google Play screenshot for "Finance Suit".

Background: split diagonally from the top-left to the bottom-right - the upper
triangle in Pearl White #F7F8FA, the lower triangle in dark background #0E1114,
with a 3 px Premium Gold #D89B42 line along the diagonal seam.

Top area (top 24%), centered inside the light triangle:
- Title: "Arabic and English, light and dark" in Manrope Bold, ~72 px,
  Building Navy #16293B.
- Slogan on one line in English and its Arabic equivalent beneath it:
  "Full right-to-left support, built in." in Manrope Medium, ~36 px, Building
  Navy at 72% opacity, and "دعم كامل للغة العربية ومن اليمين لليسار" in
  IBM Plex Sans Arabic Medium, ~36 px, Gold 700 #A86C1C.

Device area: place the PROVIDED SCREENSHOT (an Arabic, right-to-left, dark-mode
capture) in a flat dark Android phone mockup, 48 px corner radius, straight on,
centered inside the dark lower triangle, cropped by the bottom canvas edge, with
a soft shadow and a thin Highlight Gold #EBB45A rim light.

CRITICAL: The provided screenshot is already in Arabic and dark mode. Embed it
exactly as supplied - pixel-for-pixel identical. Do not redraw, restyle,
recolor, translate, transliterate, mirror, reflow, crop, blur, or correct any
Arabic text inside it, and do not overlay anything on top of it. Generate only
the background, typography, and device frame.

Flat premium fintech style, no stock photography, no invented UI.
```

---

## Frame 9 - Feature graphic (1024 x 500)

**Title:** Finance Suit

**Slogan:** Salary, work, and cash flow. Under control.

**Prompt:**

```
Create a 1024x500 px horizontal Google Play feature graphic for "Finance Suit".

Background: horizontal gradient from Deep Structure Navy #0D1B28 on the left to
Building Navy #16293B on the right, with a soft Premium Gold #D89B42 radial glow
at 10% opacity behind the right third.

Left half (left 55%), vertically centered, 72 px left margin:
- The Finance Suit "F" ledger brand mark in Premium Gold #D89B42, 88 px tall,
  above the wordmark.
- Title: "Finance Suit" in Manrope Bold, ~86 px, Pearl White #F7F8FA.
- Slogan: "Salary, work, and cash flow. Under control." in Manrope Medium,
  ~34 px, Pearl White at 78% opacity.

Right half: place the PROVIDED DASHBOARD SCREENSHOT in a flat dark Android phone
mockup, 40 px corner radius, rotated 8 degrees clockwise, scaled so the device
is cropped by both the top and bottom canvas edges, with a soft shadow and a
thin Highlight Gold #EBB45A rim light on the left edge.

CRITICAL: The provided screenshot must appear exactly as supplied -
pixel-for-pixel identical. Do not redraw, restyle, recolor, translate, crop
into, blur, or overlay any text, badge, rating, award, or "download now" graphic
on top of it. Generate only the background, brand mark, typography, and device
frame.

Keep the left 55% free of any device or busy detail so the title stays legible
when Play crops the graphic. No store badges, no ratings, no stock photography,
no invented UI.
```

---

## Rendering rules

- Never let generated typography, glow, or decoration overlap the device screen
  area; the screenshot must remain fully unobstructed in every frame.
- Regenerate a frame rather than retouching it if any part of the screenshot
  comes back altered; compare against the source capture before uploading.
- Export as 24-bit PNG without an alpha channel. Play rejects transparency on
  screenshots and feature graphics.
- Keep every title under 40 characters so it survives the carousel crop on small
  devices.
- Localize titles and slogans into Arabic for the `ar` listing using IBM Plex
  Sans Arabic and a mirrored composition; the embedded screenshot rule is
  unchanged.

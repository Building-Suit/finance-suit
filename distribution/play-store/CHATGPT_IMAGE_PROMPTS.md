# ChatGPT image prompts — Finance Suit Play Store graphics

Copy-paste prompts for generating the Play Console listing images with
ChatGPT, using the real app captures in `screenshots/` as the embedded
screen content.

## Read this before you start

ChatGPT's image generator **redraws** every pixel it outputs. It does not
composite an attached file into a canvas the way an image editor does. Given
a reference screenshot it will reproduce something that looks like it, and it
will get the layout and colors approximately right, but small text, exact
digits, and icon shapes drift. Expect to inspect every result against the
source capture and to reroll frames that come back wrong.

If a frame's screen content must be exact — and for a store listing it should
be — the reliable path is to let ChatGPT generate the **background plate only**
(no device, no screen) and then paste the real PNG into the device cutout in
any editor. Section 6 covers that workflow. Section 5 is the single-shot
version for when approximate is good enough.

## 1. How to run this

The prompts are built so that every frame shares one locked composition.
Only the headline, the sub-line, and the screenshot change between frames.
That is what makes the eight phone frames look like one set instead of eight
unrelated posters.

Order of operations in a single ChatGPT conversation:

1. Send **§2 STYLE LOCK** on its own. Do not attach anything. Wait for it to
   acknowledge.
2. For each frame, send the **§4 frame block** with the matching PNG from
   `screenshots/` attached.
3. Run the **§7 checklist** against each returned image before accepting it.

Keep it to one conversation. Starting a new chat drops the style lock and the
frames stop matching each other.

## 2. STYLE LOCK — send this first, verbatim

```
You are producing a set of 9 advertising images for the Google Play Store
listing of an Android app called Finance Suit. I will send you one frame at a
time. Every frame must obey the following specification exactly. Treat this
message as a locked style contract: do not deviate from it on any frame, and
do not "improve" or reinterpret it later in the conversation.

CANVAS
- Frames 1 through 8: exactly 1080 x 1920 pixels, portrait.
- Frame 9: exactly 1024 x 500 pixels, landscape. I will tell you when.
- Flat 2D digital composition. No photography, no 3D renders, no perspective,
  no isometric views, no hands, no desks, no people, no plants, no coffee cups.

COLOR — use these hex values and no others
- Background base:        #16293B  (dark navy)
- Background deep:        #0D1B28  (darker navy, gradient end)
- Primary accent:         #D89B42  (gold)
- Accent light:           #EBB45A  (light gold)
- Accent pale:            #F4CE86  (pale gold)
- Text primary:           #F7F8FA  (near-white)
- Device bezel:           #0B0F14  (near-black)
Background is a smooth linear gradient from #16293B at the top-left to
#0D1B28 at the bottom-right. The same gradient, the same direction, on every
single frame. No other background treatment.

BACKGROUND MOTIF
- One soft radial glow of #D89B42 at 10% opacity, 700px diameter, centered
  behind the upper portion of the phone. Nothing else.
- No grids, no arcs, no chart lines, no timelines, no card shapes, no rays,
  no particles, no bokeh, no noise texture, no vignette.
- The background must be identical on all 8 portrait frames. The only thing
  that changes between frames is the text and the phone's screen content.

TYPOGRAPHY
- Typeface: a geometric humanist sans-serif with round terminals and a tall
  x-height (Manrope is the target; Poppins or Nunito Sans are acceptable
  stand-ins). The same face on every frame.
- Headline: Bold, 76px, color #F7F8FA, line-height 1.12, maximum 2 lines,
  left-aligned.
- Sub-line: Medium, 38px, color #F7F8FA at 78% opacity, line-height 1.35,
  maximum 2 lines, left-aligned.
- A solid #D89B42 rule, 6px tall and 88px wide, sits 28px above the headline.
- Real, correctly spelled English text only. No lorem ipsum, no invented
  words, no decorative fake lettering, no text shadows, no outlines, no
  gradients on text.

LAYOUT GRID — identical on all 8 portrait frames
- Left margin for all text: 84px. Right text boundary: 996px.
- Accent rule top edge: y = 132.
- Headline block top edge: y = 166.
- Sub-line block top edge: y = 356.
- Phone mockup: 864px wide, horizontally centered (x = 108 to x = 972).
  Its top edge is at y = 540. It extends past the bottom edge of the canvas
  and is cropped by it. Do not shrink the phone to make it fit.

PHONE MOCKUP
- A flat, front-facing, straight-on Android phone. Zero rotation, zero tilt,
  zero perspective. Perfectly axis-aligned.
- Bezel: solid #0B0F14, uniform 14px thick on the left, right, and top.
- Outer corner radius 48px. Inner screen corner radius 34px.
- A 1px #EBB45A rim highlight on the outer left and top edges only.
- A soft dark drop shadow beneath and behind the phone, 60px blur, 40%
  opacity, offset 12px down. No colored glow on the shadow.
- No notch, no camera hole, no speaker grille, no side buttons, no
  reflections, no screen glare, no glass shine, no rounded-screen distortion.
- The screen area inside the bezel is 836px wide. The screenshot fills that
  width exactly and keeps its own aspect ratio, so it runs off the bottom of
  the canvas. That is intended.

SCREEN CONTENT — the most important rule in this specification
- I will attach a real screenshot with each frame. It is finished, approved
  product UI.
- Reproduce it inside the phone screen exactly as supplied: identical layout,
  identical colors, identical text strings, identical numbers, identical
  icons, identical spacing, identical order of every row and card.
- Do NOT redraw it in your own style. Do NOT restyle, recolor, or "clean up"
  anything. Do NOT translate it. Do NOT change any number, date, currency, or
  label. Do NOT add, remove, reorder, or resize any UI element. Do NOT crop
  into it or zoom it. Do NOT blur it. Do NOT round its corners beyond the
  34px screen radius. Do NOT overlay anything on top of it — no arrows, no
  callouts, no badges, no cursors, no fingers, no highlight rings, no
  gradients, no scrims.
- Scale it uniformly to the 836px screen width. Never stretch or squash it.
- The only permitted crop is the bottom, caused by the canvas edge.
- If you cannot reproduce the screenshot faithfully, leave the screen area a
  flat #0B0F14 rectangle and tell me so in text. Do not invent replacement UI
  under any circumstance.

ABSOLUTE PROHIBITIONS ON EVERY FRAME
- No Google Play badge, no "Get it on Google Play", no App Store badge.
- No star ratings, no review counts, no download counts, no award laurels.
- No "Download now", "Free", "New", "#1", or any call-to-action button.
- No company logos other than the app's own mark when I explicitly ask.
- No borders or frames around the canvas itself.
- No watermarks, no signatures, no AI artifacts in corners.
- No emoji anywhere.

Confirm you have understood, then wait. I will send frame 1 next.
```

## 3. Filling in each frame

Every frame block in §4 is the same three lines. Attach the PNG named in the
block, from `distribution/play-store/screenshots/`.

## 4. Frame prompts — send one at a time, with the PNG attached

### Frame 1 — Dashboard

Attach `01-home-overview.png`

```
Frame 1 of 9. Apply the locked specification exactly.

HEADLINE: Your whole month, one screen
SUB-LINE: Balances, salary, and cash flow at a glance.

The attached image is the screen content. Reproduce it inside the phone
exactly as supplied — every number, label, and icon unchanged. Canvas
1080x1920.
```

### Frame 2 — Salary estimate

Attach `16-income-automation.png`

```
Frame 2 of 9. Apply the locked specification exactly. Same background, same
gradient, same phone geometry, same text positions as frame 1.

HEADLINE: Know your salary before payday
SUB-LINE: Every allowance, overtime hour, and bonus, calculated.

The attached image is the screen content. Reproduce it inside the phone
exactly as supplied — every number, label, and icon unchanged. Canvas
1080x1920.
```

### Frame 3 — Work tracking

Attach `06-work-calendar.png`

```
Frame 3 of 9. Apply the locked specification exactly. Same background, same
gradient, same phone geometry, same text positions as frame 1.

HEADLINE: Every extra hour counts
SUB-LINE: Log overtime, extra days, and holidays worked.

The attached image is the screen content. Reproduce it inside the phone
exactly as supplied — every number, label, and icon unchanged. Canvas
1080x1920.
```

### Frame 4 — Income automation

Attach `19-income-split.png`

```
Frame 4 of 9. Apply the locked specification exactly. Same background, same
gradient, same phone geometry, same text positions as frame 1.

HEADLINE: Income that splits itself
SUB-LINE: Approve once, and every account gets its share.

The attached image is the screen content. Reproduce it inside the phone
exactly as supplied — every number, label, and icon unchanged. Canvas
1080x1920.
```

### Frame 5 — Cards and installments

Attach `11-card-due-breakdown.png`

```
Frame 5 of 9. Apply the locked specification exactly. Same background, same
gradient, same phone geometry, same text positions as frame 1.

HEADLINE: Never miss an installment
SUB-LINE: Track credit limits, dues, and payment plans.

The attached image is the screen content. Reproduce it inside the phone
exactly as supplied — every number, label, and icon unchanged. Canvas
1080x1920.
```

### Frame 6 — Reports

Attach `07-reports-overview.png`

```
Frame 6 of 9. Apply the locked specification exactly. Same background, same
gradient, same phone geometry, same text positions as frame 1.

HEADLINE: See where the money goes
SUB-LINE: Cash flow, categories, and balances over any range.

The attached image is the screen content. Its charts, bars, and values are
final — reproduce them exactly as supplied, and do not redraw, re-plot,
extend, or relabel any chart. Canvas 1080x1920.
```

### Frame 7 — Transaction history

Attach `05-money-transactions.png`

```
Frame 7 of 9. Apply the locked specification exactly. Same background, same
gradient, same phone geometry, same text positions as frame 1.

HEADLINE: One timeline for everything
SUB-LINE: Income, expenses, and transfers by business date.

The attached image is the screen content. Reproduce it inside the phone
exactly as supplied — every number, label, and icon unchanged. Canvas
1080x1920.
```

### Frame 8 — Arabic, right-to-left

Attach `17-home-arabic-rtl.png`

```
Frame 8 of 9. Apply the locked specification exactly. Same background, same
gradient, same phone geometry, same text positions as frame 1. The headline
and sub-line stay in English and stay left-aligned — do not mirror the
layout.

HEADLINE: Arabic and English, built in
SUB-LINE: Full right-to-left support, in light and dark.

The attached image is the screen content and it is in Arabic, right-to-left,
dark mode. Reproduce it exactly as supplied. Do not translate it, do not
transliterate it, do not mirror it, do not reflow it, do not "correct" any
Arabic word, and do not substitute Latin text for Arabic text. If you cannot
render the Arabic faithfully, leave the screen flat #0B0F14 and tell me.
Canvas 1080x1920.
```

### Frame 9 — Feature graphic

Attach `01-home-overview.png`

```
Frame 9 of 9. This one is the landscape feature graphic, so the portrait
layout grid does not apply. Everything else in the locked specification still
holds: same gradient, same palette, same typeface, same prohibitions.

CANVAS: exactly 1024 x 500 pixels, landscape.

LAYOUT:
- Background: the same #16293B to #0D1B28 gradient, running left to right.
  One #D89B42 radial glow at 10% opacity behind the right third.
- Left side, starting at x = 72, vertically centered as a block:
  - HEADLINE "Finance Suit" in Bold 82px, color #F7F8FA.
  - SUB-LINE "Salary, work, and cash flow. Under control." in Medium 32px,
    color #F7F8FA at 78% opacity.
  - A 6px x 88px #D89B42 rule 28px above the headline.
- The entire left 55% of the canvas must stay free of the phone and of any
  busy detail, because the store crops this graphic.
- Right side: the same flat, straight-on, zero-rotation phone mockup as the
  portrait frames, 300px wide, bezel #0B0F14 at 14px, outer radius 40px. It
  is cropped by both the top and bottom canvas edges.

The attached image is the screen content. Reproduce it exactly as supplied.
Do not overlay any badge, rating, or call-to-action on it or anywhere else.
```

## 5. If a frame comes back wrong

Reply in the same conversation with the specific defect. Do not restate the
whole spec — that tends to make it re-imagine the composition.

Useful corrections, one at a time:

```
The phone is tilted. It must be perfectly straight-on with zero rotation.
Regenerate with the same background and text.
```

```
You redrew the screen content. Reproduce the attached screenshot exactly:
same rows, same numbers, same colors. Regenerate.
```

```
The background changed from the previous frame. It must be the identical
#16293B to #0D1B28 top-left to bottom-right gradient with a single gold
radial glow, exactly as in frame 1. Regenerate.
```

```
The headline moved. Its top edge must be at y = 166 with an 84px left
margin, exactly as in frame 1. Regenerate.
```

```
You added a star rating / badge / call-to-action. Remove it entirely and
regenerate.
```

## 6. Exact-screenshot workflow (recommended)

This removes the redraw risk completely, at the cost of one paste per frame.

Ask ChatGPT for plates instead of finished frames:

```
Generate the same 1080x1920 composition described in the locked
specification, with one change: leave the phone's screen area completely
empty as a flat #FF00FF magenta rectangle, with the bezel, corner radius,
rim light, and shadow all still drawn. Do not put any UI inside it. I will
insert the screen content myself.
```

Then, for each plate, paste the real PNG from `screenshots/` into the magenta
rectangle in any editor, scaled to the rectangle's width with its aspect ratio
locked, aligned to the rectangle's top edge, and clipped to the 34px inner
radius. The magenta makes the target area unambiguous and easy to select.

The plates are identical across frames, so one approved plate can serve all
eight portrait frames — which also guarantees the set is perfectly consistent.

## 7. Acceptance checklist

Check every returned frame against this before uploading to Play Console.

Composition consistency, compared side by side with frame 1:
- [ ] Background gradient identical in color and direction.
- [ ] Exactly one gold radial glow, no extra motifs.
- [ ] Phone identical in width, position, corner radius, and bezel thickness.
- [ ] Phone perfectly straight — no tilt, no perspective.
- [ ] Headline and sub-line start at the same left margin and the same height.
- [ ] Same typeface and same sizes as frame 1.

Screen fidelity, compared with the source PNG in `screenshots/`:
- [ ] Every visible number matches the source exactly.
- [ ] Every visible label matches the source exactly, with no misspellings.
- [ ] Row and card order unchanged.
- [ ] Colors unchanged, including the gold accents and status colors.
- [ ] Icons are the same shapes, not invented substitutes.
- [ ] Nothing overlays the screen.
- [ ] Frame 8 only: Arabic text is real Arabic, still right-to-left, not
      mirrored into nonsense and not replaced with Latin text.

Store compliance:
- [ ] Portrait frames are exactly 1080 x 1920; feature graphic is exactly
      1024 x 500.
- [ ] 24-bit PNG, no alpha channel.
- [ ] No store badge, rating, award, price, or call-to-action anywhere.
- [ ] Headline is under 40 characters so it survives the carousel crop.

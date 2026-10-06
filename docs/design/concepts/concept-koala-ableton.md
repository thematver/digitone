# ШЕСТНАДЦАТЬ (Sixteen): a Koala × Ableton concept for Digitone II

## 1. Concept and metaphor

**ШЕСТНАДЦАТЬ.** The Digitone II as a box of sixteen colored tiles. Every track, sound, pattern, loop and sample is a tile: tap it to hear it, hold it to look inside, drag it anywhere it fits.

The hardware counts in sixteens (tracks, trig keys, steps per page), and so do the pads. Koala gives speed: one-tap record, resample everything. Ableton gives order: clips, scenes, a real piano roll, fixed track colors.

## 2. Design principles

1. **Tap = hear.** Every tile sounds the moment your finger lands, before it is even selected.
2. **The picture is the control.** There are no sliders without a curve. A number appears only under your finger, in large rounded type, and fades 600 ms after you let go.
3. **Everything is a tile.** Sounds, patterns, clips, samples and chops share one shape and one set of drag rules. Dropping a tile on a target does the obvious thing.
4. **Track color is identity.** Track 7 is cyan in the roll, on the pads, on the tape and in the library.
5. **Never lose a take.** USB audio and incoming MIDI always go into a 2-minute rolling buffer, and ● keeps the last pattern-length.
6. **Truth is a glyph, not a sentence.** Values are drawn solid when known, dotted when sent and fogged when unknown. Any explanation is a long-press away, never printed on screen.

## 3. Information architecture

| Mode | SF Symbol | Job |
|---|---|---|
| ЗВУК | `waveform.circle` | Shape the selected track's sound |
| НОТЫ | `pianokeys` | Piano roll, steps, patterns, MIDI files |
| ПЛЁНКА | `record.circle` | Record and play USB audio |
| СЭМПЛЕР | `square.grid.4x3.fill` | 16 pads, chop, auto-sample |
| БИБЛИОТЕКА | `square.stack` | Presets, banks, crates, archives |

Two rails are always on screen:

- **Track Rail:** 16 colored tiles in one row along the bottom, like the trig keys. Tap to audition and select. A tile pulses with audio (when isolated on USB OUT) or with note-ons.
- **Device Pill:** top left, a mini Digitone with a status light. It opens the Connection sheet, which is deliberately not a mode.

**Platforms:**

- **iPad/Mac:** mode icons beside the Pill; ▶, BPM and ● top right. Mac adds keys 1–5 (modes), Space, R, B (draw, as in Ableton), Tab (pages), and Finder drag in/out.
- **iPhone:** bottom tab bar; the rail becomes 16 color chips (scrub across them to audition each track); long-press opens a 4-item radial.

**From launch to sound in under 30 s:**

1. CoreMIDI picks the port whose SysEx identity says Digitone II (no picker, ~2 s); the Pill turns solid.
2. The app opens in ЗВУК on track 1, with names from the last dump on the rail.
3. Tap tile 1 and the Digitone sounds (~5 s). With no device, a bundled demo kit in the app sampler answers instead.

## 4. Screens

### (a) ЗВУК: one drawing per hardware page

**Dominant visualization:** a page strip `SYN · FLTR · AMP · FX · MOD`, using the panel's own words. Each page is a single drawing whose handles are the parameters.

- **FM TONE:** an operator constellation. Operators C, A, B1 and B2 are circles linked by the current algorithm's arrows. Radius shows level, an orbiting dot shows ratio, and a loop arrow's thickness shows feedback. Swiping flips through the 8 algorithms, and the arrows morph between them.
- **FM DRUM:** a pitch-sweep curve with the transient drawn as grain at its head.
- **WAVETONE:** two waveforms. Dragging horizontally morphs their shape.
- **SWARMER:** a fan of detuned saws. The spread of the fan is the detune.
- **FLTR:** the response curve. Drag the knee for cutoff and pinch for resonance. Envelope depth is a ghost path the knee rides when a note plays.
- **AMP:** an ADSR polyline.
- **FX:** a staircase for bit reduction, a transfer curve for overdrive, and three send "pipes" into DELAY, REVERB and CHORUS.
- **MOD:** live LFO waves, each with a dot flowing into its destination.

Behind every drawing runs the live spectrum of the isolated track from USB OUT. You see what each edit does as well as hear it.

**Knobs A–H:** every handle carries a letter badge, laid out in the hardware's 2×4 order. Turning knob E on the device makes badge E glow and its handle move. Below the drawing, a row of 8 rings repeats A–H for direct turning. On Mac, the scroll wheel turns the handle under the pointer.

**Value states, without text:**

| Glyph | Meaning | How the drawing shows it |
|---|---|---|
| ○ hollow ring | Unknown | Dashed grey "fog" |
| ◉ ring with center dot | Sent by the app | Solid, in track color |
| ● solid disk | Reported by the device (knob turn or dump) | Solid, with a tiny tick |

When a pattern or program change arrives, the known values fade back into fog over 400 ms.

```
+-[●DN2] [ЗВУК] НОТЫ ПЛЁНКА СЭМПЛЕР БИБЛ ------ [▶ 120] [●] -+
| SYN  FLTR  AMP  FX  MOD               KICK_SHARP · FM TONE |
|                                       .:||||||:. spectrum  |
|        (C)<------(A)A                                      |
|         ^         ^ \_fb C                                 |
|       (B1)B     (B2)D        ALGO ◂ 3/8 ▸                 |
|                                                            |
|   A●   B●   C○   D○         E◉   F○   G○   H●             |
+-[1][2][3][4][5][6][7][8][9][10][11][12][13][14][15][16]---+
```

```
+----------------------+
| ●DN2 KICK_SHARP ▶120 |
| SYN FLTR AMP FX MOD  |
|    (C)<--(A)         |
|     ^     ^  .:||:.  |
|   (B1)  (B2)         |
| A● B● C○ D○          |
| E◉ F○ G○ H●          |
| ■■■■■■■■■■■■■■■■     |
| ЗВУК НОТЫ ПЛЁН СЭМП Б|
+----------------------+
```

**Gestures:** drag a handle to change it; double-tap for the default; long-press for the exact value and "add to Морф"; two-finger tap to audition; three-finger swipe to undo.

**Hidden:** CC/NRPN numbers, channels, 0–127 scales and parameter-name lists.

### (b) НОТЫ: the piano roll that zooms into steps

**Dominant visualization:** "the Carpet". Notes are bars in the track color, with opacity showing velocity. Above them runs a 16-cell trig ruler, with up to 8 pages for 128 steps.

**Semantic zoom:** pinch in and the roll collapses into the hardware's 16 trig squares, one row per track. Pinch out and the roll returns. It is one object seen from two distances.

- **Drawing:** draw notes in draw mode (B), and draw over a note to erase it. Velocity is a lane of stalks you comb across.
- **Fold to scale:** uses the device's keyboard scales, so wrong notes cannot be placed.
- **Parameter locks:** small colored dots above notes. Tap a dot to open a lane, then drag across steps to draw locks, Ableton-envelope style.
- **Other trig detail:** micro-timing is a visible offset from the grid line. A trig condition is a dot glyph (1:2 = ●○). Retrigs are drawn as a comb.
- **MIDI Capture (Ⓒ):** keeps what was played on the device in the last loop, already quantized.

**Patterns:** the Pattern Wall shows banks A–H × 16 slots, filled when read and hollow when unknown. Tap a slot to read it into the Carpet. Drag a pattern onto a slot to write it with hold-to-commit: a 1 s ring, then an automatic backup to an Undo shelf, then a verifying re-read. Until write-back is verified on hardware, slots show a lock and bounce the drop.

**MIDI files:**

- **Import:** drop a `.mid`; each track becomes a clip tile to drag onto a rail tile.
- **Export:** drag a clip or pattern to Finder (share sheet on iOS) to get a `.mid` with one named track per Digitone track.

```
+-[●DN2] ЗВУК [НОТЫ] ... ------------------- [▶ 120] [●] [Ⓒ]-+
| A |  1 . . . 5 . . . 9 . . . 13 . . .  ‹page 1/4›        |
| ■ | C4|      ████        ████                             |
| ■ | A3|  ███       ███          ███    · · plock dots     |
| B | F3|████                ██                             |
| ○ | velocity  ||| | ||  |||  |  ||                        |
| ○ | FLTR·F    ~~~~/‾‾‾‾\____/‾‾ (drawn lane)              |
+-[1][2][3][4][5][6][7][8][9][10][11][12][13][14][15][16]---+
```

```
+----------------------+
| A01  ▶120  Ⓒ  ✎      |
| 1 . . . 5 . . . 9 .  |
| C4|   ███     ███    |
| A3| ██    ██         |
| F3|█          ██     |
| vel ||| | ||  |||    |
| ■■■■■■■■■■■■■■■■     |
| ЗВУК НОТЫ ПЛЁН СЭМП Б|
+----------------------+
```

On iPhone, the step view is the default and the Pattern Wall is a pull-down sheet.

**Hidden:** song mode, the arpeggiator and euclidean editors, numeric note fields, and the quantize dialog. To quantize, swipe two fingers toward the grid; each swipe applies 25 %.

### (c) БИБЛИОТЕКА: covers you can hear

**Dominant visualization:** a wall of covers. Each preset shows an **Отпечаток** ("fingerprint"): a circular spectrum ring, like a vinyl label, rendered from a 2-second USB audition recorded when the preset entered the library. Its hue shows the category.

- **No audio yet:** a dashed glyph from the machine icon and a name hash.
- **Playing:** tap to hear the stored preview instantly, device or not. Hold to send it to the current track, once that transfer is verified.
- **Shelves:** **+Drive** (A–H × 256), **Проект** (the project pool of 128) and **Crates** (user collections).
- **Import:** drop a `.syx` bank onto a shelf. Tiles land one by one, and their covers develop like Polaroids as previews are captured.
- **Export:** drag tiles out to get `.syx`. Dragging out a crate produces a `.sixteen` package with syx files, previews and tags.
- **Найти похожее** ("Find similar"): drop a cover on the search field to rank the library by spectral similarity.

```
+-[●DN2] ... [БИБЛ] -------------------- [ поиск / drop ] -+
| +Drive A B C D E F G H | Проект | Crates ▣ ▣ ▣           |
|  (◎)  (◎)  (◎)  (◎)  (◎)  (◎)  (◎)  (◌)                 |
|  BASS1 PAD2 KICK  ...                (◌ = no preview)    |
|  (◎)  (◎)  (◌)  (◎)  (◎)  (◎)  (◎)  (◎)                 |
+-[1][2][3][4][5][6][7][8][9][10][11][12][13][14][15][16]---+
```

```
+----------------------+
| A B C D E F G H  ⌕   |
| (◎) (◎) (◎)          |
| (◎) (◌) (◎)          |
| (◎) (◎) (◎)          |
| ■■■■■■■■■■■■■■■■     |
| ЗВУК НОТЫ ПЛЁН СЭМП Б|
+----------------------+
```

**Hidden:** the difference between snapshots and presets, since both are tiles and a corner glyph shows the origin. Format pickers are hidden too: the drop target decides the format.

### (d) ПЛЁНКА: a tape that is always rolling

**Dominant visualization:** a giant waveform tape scrolling right to left, colored by its source.

- **Source plug:** shows what USB OUT sends (MAIN, one track tile, two half-tiles for L/R mono, or EXT). The app cannot switch it, so tapping the plug shows a pixel-exact **128×64 OLED picture** of the device menu to set.
- **Recording:** a coin-sized ● keeps the last pattern-length. It is locked to the Digitone's MIDI clock, so loops are always seamless.
- **Playback:** takes become clips in a tray and play **through USB IN out of the Digitone's own outputs**, so you need only one pair of headphones.
- **Resample:** record MAIN while app clips play to layer it all, Koala-style.

```
+-[●DN2] ... [ПЛЁНКА] ------------------------- [▶ 120] ----+
| [MAIN]▸ ▁▂▅▇▆▃▂▁▂▅▇█▆▃▁▁▂▃▅▇▆▄▂▁▂▃▅▇▆▄▂ ◂now              |
|  plug    |bar 1        |bar 2       |bar 3                 |
|                    ( ● )   keep last: 1 · 2 · 4 bars       |
| tray: [take1 ▁▅▃] [take2 ▂▇▅] [loop ▅▃▁]                    |
+-[1][2][3][4][5][6][7][8][9][10][11][12][13][14][15][16]---+
```

```
+----------------------+
| [MAIN]▸ ▁▅▇▃▂▅▇▆▃ ◂  |
|        ( ● )         |
| 1 · 2 · 4 bars       |
| [take1] [take2]      |
| ЗВУК НОТЫ ПЛЁН СЭМП Б|
+----------------------+
```

**Hidden:** sample rate and bit depth (always 48 kHz / 24-bit), file naming and arming.

### (e) СЭМПЛЕР: 16 pads the Digitone plays

**Dominant visualization:** a 4×4 grid of pads in track colors, each showing a waveform thumbnail. The selected sample's waveform sits above the grid.

- **Chop by transient:** one horizontal threshold line across the waveform. Drag it down and more slices appear; drag a slice onto a pad.
- **Слепок ("cast", auto-sampling):** drop a Track Rail tile onto the empty grid. The app then:
  1. plays C1–C7 in minor thirds at 3 velocities into that track,
  2. records the isolated track from USB OUT,
  3. builds a playable multisample.
- **Played by the Digitone:** a **loop cable** drawn across the top shows the path. A Digitone MIDI-machine track (∿ badge) sends notes over USB MIDI, the pads light up, and the audio returns via USB IN to the Digitone's main outputs. The hardware sequencer, p-locks and trig conditions all drive the app sampler.
- **Pad modes:** Слайсы (slices) or Клавиши (one sample played chromatically, folded to scale).
- **Fun FX:** an XY "puddle"; drag in blobs for tape-stop, reverse, stutter, crush and filter dive.

```
+-[●DN2] ... [СЭМПЛЕР] ---- DN2 trk 9 ∿ ──▶ pads ──▶ USB IN -+
| ▁▃▇█▅▃▁▁▂▅▇▆▃▁▁▃▇█▅▂▁  ───── threshold ─────  | XY FX     |
|  |    |     |     |  slices: 8                 |  ○ blob   |
| [▅▃][▇▂][▃▁][█▅]  [▂▇][▅▅][▃▇][▁▃]                         |
| [▅▃][▇▂][▃▁][█▅]  [▂▇][▅▅][▃▇][▁▃]   Слайсы | Клавиши       |
+-[1][2][3][4][5][6][7][8][9][10][11][12][13][14][15][16]---+
```

```
+----------------------+
| ▁▃▇█▅▃▁▂▅▇▆▃ ─thr─   |
| [▅▃][▇▂][▃▁][█▅]     |
| [▂▇][▅▅][▃▇][▁▃]     |
| [▅▃][▇▂][▃▁][█▅]     |
| [▂▇][▅▅][▃▇][▁▃]     |
| ЗВУК НОТЫ ПЛЁН СЭМП Б|
+----------------------+
```

**Hidden:** zone and root mapping, start/end number fields, and per-pad envelopes. One AMP drawing applies to the whole sampler.

### (f) Connection sheet (opened from the Device Pill)

**Dominant visualization:** the front panel of the Digitone II, with three cables drawn to the app: **MIDI**, **USB OUT** and **USB IN**.

Cables animate with real data (dots for MIDI, a level wave for audio). A missing cable is a dashed loose end; tap it for the OLED picture of the needed setting, such as USB CONFIG → USB AUDIO/MIDI. The OS and build are engraved on the drawn device.

```
+----------------- Digitone II · OS 1.10D b0049 -------------+
|  [ ▭▭▭ DIGITONE II  ◦◦◦◦/◦◦◦◦ ]                            |
|      ║ MIDI  ●●●●●●●  ─────────▶ app                       |
|      ║ OUT   ▁▃▅▇▅▃▁  ─────────▶ app                       |
|      ║ IN    - - - - - ✕  (tap: OLED hint)                 |
+------------------------------------------------------------+
```

```
+----------------------+
| [DIGITONE II]        |
| MIDI ●●●●───▶        |
| OUT  ▁▅▇▅───▶        |
| IN   - - ✕           |
+----------------------+
```

**Hidden:** port lists, channel tables and SysEx logs. These live in a Mac-only "Мастерская" ("Workshop").

## 5. Visual language

**Theme:** light by default, following the system setting. Colored curves on cream read like a plotter print, close to TE manuals and the silk-screened panels of Soviet instruments. The dark theme is fully equal and meant for stage use.

| Token | Light "Пломбир" | Dark "Графит" |
|---|---|---|
| Canvas | `#F3F0E8` | `#121214` |
| Tile | `#FFFFFF` | `#1E1E22` |
| Ink | `#1C1B19` | `#F2F0EA` |
| Ink secondary | `#6E6A62` | `#8E8C86` |
| Hairline | `#DDD8CC` | `#2C2C31` |
| Fog (unknown) | `#B9B4A8` dashed | `#4A4A50` dashed |
| Record | `#FF3B30` | `#FF453A` |

**Track colors:** fixed for life, and the only saturated hues in the app. Dark mode raises lightness by 8 %.

| Tracks | Colors |
|---|---|
| 1–4 | `#FF5A36` `#FF8A00` `#FFC400` `#B7D000` |
| 5–8 | `#3FC25A` `#00B39A` `#00B5E2` `#2F7BFF` |
| 9–12 | `#5B5BFF` `#8F4DFF` `#D04CF0` `#FF4FA3` |
| 13–16 | `#B8875A` `#6F9C86` `#7F88A3` `#4E5560` |

Modes have no color, so color always means "which track". Red is reserved for ●.

**Type:**

| Role | Font |
|---|---|
| Display: values under the finger, BPM | SF Pro Rounded Bold 44 |
| Title: sound names | SF Pro Rounded Semibold 22 |
| Panel label: SYN, FLTR, A–H | SF Mono Medium 12, uppercase, +6 % tracking |
| Body | SF Pro 15 |
| Micro: step numbers | SF Mono 10 |

All sizes are Dynamic Type relative.

**Shapes:** continuous corners, radius 14 for tiles (12 on iPhone) and 18 for pads; curves 2.5 pt, grids 1 pt, fog 1.5 pt with a 4/4 dash; hit targets ≥ 44 pt; no shadows.

**Icons:** SF Symbols at semibold weight, plus 6 drawn glyphs: operator, algorithm, the three value states, and ∿.

**Motion:** 1:1 under the finger; release settles on a spring (response 0.28, damping 0.82); the playhead is always linear; fog dissolves in 400 ms; tiles pulse with level, capped at 4 %.

**Haptics:** a selection tick at detents (integer FM ratios, defaults, scale notes, step snaps); rigid on step toggle; heavy on ●; success when a dump arrives; trackpad alignment ticks on Mac.

**UI sounds:** none, because the Digitone is the sound. The one exception is the count-in click, played through USB IN so it comes out of the device's own headphones.

## 6. Beyond the brief

| # | Feature | Real capability | Impact | Effort |
|---|---|---|---|---|
| 1 | **Захват ("Capture"):** always-on 2-min buffer of knob moves, notes and audio; tap to keep | CC/NRPN in, USB OUT | 5 | 2 |
| 2 | **Слепок ("Cast"):** auto-multisample any Digitone sound | MIDI notes + isolated-track USB OUT | 5 | 3 |
| 3 | **Морф ("Morph"):** XY pad between two captured states, swept with hi-res NRPN; only known values move | NRPN out | 4 | 2 |
| 4 | **Вторая рука ("Second hand"):** 8 finger-drawn LFOs or automation lanes per track, clock-synced | NRPN + MIDI clock | 4 | 3 |
| 5 | **Петля Коалы ("Koala loop"):** resample MAIN → chop → pads → sequence from a Digitone MIDI track → USB IN → resample | USB OUT/IN, MIDI machine | 5 | 3 |
| 6 | **Отпечатки ("Fingerprints"):** spectral covers and "find similar" | USB audition, SysEx presets | 4 | 3 |
| 7 | **Сцены ("Scenes"):** the Pattern Wall as a scene launcher that switches on the next bar | Program Change | 4 | 1 |
| 8 | **Стемы ("Stems"):** per-track bounce (or 2 tracks per pass as L/R mono) exported as WAV + `.mid` | USB OUT modes, pattern dump | 4 | 3 |
| 9 | **Кубик ("Dice"):** drop a dice on a drawing to randomize only its visible handles, ±20 % | CC/NRPN out | 3 | 1 |
| 10 | **Живой спектр ("Live spectrum"):** isolated-track spectrogram behind ЗВУК | USB OUT single track | 5 | 2 |
| 11 | **Кольцо ("Ring"):** euclidean ring that streams live notes to any track | MIDI notes | 3 | 2 |

## 7. Roadmap fit: one tile, many engines

Every track tile carries a **machine badge**, and every machine is presented the same way: the `SYN · FLTR · AMP · FX · MOD` strip, one drawing per page, and handles A–H.

The badge shows where the engine runs. **●** means on the Digitone. **∿** means in the app: a Digitone MIDI-machine track feeds it over USB MIDI, audio returns via USB IN, and that machine's CC knobs map 1:1 to A–H, so the hardware knobs play the virtual engine.

A new engine only brings a new SYN drawing:

| Engine | SYN drawing |
|---|---|
| SAMPLER | Waveform + threshold line |
| GRAIN | Spark cloud; center = position, width = spray |
| SPECTRAL | Paintable spectrogram |
| ADDITIVE | 32 harmonic bars to comb |
| SUBTRACTIVE | Oscillator shape + the FLTR curve |

**Custom firmware** (speculative, with no SDK) needs no redesign either. If an engine ever moves onto the device, its badge changes from ∿ to ●, and the drawing and A–H mapping stay as they are.

## 8. Simplicity ledger

**Removed:** 0–127 slider lists; CC/NRPN numbers; channel pickers (identity matching and Auto Channel detection instead); disclaimer paragraphs (three glyphs instead); the sidebar; the "Применить параметры" ("Apply parameters") button (sending is live); A/B variants (absorbed by Морф); snapshot vs preset (both are tiles); file-format and quantize dialogs; port lists (outside the Mac Мастерская).

**Hidden until needed:** exact numbers (under the finger); trig-condition editing (long-press radial); song mode, perform kit and the arpeggiator; the full euclidean sequencer; sampler zones; SysEx logs; OS/build details (engraved on the device drawing).

**Kept on purpose:** the panel's own words (SYN, FLTR, A–H). Learning the app should teach the instrument, and the other way round.

## 9. Top 5 risks

1. **Fog everywhere.** Values cannot be queried over CC, so a fresh session opens mostly hollow and may feel broken. Mitigate by decoding kit parameters from dumps once verified and by keeping last-known values per preset.
2. **USB OUT routing is set only on the device.** Слепок and Стемы need menu changes on the Digitone between passes. The OLED hints soften this but cannot remove it, and multi-pass stems may feel slow.
3. **Round-trip latency and jitter.** The path Digitone MIDI track → app sampler → USB IN can flam rhythmic parts, especially on iPhone. It needs measurement and per-device compensation.
4. **Visual noise.** Sixteen hues plus state glyphs can get busy and are hard for color-blind users. Tiles always show the track number, and fog is shown with dashes rather than with color alone.
5. **Drift toward a mini-DAW, and write safety.** Tape, sampler and roll could pull the app into being a Koala clone. Pattern write-back is also unverified, and one bad write would destroy trust. Keep writes locked until read-back verification works, and anchor every feature to a real Digitone capability.

# LUMEN — a light table for the Digitone II

**Metaphor:** the app is a photographer's light table. The Digitone's real sound is the light underneath. Every parameter, note and sample is a sheet of coloured film laid on the glass, and you shape it with your fingers while watching the light change.

---

## 1. Design principles

1. **The picture is the control.** If you can see it, you can drag it. There are no slider lists.
2. **Solidity is certainty.** Filled means known from the Digitone, outline means only in the app, dashed means unknown. Never use a sentence where a stroke will do.
3. **Mirror the panel.** A–H, SYN/FLTR/AMP/FX/MOD and the 16 trig keys look as they do on the hardware. Hands on the device move the screen.
4. **Sound first, numbers on touch.** A value is visible only while a finger or cursor is on it.
5. **One stage, one subject.** Each mode has one dominant visualization, with at most one row of chrome above it and one below.
6. **Nothing is final.** Every change can be undone. Hold **Было** to hear the previous state. The app backs up before any write to the device.

---

## 2. Information architecture

**Five modes and one object:**

| Mode | Subject | SF Symbol |
|---|---|---|
| **Звук** | Signal path of one track | `waveform.path` |
| **Ноты** | Time: project → pattern → track | `pianokeys` |
| **Библиотека** | Sound portraits | `square.grid.4x4.fill` |
| **Лента** | The audio river | `recordingtape` |
| **Сэмплер** | 16 pads and one waveform | `square.grid.3x3.square` |

The **Device** is an object, not a mode: a small drawn Digitone silhouette with a status light in the leading toolbar slot. Tapping it opens the Connection sheet.

Two elements stay visible in every mode:
- **Track ribbon.** 16 lozenges along the bottom edge, like the trig keys, tinted by machine colour.
  - Each lozenge blinks when the Digitone sends a note.
  - Tap to select a track, hold to audition it, drag up to set its level.
  - It accepts drops of sounds, MIDI files and samples.
- **Undo / Было** in the trailing corner.

**Navigation by platform:**
- **iPhone:** a five-tab bar. The device pill sits at the leading edge and a `T1 ⌄` track chip at the trailing edge. The ribbon collapses into the chip: swipe it to change track, tap it for a 4×4 grid.
- **iPad:** modes are a centred segmented control in the toolbar, like Logic for iPad's view switcher. The ribbon stays at the bottom. In any mode, a Library drawer pulls in from the left edge so sounds can be dropped onto tracks. Tape and Sampler can open as separate Stage Manager windows.
- **Mac:** the same toolbar; ⌘1–⌘5 for modes, ⌘L for the Library sidebar, everything in the menu bar. Hold **A–H** and scroll to turn that knob, like hold-and-turn on the device. Space sends MIDI Start/Stop.

**From launch to sound in under 30 seconds:**
1. **0 s:** the app opens straight into Звук, with no splash and no onboarding carousel.
2. **~1 s:** CoreMIDI finds the Digitone, the SysEx identify succeeds, and the silhouette lights up.
3. **~3 s:** the pattern and kit dump arrives. Track names fill the ribbon.
4. **~5 s:** a pulsing ring sits on lozenge 1. Tap it, a note is sent, and the Digitone plays. With USB audio on, the stage fills with the live spectrum.

Without a device, the silhouette shows a cable sliding in, and lozenge 1 plays the built-in Sampler kit, so the gesture is learned first.

---

## 3. Value-state glyphs (used everywhere)

| Glyph | Meaning | Drawing |
|---|---|---|
| ● | Known: received from the Digitone as CC/NRPN, or decoded from a dump | Solid fill in the machine colour |
| ◐ | Sent but not confirmed | Fill with an outbound ring that fades in about 1 s |
| ○ | Draft: exists only in the app | Stroke only, no fill |
| ◌ | Unknown | Dashed stroke, frosted fog, faint ghost of the last value |

When the Digitone reports a pattern or preset change, every ● fades to ◌ and keeps its ghost. That signals "stale" without words. Curves follow the same rule segment by segment: an unknown decay is drawn dashed.

---

## 4. Screens

### (a) Звук — the Signal Path

**Dominant visualization:** the path strip at the top shows SYN → FLTR → AMP → FX as glass miniatures, with MOD floating above them as a yellow wave. Tapping a miniature zooms it into the stage with a matched-geometry transition. The stage is the editor.

```
iPad / Mac landscape
┌────────────────────────────────────────────────────────────────────┐
│ ◉DN II   [Звук] Ноты Библиотека Лента Сэмплер          ↶   ◐ Было │
├────────────────────────────────────────────────────────────────────┤
│ ▣SYN ──▶ ▢FLTR ──▶ ▢AMP ──▶ ▢FX                       ∿MOD         │
│ ╭────────────────────────────────────────────────────────────────╮ │
│ │ ░░▒▒▓▓█ live spectrum from USB (the "light") █▓▓▒▒░░           │ │
│ │                 ( C )━━━━━━━━━━▶( A )━━━━▶ out                 │ │
│ │                   ▲                                            │ │
│ │       ↻( B1 )━━━━━┛       ( B2 )┅┅┅ ◌                          │ │
│ │        ╲__╱ env tail       ╲┅┅╱                                │ │
│ ╰────────────────────────────────────────────────────────────────╯ │
│    A●     B●     C◐     D●     E◌     F◌     G●     H○             │
│   ALGO    C      A      B     HARM   DTUN   FDBK   MIX             │
├────────────────────────────────────────────────────────────────────┤
│ ▮1 ▯2 ▯3 ▯4 ▯5 ▯6 ▯7 ▯8 ▯9 ▯10 ▯11 ▯12 ▯13 ▯14 ▯15 ▯16            │
└────────────────────────────────────────────────────────────────────┘
```
```
iPhone portrait
┌───────────────────────────┐
│ ◉   KICK_SHARP    T1⌄  ◐  │
│ SYN·FLTR·AMP·FX   ∿       │
│ ╭───────────────────────╮ │
│ │     (C)━━▶(A)         │ │
│ │      ▲                │ │
│ │  ↻(B1)   (B2)┅        │ │
│ ╰───────────────────────╯ │
│   A●   B●   C◐   D●       │
│   E◌   F◌   G●   H○       │
│ Звук Ноты Библ Лента Сэмп │
└───────────────────────────┘
```

- **FM (SYN):** operators C, A, B1 and B2 are glass discs laid out by the current algorithm, with light beams for the modulation routes.
  - Disc size is level, the number of concentric rings is the ratio, and a curled arc is feedback.
  - Swipe across the constellation to change algorithm; the beams re-route with a spring.
  - Pinch a disc to change its ratio, with a haptic detent at each integer.
  - Each disc has an envelope tail you can drag. This replaces flipping to the second SYN page.
- **Other machines:** WAVETONE shows two oscillator shapes, SWARMER a voice cloud, FM DRUM body plus transient.
- **FLTR:** a response curve over the isolated track's real spectrum.
  - Drag the peak: horizontal is cutoff, vertical is resonance.
  - Envelope depth is a translucent band showing the sweep range.
  - The type is picked from six drawn curve glyphs: MULTI-MODE, LOWPASS 4, LEGACY LP/HP, COMB−, COMB+ and EQUALIZER.
- **AMP:** one large envelope with draggable corners and a faint gate bar.
- **FX:**
  - a staircase sine for bit reduction;
  - an S-curve for overdrive;
  - sample-and-hold dots for sample-rate reduction;
  - three glass "taps" for the DELAY, REVERB and CHORUS sends.
- **MOD:** the LFO shape. Drag horizontally for speed and vertically for depth. A yellow beam runs to the destination, which wobbles in its miniature.
- **Knob rail A–H:** mirrors the current hardware page, with silkscreen labels.
  - **Follow hands:** when a hardware knob sends a CC, the app jumps to that page and lights the knob.
  - A large SF Mono readout appears only while touching.
- **Gestures:**
  - drag vertically on a knob (Mac: scroll or arrow keys);
  - two-finger tap to reset to default;
  - hold a lozenge to audition.
- **Hidden:**
  - CC and NRPN numbers;
  - 0–127 values;
  - channel fields;
  - the "Apply" button (changes send live and can be undone);
  - the A/B panel (replaced by Было).

### (b) Ноты — semantic zoom, like Photos

**Dominant visualization:** one canvas at three levels. Pinch to change level; on Mac use ⌘+ / ⌘−.
1. **Проект:** an 8×16 grid of the 128 patterns, each cell a note miniature. Cells not yet read are fogged.
2. **Паттерн:** 16 lanes of step dots in machine colours. Lane lengths are visible.
3. **Трек:** a piano roll over a strip of 16 trig keys. Page dots show the page for patterns up to 128 steps.

```
iPad / Mac landscape — Трек level
┌────────────────────────────────────────────────────────────────────┐
│ ◉DN II   Звук [Ноты] Библиотека Лента Сэмплер        A01 ●   ↶ ◐  │
├────────────────────────────────────────────────────────────────────┤
│  Проект ‹ Паттерн ‹ Трек 1                                         │
│ C4 ┃       ▬▬▬◆             ▬▬                  ▬▬▬▬▬              │
│ B3 ┃ ▬▬                 ⚄▬▬       ▬▬                               │
│ A3 ┃           ▬:2            ▬▬▬                       ▬▬         │
│ G3 ┃ ▬▬▬▬▬▬              ↤▬▬                                       │
│    ┃ 1 · · · 5 · · · 9 · · · 13 · · ·                              │
│ ┌──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┐   ● ○ ○ ○         │
│ │██│  │  │  │██│  │  │  │██│  │  │  │██│  │  │  │                   │
│ └──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┘                   │
│ ▮1 ▯2 ▯3 ▯4 ▯5 ▯6 ▯7 ▯8 ▯9 ▯10 ▯11 ▯12 ▯13 ▯14 ▯15 ▯16            │
└────────────────────────────────────────────────────────────────────┘
```
```
iPhone portrait = trig keys        iPhone landscape = piano roll
┌───────────────────────┐          ┌──────────────────────────────┐
│ ◉  A01 · T1      ◐    │          │ C4 ┃   ▬▬◆      ▬▬   ▬▬▬     │
│ ┌────┬────┬────┬────┐ │          │ A3 ┃ ▬▬    ⚄▬▬         ▬▬   │
│ │ C4 │    │    │    │ │          │ G3 ┃▬▬▬▬     ↤▬▬            │
│ │ A3 │ ◆  │ ⚄  │    │ │          │    ┃1 · · · 5 · · · 9 · · · │
│ ├────┼────┼────┼────┤ │          └──────────────────────────────┘
│ │ …  4×4 trig keys  │ │
│ └────┴────┴────┴────┘ │
│ Звук Ноты Библ Лента …│
└───────────────────────┘
```

- **Glyphs inside note heads:**
  - ◆ marks a parameter lock;
  - ⚄ marks probability;
  - dot pairs mark conditions such as 1:2;
  - a tail (↤) shows micro-timing;
  - ticks inside the bar show retrigs.
  - Brightness is velocity; a velocity lane appears only while a note is touched.
- **Parameter locks the hardware way:** hold a note and turn a knob in the rail. That knob turns solid and the note gains ◆.
- **Import:** drop a `.mid` file onto the Pattern level. Each MIDI channel appears as a ghost lane, with short arrows showing how notes will move on quantize. Drag a ghost onto a track lozenge to accept it.
- **Export:** drag a pattern cell or lane out to Files to get a `.mid`.
- **Reading:** automatic on each pattern change; the fog clears.
- **Writing:** until direct write is verified on hardware, **Впечатать** (Imprint) streams the notes while the user holds LIVE REC. An OLED-style picture shows the buttons to hold. Once verified, writing becomes a drag onto a slot cell, with an automatic backup and undo.
- **Hidden:** tick numbers, numeric velocity, step tables.

### (c) Библиотека — portraits, not names

**Dominant visualization:** a wall of **sound portraits**, 16 per row like the trig keys. Tabs: A–H, then **Проект** (pool of 128), **Мои** (local) and **Пойманные** (caught).

Each portrait is a radial spectrum flower:
- the petals are the harmonics;
- their sharpness is the attack;
- the hue is the machine colour.

A sound never heard is a fogged disc with a machine-coloured outline: unheard looks unheard.

```
iPad / Mac landscape
┌────────────────────────────────────────────────────────────────────┐
│ ◉DN II   Звук Ноты [Библиотека] Лента Сэмплер              ⌕   ⇪   │
├────────────────────────────────────────────────────────────────────┤
│  A  B  C  D  E  F  G  H  │ Проект │ Мои │ Пойманные    ◍FM ◍DR ◍WT ◍SW │
│  ✿  ❀  ✿  ◌  ✿  ❁  ✿  ✿  ❀  ◌  ✿  ✿  ❁  ✿  ◌  ✿                   │
│  ❀  ✿  ❁  ✿  ◌  ✿  ❀  ✿  ✿  ✿  ❁  ◌  ✿  ❀  ✿  ✿                   │
│  ✿  ◌  ✿  ❀  ✿  ✿  ✿  ❁  ◌  ✿  ✿  ❀  ✿  ✿  ❁  ✿                   │
│ ╭──────────────────────────────────────────────────────────────╮  │
│ │  ❀  GLASS_BASS   ▁▃▇█▆▄▂▁   A● B● C● D○ E● F● G● H●   ⇢ T3     │  │
│ ╰──────────────────────────────────────────────────────────────╯  │
│ ▮1 ▯2 ▯3 ▯4 ▯5 ▯6 ▯7 ▯8 ▯9 ▯10 ▯11 ▯12 ▯13 ▯14 ▯15 ▯16            │
└────────────────────────────────────────────────────────────────────┘
```
```
iPhone
┌───────────────────────┐
│ ◉  A ⌄    ⌕   ⇪       │
│ ✿ ❀ ✿ ◌               │
│ ❁ ✿ ✿ ❀   4 per row   │
│ ✿ ◌ ❀ ✿               │
│ ─ GLASS_BASS ▁▃▇▆▂ ─  │
│ Звук Ноты Библ Лента …│
└───────────────────────┘
```

- **Audition:** hold a portrait to play its cached preview. The device is never touched.
- **Load:** drag a portrait onto a track lozenge. The previous sound is snapshotted first, and the load can be undone.
- **Similar sounds:** pull a portrait toward you and spectrally similar sounds gather around it like iron filings. Name search (⌕) is secondary.
- **Import:** drop a `.syx` bank or preset anywhere. Its contents appear as portraits in a **tray** before anything is filed or sent.
- **Export:**
  - drag portraits out to get a `.syx`;
  - `⇪` also offers a **Lumen archive** (`.lumen`), which holds the raw `.syx`, previews, portraits, patterns and samples;
  - AirDrop and Files are supported.
- **Hidden:** tag taxonomies, folders and metadata forms. Tags are derived from the machine type and the portrait's shape.

### (d) Лента — the river

**Dominant visualization:** a waveform river scrolling past a fixed playhead, as in Voice Memos, with a bar ruler driven by MIDI clock. The river's colour is its source: ink for MAIN, the machine colour for a track, grey for EXT.

```
iPad / Mac landscape
┌────────────────────────────────────────────────────────────────────┐
│ ◉DN II   Звук Ноты Библиотека [Лента] Сэмплер              ♩120    │
├────────────────────────────────────────────────────────────────────┤
│  ╭───────╮   1 · · · 2 · · · 3 · · · 4 · · · ┃ 5                   │
│  │ MAIN  │  ▁▂▅▇▆▃▂▁▂▄▇█▇▅▂▁▁▂▅▇▆▃▂▁▂▄▇█▇▅▂┃                      │
│  │ ◉ T3  │  ▁▂▅▇▆▃▂▁▂▄▇█▇▅▂▁▁▂▅▇▆▃▂▁▂▄▇█▇▅▂┃                      │
│  │ ◑◐ 2×1│                                   ┃                     │
│  │ EXT   │                                                         │
│  ╰───────╯                                                         │
│   ⟲ Захват 8 тактов           (  ●  )            ▶ ⇢ ⎍ Digitone    │
│   ▭ дубль 3 · 0:12      ▭ дубль 2 · 0:31      ▭ дубль 1 · 1:04       │
└────────────────────────────────────────────────────────────────────┘
```
```
iPhone
┌───────────────────────┐
│ ◉  Лента       ♩120   │
│ ▁▂▅▇▆▃▂▁▂▄▇█▇▅┃       │
│ MAIN ◉T3 ◑◐ EXT       │
│        ( ● )          │
│ ⟲ 8 тактов   ▶ ⇢ ⎍    │
│ ▭ дубль 3  ▭ дубль 2  │
└───────────────────────┘
```

- **Source dial:** four positions, one per USB OUT option: MAIN, one track, two tracks as L/R mono, or EXT. The app cannot switch the Digitone's routing itself. Choosing a position the device isn't set to shows an OLED-style picture of the setting to change.
- **⟲ Capture:** keeps the last bars from an always-on buffer.
- **Recording:** the big round button, the only red thing in the app. Takes stack as strips of glass. Swipe a take away to delete it; it remains recoverable.
- **Playback:** through the Mac or iPad, or **⇢ ⎍** back through USB IN to the Digitone's outputs.
- **Takes:** trimmed to bars; drag one to a pad or to Files.
- **Hidden:** gain staging, format choice (always 48 kHz/24-bit WAV) and track arming.

### (e) Сэмплер — 16 pads, one waveform

**Dominant visualization:** the selected pad's waveform fills the stage, and slices are drawn directly on it. Below are 16 pads in a row, like the trig keys, each with a tiny waveform.

```
iPad / Mac landscape
┌────────────────────────────────────────────────────────────────────┐
│ ◉DN II   Звук Ноты Библиотека Лента [Сэмплер]         T9 ⇄ ⎍  ↶ ◐ │
├────────────────────────────────────────────────────────────────────┤
│ ╭────────────────────────────────────────────────────────────────╮ │
│ │ ▁▂▇█▅▃▂│▁▁▆█▆▃│▂▁▃▇█▅▂▁│▁▂▆▇▄▂▁│▁▃▇▆▂│                         │ │
│ │ ◁ start                                   end ▷     ⟲ loop     │ │
│ ╰────────────────────────────────────────────────────────────────╯ │
│  A●START B●LEN C●PITCH D●LOOP E●ATK F●DEC G●FLTR H●VOL             │
│ ┌──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┐                   │
│ │▁▇│▆▂│▇▃│▂▅│▃▇│  │  │  │  │  │  │  │  │  │  │  │                   │
│ └──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┘                   │
│ ▮1 ▯2 ▯3 ▯4 ▯5 ▯6 ▯7 ▯8 ▯9⇄ ▯10 ▯11 ▯12 ▯13 ▯14 ▯15 ▯16           │
└────────────────────────────────────────────────────────────────────┘
```
```
iPhone
┌───────────────────────┐
│ ◉  Сэмплер   T9⇄⎍     │
│ ▁▂▇█▅│▁▆█▆▃│▂▃▇█▅     │
│  A● B● C● D●          │
│  E● F● G● H●          │
│ ┌──┬──┬──┬──┐ 4×4     │
│ │▁▇│▆▂│▇▃│▂▅│ pads    │
│ └──┴──┴──┴──┘         │
│ Звук Ноты Библ Лента …│
└───────────────────────┘
```

- **Chopping:**
  - tap the waveform to add a slice, and drag an edge to move it;
  - comb downward to auto-slice at transients, then pinch to change the slice count;
  - drag a slice onto a pad to assign it.
- **Слепок (Cast) — automatic sampling of a Digitone track:**
  1. Drag a track lozenge onto the keyboard strip.
  2. Sweep across the keys to set the range; a second swipe sets velocity layers.
  3. The app plays each note and records that track in isolation via USB OUT. Track outputs are pre-effects, so the samples are dry.
  4. Each key fills with its waveform as it is captured.
- **Played by the Digitone:** set a track to a MIDI machine and the lozenge shows `⇄`. The Digitone sequences the pads, and their audio returns via USB IN to MAIN. Pads flash on each trig, and the MIDI track's knobs map to A–H.
- **Hidden:** zones, root-key tables and modulation matrices.

### (f) Прибор — the device portrait (a sheet)

**Dominant visualization:** a line drawing of the front panel.
- Knobs A–H light as their CC arrives.
- Trig keys blink on notes.
- The MIDI and USB-audio cables carry flowing dots in the direction the data moves.

Below the drawing, each required setting is a light: USB CONFIG, PORT CONFIG, RECEIVE CC/NRPN, ENCODER DEST and PARAM OUTPUT.
- A light turns ● only when real traffic proves the setting; for example, an incoming CC proves PARAM OUTPUT.
- Tapping a hollow light shows a 128×64 OLED-style picture of the exact menu row to change.

```
iPad / Mac (sheet)                               iPhone (sheet)
┌──────────────────────────────────────────────┐  ┌──────────────────────┐
│        Digitone II · OS 1.10D · 0049          │  │ Digitone II · 1.10D  │
│ ╭──────────────────────────────────────────╮ │  │ ╭──────────────────╮ │
│ │ ▭OLED   ◯◯◯◯ ◯◯◯◯     knobs light on CC   │ │  │ │ ▭  ◯◯◯◯ ◯◯◯◯    │ │
│ │ ▢▢▢▢▢▢▢▢▢▢▢▢▢▢▢▢    keys blink on notes  │ │  │ │ ▢▢▢▢▢▢▢▢▢▢▢▢▢▢▢▢ │ │
│ ╰──────┬───────────────────────────┬───────╯ │  │ ╰───┬──────────┬───╯ │
│   MIDI ⇣⇡ •••→              USB AUDIO ⇣● ⇡○   │  │  MIDI ⇣⇡    AUDIO ⇣● │
│ ● USB CONFIG  ● PORT  ● CC/NRPN  ◌ ENCODER    │  │ ● ● ● ◌  AUTO CH 10  │
│ AUTO CH 10 ●      «Поверни любую ручку»       │  │ «Поверни ручку»      │
└──────────────────────────────────────────────┘  └──────────────────────┘
```

- **Auto Channel:** the one sentence on the sheet asks the user to turn any knob. The app detects the Auto Channel and lights it.
- **Hidden:** port pickers, raw SysEx (Mac ⌥-click only) and troubleshooting text.

---

## 5. Visual language

**Decision: light-first, full dark mode.** A light table glows pale: machine colours read as translucent film, it works in daylight, and it is not another black DAW. Night mode (system setting, for stage) turns the films emissive on near-black, like the OLED.

| Token | Day | Night |
|---|---|---|
| Table (background) | `#F2F1EC` | `#0B0B0D` |
| Stage surface | `#FFFFFF` | `#161618` |
| Ink | `#17171A` | `#F4F3EE` |
| Ink secondary | `#6B6B70` | `#8C8C92` |
| Hairline | `#DCDAD3` | `#2A2A2E` |
| Fog (◌) | Ink at 8% + dashed stroke | Ink at 10% + dashed stroke |

**Colour semantics:** colour means *what kind of sound*, never decoration.

| Hex | Meaning |
|---|---|
| `#FF6A00` | FM TONE |
| `#2F6BFF` | FM DRUM |
| `#00A99D` | WAVETONE |
| `#B04DFF` | SWARMER |
| `#8E8E93` | MIDI machine (outline only) |
| `#FF5FA2` | Lumen engines (sound made in the app) |
| `#FFC400` | Modulation (always animated and dashed) |
| `#FF3B30` | Recording only |

Every machine also has a glyph shape, so colour is never the only carrier of meaning.

**Typography (system fonts, Dynamic Type):**
- **Readout:** SF Mono Light 44, for the value while dragging.
- **Title:** SF Pro Rounded Semibold 22, for sound and track names.
- **Body:** SF Pro Text 17.
- **Panel:** SF Pro Text Semibold 11, caps, +6% tracking, for silkscreen labels (SYN, FLTR, A–H).
- **Micro:** SF Mono 11, for axes, BPM and OS build.
- At accessibility sizes the A–H rail reflows to two rows of 4.

**Shape:**
- 8 pt grid.
- Concentric corner radii: 22 for the stage, 14 for pads, 8 for lozenges.
- Strokes: 1 pt for chrome, 2 pt for curves, 3 pt for the selected curve.
- Handles are 12 pt dots with 44 pt hit areas.
- Shadows appear only while dragging.
- Material only on drawers and sheets; the stage stays matte so curves are crisp.

**Iconography:**
- SF Symbols for system actions.
- Drawn glyphs at SF Symbols Regular weight:
  - FM TONE: nested rings;
  - FM DRUM: a ring with a strike mark;
  - WAVETONE: a sine in a square;
  - SWARMER: five scattered dots;
  - MIDI: a DIN socket;
  - Lumen engine: a ring with a cable.
- Filter types and trig conditions are drawn glyphs too.

**Motion:**
- **Light reveals:** fog dissolves over 200 ms when a value becomes known.
- Hardware-driven changes never animate; they track the knob 1:1.
- App-driven changes use a spring (response 0.3, damping 0.85).
- Changing mode zooms from the miniature into the stage.
- With Reduce Motion: 150 ms cross-fades, and the spectrum is smoothed to 10 Hz.

**Haptics (iOS, plus the Force Touch trackpad):**
- detents at integer FM ratios, at bipolar centres and at the range ends;
- a rigid tick when a note snaps to the grid;
- a heavy impact when recording is armed;
- success when a Catch arrives.

**UI sounds:** none. The Digitone is the only voice, apart from the optional metronome.

**VoiceOver:** canvas handles are adjustable elements that speak their state («Срез, известно, 1,2 кГц»).

---

## 6. Beyond the brief

| # | Feature | How it works on real capabilities | Impact | Effort |
|---|---|---|---|---|
| 1 | **Портреты** (Sound portraits) | Program change to a pattern, a note on each track, and an isolated USB OUT recording. Portraits and previews for all 128×16 kit sounds and every caught preset. | 5 | 3 |
| 2 | **Слепок** (Cast) | Automatic multisampling of a track, which then plays without the device. | 5 | 3 |
| 3 | **Захват** (Capture) | An always-on USB audio buffer; keep the last 8 bars. | 4 | 2 |
| 4 | **Ловушка** (Catch) | A passive SysEx receiver. Anything the Digitone sends lands in Пойманные with a portrait. | 4 | 1 |
| 5 | **Впечатать** (Imprint) | A `.mid` streamed into LIVE REC. Pattern writing before the dump-write format is solved. | 4 | 2 |
| 6 | **Жест** (Gesture) | Records hardware knob moves (CC/NRPN) as curves, then replays them or converts them to per-step parameter locks. | 4 | 3 |
| 7 | **Морф** (Morph puck) | An XY puck between four sound states, gliding over high-resolution NRPN. | 4 | 2 |
| 8 | **Призрачные LFO** (Ghost LFOs) | Drawn, clock-synced LFOs on any NRPN, beyond the three MOD pages. | 3 | 3 |
| 9 | **Прожектор** (Spotlight) | Two tracks as L/R mono via USB OUT; their spectra overlap and the collisions glow (kick vs bass). | 3 | 2 |
| 10 | **Контактный лист** (Contact sheet) | Reads all 128 patterns and exports the project as a folder of `.mid` files. | 4 | 2 |
| 11 | **Второй экран** (Second screen) | An iPhone next to the device shows the current page as a giant OLED, via network MIDI from the Mac. | 3 | 3 |

---

## 7. Roadmap fit

The app treats every machine as the same kind of object, so new engines need no redesign. Each machine supplies three things:
1. one stage visualization, which is also its control;
2. up to 8 parameters per page, labelled A–H, under SYN/FLTR/AMP/FX/MOD;
3. a value-state source. Hardware machines can show ◌. App engines are always ●, because the app knows their whole state.

**App-side "Lumen machines"** appear in the same machine picker, in pink with the cable glyph. On the Digitone the track is a MIDI machine, and the audio returns through USB IN.

| Engine | Stage visualization |
|---|---|
| Sampler | Sliced waveform |
| Granular | A grain cloud over the waveform: drag it for position, spread it for width; the particle count is density |
| Spectral | A spectrogram you paint, freeze and blur |
| Additive | 32 glowing harmonic drawbars, combed with one finger |
| Subtractive | Oscillator shape plus the existing FLTR curve |

**Hypothetical custom firmware:** if an engine ever runs inside the Digitone, the cable glyph and the `⇄ ⎍` loop disappear, and its values gain hardware states. Layout, gestures and colour stay the same.

---

## 8. Simplicity ledger

**Removed:**
- the sidebar;
- 0–127 slider lists;
- paragraphs of disclaimers (replaced by ● ◐ ○ ◌);
- channel fields and port pickers (replaced by "turn any knob");
- the «Применить параметры» button (changes send live and can be undone);
- the A/B snapshot panel (replaced by Было);
- the mixer view (drag up on a lozenge);
- file dialogs (replaced by drag and drop and the share sheet);
- tag forms;
- UI sounds.

**Hidden until touched:** numbers, the velocity lane, parameter-lock details and trig-condition menus.

**Mac ⌥ only:** SysEx inspector, CC/NRPN numbers, dump hex. **Never shown:** how-to text longer than one line.

---

## 9. Top 5 risks

1. **A foggy app.** The Digitone cannot report its full sound, so many controls may sit at ◌ and Lumen could look broken.
   - *Mitigation:* decode as much as possible from the kit dump, rely on Follow hands, and add a 10-second «обойди ручки» ritual (turn each knob once).
2. **Depending on USB audio setup.** Portraits, Cast, Spotlight and the spectrum all need USB AUDIO/MIDI mode and the correct USB OUT routing, which only the user can set. Audio and MIDI together through iPhone adapters may be fragile.
   - *Mitigation:* everything degrades gracefully to MIDI-only and shows less light.
3. **Latency of app engines.** The round trip from a Digitone MIDI trig to returned USB audio adds offset and jitter.
   - *Mitigation:* measure it, compensate with negative micro-timing on the MIDI track, and show a warning glyph if jitter exceeds about 3 ms.
4. **Undocumented formats.** Pattern write, preset transfer and the +Drive API are reverse-engineered and may change with an OS update.
   - *Mitigation:* back up before every write, gate each operation on the detected OS and build, and use Imprint and Catch as safe fallbacks.
5. **Visualization becoming decoration.** Drawn controls can be imprecise, slow on iPhone, or invisible to VoiceOver.
   - *Mitigation:* every visual must be draggable, have an accessible adjustable element and a keyboard path, and hold 60 fps on the oldest supported iPhone.

# ПУЛЬТ ДН-2 — the Digitone II as a measuring instrument

## 1. Concept

**ПУЛЬТ ДН-2** (Pult, "control desk"; ДН-2 is the Digitone II's "factory index").

> A warm-white Braun instrument panel bolted onto the Digitone II. Every sound is a trace you grab with your finger, every state is a lamp, and only one key on the screen is ever orange.

It is not a "DAW" or an "editor". It is the big front panel the Digitone never had: an oscilloscope, a frequency analyzer, a chart recorder, a tape deck and a mimic diagram, each wired to the real device.

## 2. Design principles

1. **The trace is the control.** You change a parameter by dragging the curve, needle or dot it draws. There are no standalone sliders.
2. **One orange.** Each screen has exactly one accent key: the action that turns intent into sound (ПРОБА, ● ЗАПИСЬ, В ПРИБОР).
3. **Lamps, not sentences.** State is shown as line style plus lamp: dashed means unknown, solid means known, a hollow lamp means sent and a filled lamp means heard back. The app has no disclaimer text.
4. **Panel = device.** The 8 encoders A–H always sit in one bottom strip, in hardware order, with hardware labels. Touch one on either side and the matching element lights on the other.
5. **Follow the hand.** When a hardware knob turns, the screen flips to that page and shows the change. The app is the Digitone's big display.
6. **Graphite on paper.** Warm off-white body and graphite ink. Colour appears only where it means something: machine, lamp, the orange key.

## 3. Information architecture

**Five modes plus one lamp.** The mode selector is drawn as a flat rotary switch: labels in silk-screen caps with a single ▲ pointer that clicks into detents.

| Mode | Instrument | Question it answers |
|---|---|---|
| ЗВУК (sound) | oscilloscope / analyzer | What does this track sound like, and how do I bend it? |
| НОТЫ (notes) | chart recorder | What plays, and when? |
| ЛЕНТА (tape) | tape deck + VU meters | What came out? |
| СЭМПЛЕР (sampler) | waveform plate + 16 pads | What can I cut and replay? |
| АРХИВ (archive) | card catalogue | Which sound do I want? |
| ● СВЯЗЬ lamp | mimic diagram (мнемосхема) | Is the wiring alive? |

СВЯЗЬ (link) is not a mode. It is the lamp in the top-left corner. Tapping it opens the mimic diagram: a sheet on iPhone, a pop-down panel on iPad and Mac.

**Global frame, iPad and Mac:**
```
┌───────────────────────────────────────────────────────────────┐
│ ● ДН-2   ЗВУК · НОТЫ · ЛЕНТА · СЭМПЛЕР · АРХИВ   ▶ ■  120.0  │
│                ▲                                              │
├────┬──────────────────────────────────────────────────────────┤
│ 01▪│                                                          │
│ 02▪│          DOMINANT INSTRUMENT (is the control)            │
│ …  │                                                          │
│ 16▪│                                                          │
├────┴──────────────────────────────────────────────────────────┤
│  (A)  (B)  (C)  (D)  (E)  (F)  (G)  (H)          [ ПРОБА ]    │
└───────────────────────────────────────────────────────────────┘
```
The left rail holds the 16 tracks as trig-key squares, each with a machine-colour stripe and glyph. A track's lamp blinks when MIDI for it arrives.

- **Mac:** one panel, no sidebar. ⌘1–⌘5 switch modes, 1–8 pick encoders, arrows nudge, space plays.
- **iPad:** same frame; Apple Pencil draws notes and spectra.
- **iPhone:** the rotary becomes a bottom row of five words; the rail becomes a drum counter (`03`) top-left (swipe to change track, tap for a 4×4 grid); the A–H strip shows four encoders, swipe for the rest.

**Launch to sound in under 30 s:**
1. 0 s: lamps warm up in sequence (400 ms, once).
2. ~2 s: CoreMIDI auto-scan and SysEx identify; the lamp turns green, the nameplate reads `ДН-2 · OS 1.12`.
3. ~4 s: pattern and kit dump read; track names fill the rail.
4. ~5 s: the app lands on ЗВУК, track 01; orange ПРОБА pulses once. Press it and the Digitone plays.

With no device, ДН-С loads a factory tape and ПРОБА plays through the phone speaker.

## 4. Screens

### Value-state grammar (shared)

| Glyph | Line | Meaning |
|---|---|---|
| `(◌)` dotted ring, needle parked at rest stop | dashed trace | unknown: never heard from the device |
| `(○)` needle + hollow lamp | solid trace | sent by the app, no echo yet |
| `(●)` needle + filled lamp | solid trace | heard from the device (CC/NRPN or dump) |

The dashed line borrows the drafting convention for hidden lines (GOST 2.303). Engineers already read it as "exists, but not seen". When a dump confirms a value, its lamp fills with a 120 ms flash.

### (a) ЗВУК — the oscilloscope

**Dominant visualization:** one big instrument per hardware page, chosen by a page selector of hardware labels (`SYN1 · SYN2 · FLTR · AMP · FX · MOD`):

- **SYN (FM TONE): the algorithm diagram.** Operators C, A, B1, B2 are circles wired as the current ALGO.
  - Drag an operator vertically for level (modulation index; its halo grows), horizontally for ratio, snapping to harmonic ticks with a haptic detent.
  - Swipe the empty field to turn through algorithms; the wiring re-routes like a patch bay.
  - Beside it, a live trace: the real output when a track is isolated over USB audio, otherwise a computed preview drawn dashed (a model, not the device).
- **FLTR: frequency response.** The filter curve over the track's live spectrum. Drag the knee: x = frequency, y = resonance. The envelope plays as a ghost sweep on each trig.
- **AMP: the envelope.** An ADSR polyline; drag the nodes.
- **FX: the signal path.** One drawn stage per effect: staircase sine (bit reduction), transfer curve (overdrive), sample-and-hold (SRR), three needle gauges for DELAY, REVERB, CHORUS sends.
- **MOD: the LFO trace.** Drag x for speed, y for depth; a wire runs to the target element, which visibly wobbles.

FM DRUM, WAVETONE and SWARMER get their own SYN instrument (wavetable strip, swarm of detuned dots); the page grammar stays.

**A–H mapping:** the strip mirrors the hardware page 1:1, same labels and order. Touch a knob and its element outlines; turn the hardware encoder and the page flips to it (follow the hand) while the needle moves live.

```
iPad / Mac
┌ SYN1 · SYN2 · FLTR · AMP · FX · MOD ─────────── ◎ FM TONE ┐
│      (C)◄────(A)            ┌─────────────────────────┐   │
│       ▲       ▲             │ ∿∿∿∿∿∿  live trace       │   │
│     (B1)────(B2)            └─────────────────────────┘   │
│   ½  1  2  3  4  5  6  7  8   ← ratio ticks               │
├───────────────────────────────────────────────────────────┤
│ ALGO  C    A    B   HARM DTUN FDBK  MIX                    │
│ (●)  (●)  (●)  (○)  (●)  (◌)  (●)  (●)       [ ПРОБА ]    │
└───────────────────────────────────────────────────────────┘
iPhone
┌──────────────────────┐
│ 03 ◎ FM TONE   ● 120 │
│ SYN1 FLTR AMP FX MOD │
│   (C)◄──(A)   ∿∿∿∿   │
│    ▲     ▲           │
│  (B1)──(B2)          │
│ (A)  (B)  (C)  (D) ›│
│ [      ПРОБА       ] │
│ ЗВУК НОТЫ ЛЕНТА СЭМ АРХ│
└──────────────────────┘
```
**Gestures:** drag to change; two-finger drag for fine (hi-res NRPN); double-tap restores the last value heard from the device; long-press for numeric entry; hold ПРОБА and slide along it to change pitch.

**Hidden:** CC/NRPN numbers, MIDI channel, raw 0–127 values (shown in SF Mono only during a drag).

### (b) НОТЫ — the chart recorder

**Dominant visualization:** a paper chart-recorder roll (самописец). Notes are graphite bars whose thickness shows velocity; parameter locks are lamp dots on the note head; trig conditions are small glyphs.
- **Semantic zoom:** pinch out and the roll collapses into 16 trig-key squares; the step view *is* the roll at low zoom. Pinch further and the 128 patterns (A–H × 16) become a lamp matrix; tap one to read it from the device.
- **State:** notes read from the device are solid; local edits are dashed until the orange **В ПРИБОР** ("to the device") writes them, after which the app reads back and fills the lamps.
- **Files:** drop a `.mid` anywhere on the roll; its tracks land as dashed notes, assigned by channel. Export via share sheet as `.mid` or raw `.syx`.

```
iPad / Mac
┌ A01 ▾  16 ▸ 64 steps          ⌂ C-minor      [ В ПРИБОР ] ┐
│ C4 │    ▬▬•      ┄┄┄┄           ▬▬                         │
│ G3 │ ▬▬     ▬▬            ▬▬•        ▬▬                    │
│ C3 │▬▬▬▬        ▬▬▬▬   ◇▬▬                                 │
│    │1   .   .   .   2   .   .   .   3   .   .   .   4      │
├───────────────────────────────────────────────────────────┤
│ NOTE  VEL  LEN  MICRO COND RTRG  ·    ·                    │
└───────────────────────────────────────────────────────────┘
iPhone (step view by default; pinch in for roll)
┌──────────────────────┐
│ 03  A01 ▾   [В ПРИБОР]│
│ ■ □ □ □ ■ □ □ ■      │
│ □ □ ■ □ ■ □ □ □      │
│ ▬▬•  ┄┄   ▬▬  (roll) │
│ NOTE VEL LEN COND ›  │
│ ЗВУК НОТЫ ЛЕНТА СЭМ АРХ│
└──────────────────────┘
```
**Gestures:** tap adds, drag moves, drag the right edge for length, two-finger vertical drag for velocity, long-press for a radial rotary (conditions, retrig, micro timing), Pencil draws.

**Hidden:** micro timing, retrigs, conditions (long-press); rows outside the track's scale fold away.

### (c) АРХИВ — the card catalogue

**Dominant visualization:** a sound map, like an analyzer display: x = percussive → sustained, y = dark → bright. Every preset is drawn as its **паспорт** ("passport"): a Lissajous figure from its operator ratios, edged with its envelope silhouette. Similar sounds cluster. Selecting one opens a typed card (SF Mono name, bank·slot, machine glyph, completeness ring for how much of the sound is known) with its **оттиск** ("imprint"), a 2-second audio print captured over USB that plays even without the device.

**Import/export:** drop a `.syx` bank or preset, or a `.dn2arc` app archive, and the cards land in a dashed "входящие" (inbox) drawer. Orange **В ПРИБОР** sends the card to a track or +Drive slot. Export via share sheet.

```
iPad / Mac
┌ +Drive A–H ▾  проект ▾  входящие ┄3┄       [ В ПРИБОР ] ┐
│ ярко │   ∞     ⌘ ◎                ∞                    │
│      │ ◎    ∞ ∞        ◎ ∞    ◎                        │
│ тускло│ ∞ ◎      ∞  ◎        ∞      ┌ KICK_SHARP ─────┐ │
│      └──────────────────────────────│ ◉ FM DRUM  A·014│ │
│       удар                 тянется  │ ∿∿ ◔ 70%        │ │
└──────────────────────────────────────────────────────────┘
iPhone
┌──────────────────────┐
│ АРХИВ  A ▾  ┄3┄      │
│  ∞  ◎   ∞     ◎      │
│    ◎  ∞   ◎  ∞       │
│ ┌ KICK_SHARP  A·014 ┐│
│ │ ∿∿  ◔ 70%  ▶ оттиск│
│ [     В ПРИБОР     ] │
└──────────────────────┘
```
**Gestures:** pan and pinch the map; tap a dot to hear its imprint; drag a card onto a rail track to load it; swipe a card up to favourite it.

**Hidden:** folders, tag editor, list view. Search is one field.

### (d) ЛЕНТА — the tape deck

**Dominant visualization:** a wide waveform strip moving past a fixed centre playhead (the tape moves, the head stays), under two damped Elektronika VU needles and a 4-digit mechanical bar counter. A source rotary mirrors the device's USB OUT options (`MAIN · ДОРОЖКА n · 2×МОНО · EXT`); since that is set on the device, a mismatch with channel activity draws the switch dashed with a pictogram of the menu path. Recording can arm on MIDI Start, so takes begin exactly on bar 1.

```
iPad / Mac
┌  ◜VU L◝  ◜VU R◝     0 0 1 7     ИСТОЧНИК ⟲ MAIN          ┐
│ ────────────────────────│────────────────────────────── │
│ ▁▃▆█▆▃▁▃▆▇▆▃▁▁▃▅█▅▃▁▃▆│▆▃▁▃▆▇▆▃▁                         │
│ ────────────────────────│────────────────────────────── │
│ дубли: ▭ 14:02 A01  ▭ 14:05 A01  ▭ 14:09 B03             │
│             ◀◀   ▶   ■   ⟳       [ ● ЗАПИСЬ ]             │
└───────────────────────────────────────────────────────────┘
iPhone
┌──────────────────────┐
│ ◜L◝ ◜R◝   0017  MAIN │
│ ▁▃▆█▆▃│▃▆▇▆▃▁        │
│ ▭14:02 ▭14:05 ▭14:09 │
│ [    ● ЗАПИСЬ      ] │
└──────────────────────┘
```
**Gestures:** drag the tape to scrub (soft haptic per beat); pinch to zoom; two-finger drag selects a region, flick it up to send it to СЭМПЛЕР; long-press a take to export `.wav`. Playback goes to local speakers, or into the Digitone over USB IN when the output toggle shows the device glyph.

**Hidden:** sample rate and bit depth (fixed 48 kHz/24-bit), file names (time + pattern).

### (e) СЭМПЛЕР — the ДН-С virtual machine

**Dominant visualization:** the plate, a waveform cut by vertical razor lines, over 16 pads mirroring the 16 trig keys. Across the top, the routing ring `Digitone track 09 (MIDI) → USB → ДН-С → USB IN → MAIN` lights segment by segment as data passes; the plug glyph means "runs outside the device".

**Автосэмпл (auto-sampling):** pick a track and note range; the app plays the notes over MIDI, records the track isolated on USB OUT, then trims, normalises and maps. A staircase of waveforms fills in note by note. Afterwards the Digitone's MIDI track and its 8 assignable CC knobs play and tweak ДН-С, with audio coming out of the Digitone's own outputs.

```
iPad / Mac
┌ ДОРОЖКА 09 ⇢ USB ⇢ ДН-С ⇢ USB IN ⇢ MAIN   ⏱ 6 мс         ┐
│ ▁▃▆█▆▃▁│▃▆▇▆▃▁│▁▃▅█▅▃▁│▃▆▆▃▁│▁▃▆▇▆▃▁                     │
│ ┌──┐┌──┐┌──┐┌──┐┌──┐┌──┐┌──┐┌──┐                           │
│ │01││02││03││04││05││06││07││08│  … 16                     │
│ └──┘└──┘└──┘└──┘└──┘└──┘└──┘└──┘                           │
│ START LEN  PTCH  ATK  REL  LOOP  FLTR  LVL  [ ● СЭМПЛ ]    │
└───────────────────────────────────────────────────────────┘
iPhone
┌──────────────────────┐
│ 09⇢ДН-С⇢MAIN  ⏱6мс  │
│ ▁▃▆█│▃▆▇│▁▃▅█│▃▆   │
│ ▢▢▢▢ ▢▢▢▢           │
│ ▢▢▢▢ ▢▢▢▢           │
│ [      ● СЭМПЛ     ] │
└──────────────────────┘
```
**Gestures:** swipe down across the waveform to cut; drag a razor to move it; tap a pad to audition, drag onto another to swap; hold the orange key to sample the current source.

**Hidden:** MIDI channel binding (learned from the first incoming note), latency compensation (only the ⏱ needle), root-key detection.

### (f) СВЯЗЬ — the mimic diagram

**Dominant visualization:** a power-plant мнемосхема. The Digitone is a riveted nameplate block (`DIGITONE II · OS 1.12 · build`) whose ports (MIDI, USB OUT L/R, USB IN L/R) are wired to the app. Dots flow along wires when data passes; audio wires carry mini bar meters; dead wires are dashed; a port in the wrong mode is hollow, with the device menu path as a pictogram. Orange **ПРОБА** runs the петля (loop test): send a note, hear it on USB OUT, measure the round trip. When the loop closes, every lamp turns solid green.

```
iPad / Mac (pop-down panel)
┌──────────────────────────────────────────────────────────┐
│ ┌DIGITONE II┐  MIDI ●━━•━━•━━▶ ┌ПУЛЬТ┐                     │
│ │ OS 1.12   │  MIDI ◀━━•━━━━━━● │     │                     │
│ │ ⊙ ⊙ ⊙ ⊙   │  USB OUT ▮▮▯ ━━━▶ │     │   ⏱ 6 мс           │
│ └───────────┘  USB IN  ◀┄┄┄┄┄┄ └─────┘   [ ПРОБА ]        │
└──────────────────────────────────────────────────────────┘
iPhone (sheet)
┌──────────────────────┐
│ ┌DN II 1.12┐         │
│ MIDI ⇄ ●  USB▶ ▮▮▯  │
│ USB◀ ┄┄ ◌   ⏱ 6 мс  │
│ [       ПРОБА      ] │
└──────────────────────┘
```
**Gestures:** tap a wire to see its port picker (only when more than one port is available).

**Hidden:** port lists (when auto-detection works); SysEx hex and logs (long-press the nameplate for the "служебный" service drawer). UI sound and haptic toggles sit at the panel's foot; there is no settings screen.

## 5. Visual language

**Light is primary.** Braun appliances, Elektronika cases, chart paper and lab instruments are dark ink on warm white. Light mode also separates the app from every black DAW. A dark theme, **ночная смена** ("night shift"), keeps the same semantics for dark studios.

| Token | Light | Dark | Use |
|---|---|---|---|
| корпус (body) | `#ECE8DE` | `#1C1B19` | window background |
| панель (panel) | `#F7F4ED` | `#272623` | instrument faces, keys |
| графит (ink) | `#1E1E1C` | `#E9E5DA` | traces, needles, text |
| шелкография (silk) | `#6F6A61` | `#9C978B` | labels, ticks |
| сетка (grid) | `#D3CDBF` | `#3A3833` | hairlines |
| оранжевый (orange) | `#E5531A` | `#FF6A2B` | the one action |
| лампа-зелёная (green lamp) | `#3E9A55` | `#5CC274` | heard / alive |
| лампа-красная (red lamp) | `#C8372B` | `#E4574A` | clip, error, feedback interlock |

**Machine colours** (track stripe and glyph only, never a fill):
- FM TONE `#3D5C7C` (steel blue)
- FM DRUM `#A3493B` (brick)
- WAVETONE `#6E7A3A` (olive)
- SWARMER `#B58A2C` (ochre)
- MIDI `#6A5C7A` (slate violet)
- App virtual machines `#2E7C78` (teal)

Colour encodes machine, not track number, so 16 tracks never become a rainbow.

**Type:** system fonts only.
- Silk-screen labels: SF Pro Condensed Semibold, 11 pt, all caps, +8% tracking.
- Body: SF Pro Text 13.
- Values: SF Mono Medium 15, tabular figures.
- Mode selector: SF Pro Condensed 17 (caps).
- Counters and tempo: SF Mono 34.
- Tape counter: SF Mono 64.
- Card names: SF Mono 15, the typed-card look.

**Shape:**
- 8 pt grid.
- Keys use a 4 pt radius; small chips use 2 pt.
- Circles are only for knobs, operators and lamps.
- Strokes: hairlines 1 pt, traces 1.5 pt, the active trace 2.5 pt, dashes 4/3.
- No shadows or gradients, except a 1 px inner bevel on keys and the needle's tip.

**Icons:** drawn glyphs in a GOST pictogram spirit. ◎ FM TONE, ◉ FM DRUM, ∿ WAVETONE, ⁘ SWARMER, DIN-circle MIDI, ⊸ plug for virtual machines. SF Symbols are used only for share, transport and search.

**Motion:** needles follow meter ballistics (critically damped, 300 ms VU integration); the mode switch snaps in 120 ms; hardware CC renders within one frame. Nothing is decorative except the one-time lamp warm-up.

**Haptics:** selection tick per quantised detent (ratio, algorithm, mode); rigid tap on the orange key; soft tick per beat while scrubbing; Force Touch detents on Mac.

**UI sounds:** recorded Soviet toggle clicks for mode changes, a tape-deck clunk for ● ЗАПИСЬ. Local output only, never into USB IN; on at −24 dB, switchable in СВЯЗЬ.

## 6. Beyond the brief

| # | Feature | Real capability used | Impact | Effort |
|---|---|---|---|---|
| 1 | **Петля** (loop test): one key sends a note and listens for it, giving latency calibration and routing proof | USB MIDI + USB OUT | 4 | 2 |
| 2 | **Оттиск** (imprint): batch-capture a 2-second print of every preset and draw its spectral passport, giving an audio-browsable library offline | preset SysEx + MIDI note + USB OUT track isolation | 5 | 4 |
| 3 | **Разбор** (stems): loop a pattern via MIDI Start and record each track isolated, or 2 tracks per pass in 2×МОНО (8 passes), to get 16 stems | USB OUT per-track routing, MIDI transport | 5 | 3 |
| 4 | **Самописец** (chart recorder): record hardware knob moves as curves over the pattern, then bake them into parameter locks | incoming CC/NRPN, pattern write | 4 | 3 |
| 5 | **АНС-холст** (ANS canvas): draw a spectrogram with Pencil; the app resynthesizes it and plays it through the Digitone, triggered by a MIDI track | MIDI machine track, USB IN | 5 | 4 |
| 6 | **Морфинг**: drag between two passports to interpolate every *known* parameter over NRPN; unknown parameters stay dashed and untouched | NRPN hi-res send | 4 | 3 |
| 7 | **Вставка** (insert): re-amp an isolated pre-FX track through app FX (tape echo, grain freeze) and return it on USB IN. A red interlock lamp blocks the MAIN→MAIN feedback loop | USB OUT track + USB IN | 4 | 3 |
| 8 | **Анализатор**: live spectrum under the FM diagram with harmonic markers at each operator ratio, so you see what ratio 3.5 does | USB OUT track isolation | 3 | 2 |
| 9 | **Ротор**: Euclidean editor drawn as concentric phase rings, one per track, showing polymeters at a glance; written back as trigs | pattern dump read/write | 3 | 3 |
| 10 | **Паспорт** (passport): export a sound as a printable A5 spec sheet (diagram, envelope, Lissajous, .syx QR) for forums | preset SysEx + rendering | 2 | 2 |
| 11 | **Снимок проекта** (project snapshot): before any write, the app silently dumps the target slot, so a single undo can restore it | SysEx dump receive/send | 5 | 2 |

## 7. Roadmap fit

The ЗВУК grammar is fixed: tracks, machine, pages (SYN/FLTR/AMP/FX/MOD), A–H strip, one dominant instrument per page. A new engine is just another **machine**, with an origin mark:

| Origin | Glyph | Audio path |
|---|---|---|
| Internal (Elektron) | none | inside the device |
| Virtual (app) | ⊸ plug, teal | Digitone MIDI track → app → USB IN → MAIN |
| Custom firmware (speculative) | ⌗ chip, teal | inside the device; loop wire disappears |

Each virtual machine replaces only the SYN page instrument:
- ДН-С sampler: the plate.
- ДН-Г granular: a grain cloud floating over the waveform. Density is the dot count; spray is the scatter.
- ДН-Сп spectral: the ANS canvas.
- ДН-А additive: 32 vertical harmonic bars, organ drawbars drawn as needles.
- ДН-В subtractive: oscillator scope plus the same frequency-response plot as FLTR.

Each machine publishes an 8-knob contract (A–H) that maps onto the Digitone MIDI machine's assignable CC knobs. As a result, the hardware encoders play virtual engines exactly as they play internal ones. If custom firmware ever ships, the same machine definition swaps its transport from "USB loop" to "native", and the screens do not change.

## 8. Simplicity ledger

**Removed:**
- The sidebar.
- 0–127 slider lists.
- Every disclaimer paragraph; line style and lamps replace them.
- The "Применить параметры" (apply parameters) button. Edits are live; only bulk actions use orange.
- The snapshot vs preset vocabulary. There is one noun, **звук** (sound), with a completeness ring.
- The settings screen.
- The file browser. Files arrive by drag-drop and leave by the share sheet.
- Onboarding carousels. The mimic diagram is the onboarding.
- Tooltips.

**Hidden until asked:**
- MIDI channel and ports (auto-detected; in СВЯЗЬ).
- CC vs NRPN (hi-res is used automatically).
- SysEx hex and logs (the служебный drawer).
- Raw values (shown only during a drag).
- Micro timing, retrig and trig conditions (long-press radial).
- Numeric entry (long-press).
- Sample rate, bit depth and file names (fixed or automatic).
- Latency compensation (the ⏱ needle only).
- Folders and tags (a single search field).

## 9. Top 5 risks

1. **A sea of dashes.** The device cannot report full sound state, so a fresh session may look half-drawn and "broken". Mitigations: auto-read the kit dump on track change; make dashed traces beautiful rather than apologetic; a "прочитать" (read) pull-down gesture on every instrument.
2. **USB audio routing lives on the device.** The app cannot set USB OUT or INT TO MAIN, so the sampler, ЛЕНТА and the inserts depend on a manual hardware setting. Mitigations: detect routing by channel activity and the loop test, and show the menu path as a pictogram.
3. **Visual honesty vs visual delight.** Drawing FM diagrams, filter responses and LFO wires needs exact parameter maps for four machines and multiple FLTR types. A wrong curve is a lie dressed as a picture. Computed previews must stay dashed until audio confirms them.
4. **Writing to the device is reverse-engineered.** Pattern and preset formats are confirmed only for build 0049, and OS 1.12 may differ. One corrupted project kills trust. Mitigations: automatic pre-write snapshot (feature 11), read-back verification, refusing unknown builds.
5. **Style risk.** The warm-white Soviet panel can tip into kitsch skeuomorphism, and Cyrillic silk-screen may alienate non-Russian users. Mitigations: flat drawing, strict colour budget, hardware labels kept in Latin, full localization of the Russian words. Separately, the round-trip latency of virtual machines (about 6–15 ms) may feel loose for drums.

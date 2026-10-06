# DN·KIT: «Игрушечный пульт»

**Metaphor:** every screen is one toy drawing (planets, a music-box disc, a badge board, tape reels, a sliced loaf), and the drawing is the instrument. Its colored parts are the Digitone's eight knobs A–H.

Lens: Teenage Engineering (OP-1 engine screens, OP-XY encoder colors, EP-133 pads) crossed with Soviet consumer electronics: cream panels, rotary band switches, enamel pins (значки).

---

## 1. Design principles

1. **One drawing per screen, and you touch the drawing.** If a value can't be dragged inside the illustration, it doesn't belong on that screen.
2. **Color means a hand, never a category.** Blue, green, graphite and orange always mean knobs A/E, B/F, C/G, D/H.
3. **Line style tells you how true a value is.** Dashed is unknown, outline is sent, solid is heard from the device.
4. **Numbers only appear under a finger.** At rest you see shapes. Touching brings up a magnifier («лупа») with the value.
5. **The drawing does what the sound does.** Moons orbit while notes play, the filter sun rises with its envelope, reels turn at tape speed.
6. **The hardware is the main controller.** A turned Digitone knob visibly moves its colored part in the app within 50 ms.

---

## 2. Information architecture

Five modes plus one status socket. Each mode is a drawn key, like the OP-1 mode keys.

| Key | Mode | Drawing |
|---|---|---|
| ◎ | **ЗВУК** | Machine illustration (orbit, drum, swarm…) |
| ⠿ | **НОТЫ** | Music-box disc ↔ unrolled piano roll |
| ◍ | **ПОЛКА** | Felt board of sound badges |
| ◫ | **ПЛЁНКА** | Two reels + tape |
| ✂ | **СЭМПЛ** | Waveform loaf + 16 pads |
| ⏚ | *розетка* (status) | Phone ↔ cable ↔ Digitone |

**The frame shared by every screen:**
- **Top panel:** socket glyph, 16 track squares (the trig keys), tempo, ▶ and ●.
- **Bottom:** the encoder bar, A–H in two rows of four as on the hardware.
- The selected track is global and stays put when you switch modes.

**Navigation:**
- **iPad and Mac (landscape):** a column of mode keys on the left; the drawing fills the rest.
- **Mac keyboard:** ⌘1–5 switch modes, `[` `]` change track, Space plays, R records, ⌥-drag gives fine values, scrolling over a part turns its knob.
- **iPhone (portrait):** a row of the five drawn keys at the bottom. Above it sit only four encoders (A–D); flick the bar up for E–H, like a TE shift key.
- **iPhone (landscape):** the current mode becomes a full-screen playing surface (keyboard, long roll or 16 pads).

**From launch to a sound in under 30 s:**
1. **0 s:** the app opens on ЗВУК, with a dangling cable in the socket that sways as the device moves.
2. **~2 s:** it finds the Digitone II ports and identifies the device over SysEx. The plug clicks in (haptic) and the Digitone outline lights up with "OS 1.10D" on its label plate.
3. **~4 s:** it reads the pattern+kit dump automatically, so track names and steps appear.
4. **~5 s:** the bottom edge of the drawing is a one-octave keyboard («земля»). One tap plays a note on the selected track, and the sound comes from the Digitone.
5. **No device:** СЭМПЛ opens with a bundled kit, so you hear something in about 3 s.

---

## 3. Screens

### (a) ЗВУК: sound editing

**Dominant visualization: «Орбита» (FM TONE).**
- **Operators:** carriers are suns on the ground line; modulators are moons on strings, with arrows showing the algorithm.
- **Ratio** is a moon's orbit speed, with detents at legal ratios.
- **HARM** grows teeth on a moon until it becomes a gear.
- **DTUN** splits the sun into two offset discs.
- **FDBK** is a spin-trail around its operator.
- **MIX** is a seesaw between outputs X and Y.
- **ALGO** is an 8-position constellation dial. Moons fly to their new wiring on change, so the algorithm teaches itself.

**Other machines on the same SYN page:**
- **FM DRUM:** a drum skin with a ski-jump pitch sweep.
- **WAVETONE:** two blending oscilloscope ribbons.
- **SWARMER:** a firefly swarm. Detune spreads it; animation makes it drift.

**Other pages, one shape each:**
- **SYN envelope pages:** each operator becomes a hill with ATK/DEC/END/LEV handles.
- **FLTR:** a horizon.
  - Cutoff is a sun you drag along it, and resonance is a mountain under the sun.
  - The filter envelope is the sun's rise on each trig.
  - The horizon takes the machine's shape: MULTI-MODE morphs LP→BP→HP, COMB± is a picket fence, EQUALIZER is two hills.
- **AMP:** one bold ADSR line with four colored handles; PAN tilts the baseline.
- **FX:** bit and sample-rate reduction turn a sine into stairs, overdrive squashes it, and DELAY/REVERB/CHORUS sends are three filling ladles.
- **MOD:** each LFO is a ball riding its waveform (speed and wave height). A string ties it to a live, wobbling thumbnail of its destination.

**Mapping A–H:**
- Every grabbable part wears a 6 pt pin in its knob's color with the letter.
- A–D (top row) get solid pins, E–H (bottom row) get ring pins.
- FM TONE SYN1: A = ALGO dial, B = sun (C ratio), C = moon A, D = moons B, E = gear teeth, F = double sun, G = spin trail, H = seesaw.
- A hardware knob turn ripples its part. Dragging a part sends CC, or NRPN in fine mode.

**Value truth without text:**

| Glyph | Meaning |
|---|---|
| dashed outline + hatch, at the default position | unknown, never received |
| outline only | sent by the app, not echoed |
| solid fill | heard from the device (knob CC/NRPN or dump) |

- A row of eight dots on the encoder bar (`●●◌○●●◌●`) summarizes the page.
- **«Забыть»:** shake the iPhone or press ⌘⌫ to fade every part back to dashed. This is the honest reset after changing sound on the hardware.
- Modulation animates only when all of its inputs are solid.

```
iPad / Mac
┌ ⏚● ▢▢▢▢▣▢▢▢▢▢▢▢▢▢▢▢  T5 KICK_SHARP  ◉FM TONE    120.0  ▶ ● ┐
│◎│ [SYN1] SYN2 SYN3 SYN4 · FLTR · AMP · FX · MOD           │
│⠿│                (B2)◌ - - ╮          algo ·· ·[4]· ··     │
│◍│        (A)⚙ ──────────→ ☀☀ C ←── (B1)◐       (A●)        │
│◫│          ↻G○              ⚖H○                            │
│✂│ ▔▔▔▔▔▔▔▔▔▔▔▔▔▔ земля = keyboard ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔ │
│ │ A●ALGO B●C C●A D●B   E○HARM F○DTUN G○FDBK H○MIX  ●●◌○●●◌● │
└─────────────────────────────────────────────────────────────┘
iPhone
┌ ⏚●   T5 ◉FM TONE  120 ┐
│ SYN1 ‹ FLTR AMP FX ›  │
│      ◌B2              │
│  ⚙A ──→ ☀☀C ←── ◐B1   │
│   ↻        ⚖          │
│ ▔▔▔▔ keyboard ▔▔▔▔▔▔▔ │
│ A●  B●  C●  D●   ⇡E–H │
│ ◎   ⠿   ◍   ◫   ✂     │
└───────────────────────┘
```

**Gestures:**
- Drag a part to change its value.
- Two-finger rotate on the constellation steps through algorithms.
- Long-press shows the magnifier with the hardware unit (e.g. `1.50`), or `0–127` plus the state glyph when the unit is unknown.
- Double-tap resets to the default.

**Hidden:** full parameter names (only the 4-letter hardware labels remain), and A/B variants (they live in ПОЛКА as two badges).

### (b) НОТЫ: notes, piano roll, patterns

**Dominant visualization: a music box («шарманка») you zoom through.**
- **Zoomed out:** a **disc** with 16 concentric rings, one per track. Notes are pins on the rings, and a needle sweeps around during playback.
- **Pinch into a ring** to unroll it into a **piano roll** for that track. Under it, a 16-key step row mirrors the trig keys and shows the page.

**How a note looks:**
- Velocity is the pin's thickness.
- A trig condition is a pie ring on the pin (½ filled = 50%).
- Micro-timing is a pin nudged off-grid, with a shadow tick left on the grid.
- Parameter locks are colored pins on the note (blue = knob A locked).

**Gestures:**
- Tap to add a note, drag to move it, drag its right edge to set length.
- A two-finger vertical drag changes velocity.
- Hold a note and turn any knob, on screen or on the hardware, to set a p-lock. It is the hardware's own hold-trig move.

**Patterns:**
- The **slot board** shows 8 banks × 16 tiny discs. An unread slot is a dashed circle; tap it to read it over SysEx, and its thumbnail "develops".
- **Write-back:** hold a slot for 1 s while a ring fills. The current contents are read and archived first, and the old disc slides into the «архив» tray.
- Until hardware write-back is verified, the app plays the roll itself as MIDI to the Digitone tracks. The needle's icon (device outline or phone) shows who is playing.

**MIDI files:** drop a `.mid` onto the disc (Mac/iPad) or use Files/Share (iPhone). Its tracks float as ghost rings that you drag onto Digitone rings. Drag the disc out to export a `.mid`.

```
iPad / Mac                                   iPhone
┌ ⏚● ▢▢▣▢… T3  A07  120 ▶ ● ──────────────┐  ┌ ⏚● T3 A07 ▶ ┐
│◎│  ╭─ disc ─╮ │ C4 ▬▬   ▬      ▬▬▬       │  │ C4 ▬▬  ▬   │
│⠿│  │ ◯◯◯◯◉ │ │ A3    ▬◔  ▬               │  │ A3   ▬◔    │
│◍│  │ ◯ ╲ ◯ │ │ F3 ▬●B      ▬  ▬          │  │ F3 ▬●  ▬   │
│◫│  ╰needle─╯ │ ────────────────────────  │  │ ▢▣▢▢▢▣▢▢…  │
│✂│  A▢▢▢… H   │ ▢▣▢▢ ▢▣▢▢ ▢▢▣▢ ▢▣▢▢ steps │  │ A● B● C● D●│
│ │ slot board │ A● B● C● D●  E○ F○ G○ H○  │  │ ◎ ⠿ ◍ ◫ ✂  │
└───────────────────────────────────────────┘  └────────────┘
```

**Hidden:** song mode, perform kit, arpeggiator and scales are read-only glyphs in v1. Tracks are renamed on the device.

### (c) ПОЛКА: presets and banks

**Dominant visualization: a felt badge board («планшет со значками»).**
- **Emblem:** every sound is a round enamel badge whose emblem is a **radial spectrogram of its own audio preview** (angle = time, radius = frequency).
- **Previews** are captured over USB the first time a sound plays, so the badge is honest even when parameters are unknown.
- **Rim shape** gives the machine: smooth for FM TONE, notched for FM DRUM, wavy for WAVETONE, dotted for SWARMER, a plug for MIDI.
- A badge with no preview yet is blank with a dashed rim.

**Boards:** +Drive has 8 boards of 16×16 (2048 sounds); the project pool is a smaller board of 128.

**Gestures:**
- Tap a badge to play its preview.
- Drag a badge onto the Digitone outline or a track square to send its `.syx` to the chosen slot.
- Lasso several badges, then drag them out (Mac) or Share (iOS).
- Tap to favorite; the rim turns orange.

**Import / export:** drop a `.syx` to add badges; a bank file arrives as a whole board. «Коробка» is the app archive: a zip of `.syx`, preview `.wav` and metadata.

**Filtering:** tap a rim silhouette to filter by machine. Text search waits behind pull-down (iOS) or ⌘F (Mac).

```
iPad / Mac                                   iPhone
┌ ⏚●  +DRIVE [A] B C D E F G H · POOL ─────┐  ┌ ⏚● [A]B C D… ┐
│◎│ ◉ ◉ ◌ ◉ ◉ ◉ ◌ ◉ ◉ ◉ ◉ ◌ ◉ ◉ ◉ ◉        │  │ ◉ ◉ ◌ ◉ ◉   │
│⠿│ ◉ ◉ ◉ ◉ ◌ ◉ ◉ ◉ ◉ ◌ ◉ ◉ ◉ ◉ ◌ ◉        │  │ ◉ ◌ ◉ ◉ ◉   │
│◍│ ◉ ◌ ◉ ◉ ◉ ◉ ◉ ◌ ◉ ◉ ◉ ◉ ◉ ◉ ◉ ◉        │  │ ◉ ◉ ◉ ◌ ◉   │
│◫│ filter: ◯ ✲ 〰 ⁘ ⏚     drop .syx here  │  │ ◯ ✲ 〰 ⁘ ⏚  │
│✂│ ╭ big badge + name on rim · ▶ · → T5 ╮ │  │ ◎ ⠿ ◍ ◫ ✂   │
└───────────────────────────────────────────┘  └─────────────┘
```

**Hidden:** tags, categories, file names, dates, and the snapshot/preset distinction (shown only as rim style).

### (d) ПЛЁНКА: audio play and record

**Dominant visualization: two reels** with the waveform printed on the tape between them.
- Recording spins the reels and prints the wave in red.
- Takes are cut tape strips lying on a table underneath.

**Source:** a Soviet **band switch** (MAIN · TRACK · 2×MONO · EXT) mirrors the device's USB OUT setting, which the app can't change remotely. It stays dashed until **Эхолот** confirms it (see §5).

**Output:** the arrow on the cable glyph sends playback to the phone/Mac speaker, or *into* the Digitone over USB IN → MAIN.

**Gestures:**
- Drag the tape to scrub; the reels turn with it. Pinch to zoom.
- Two-finger drag selects a region; flick it up to cut a take.
- Drag a take onto ✂ to send it to the sampler.
- With MIDI clock present, recording arms to the next bar and the tape shows bar ticks.

```
iPad / Mac                                   iPhone
┌ ⏚●  T—  120 ▶ ●REC ──────────────────────┐  ┌ ⏚●   ● 0:12  ┐
│◎│    ◎╲________________________╱◎        │  │  ◎╲_____╱◎    │
│⠿│      ▁▃▇▅▂▁▃▆▇▃▁▂▅▇▆▃  (red = rec)    │  │  ▁▃▇▅▂▃▆▇▃    │
│◍│   [MAIN|TRK|2×M|EXT] ◜band switch◝  ⇄  │  │ (MAIN◜switch◝)│
│◫│ takes: ▭▭  ▭▭▭  ▭                       │  │ ▭▭ ▭▭▭ ▭      │
│✂│ A●gain B●trim C●fade D●pitch           │  │ ◎ ⠿ ◍ ◫ ✂     │
└───────────────────────────────────────────┘  └───────────────┘
```

**Hidden:** format pickers (always 48 kHz/24-bit), file names (takes are named by time and track), and the audio device list.

### (e) СЭМПЛ: the sampler

**Dominant visualization: a loaf** (the waveform) with knife cuts. The slices drop into **16 pads** that mirror the trig keys.
- Drag a cut to move it; tap the loaf to add one.
- The knife's number (4/8/16) sets auto-chop; long-press it to chop on transients.
- Per pad, A–D are START, LEN, PITCH, LEVEL and E–H are FLTR, AMP ENV, LOOP, PAN.

**Фотобудка (auto-sampling the Digitone):**
1. The app plays notes on the selected track over MIDI, across a chosen range, step and velocity layers.
2. It records the isolated track from USB OUT.
3. A contact sheet of frames "develops" as each note is captured.
4. The result is a trimmed, normalized, loop-pointed multisample.

**Played from the Digitone:** set a track to the MIDI machine, and its notes and 8 CC knobs drive the sampler over USB MIDI. Audio returns through USB IN to the Digitone's MAIN outs. The picture shows the loop: the track key lit on the Digitone outline, note dots travelling out along the cable, a wave coming back.

```
iPad / Mac                                   iPhone
┌ ⏚●  T9 ⏚MIDI→СЭМПЛ  120 ▶ ● ─────────────┐  ┌ ⏚● T9→СЭМПЛ ┐
│◎│ ▁▃▇▅▂│▁▃▆▇▃│▁▂▅▇▆▃│▁▃▇▂│ ✂16           │  │ ▁▃▇│▅▂│▁▃▆ ✂ │
│⠿│ ▣ ▢ ▢ ▢  ▢ ▢ ▢ ▢  ▢ ▢ ▢ ▢  ▢ ▢ ▢ ▢     │  │ ▣▢▢▢ ▢▢▢▢   │
│◍│ [DN2 ▢▢▢▢▢▢▢▢▣▢▢▢▢▢▢▢]→notes→ ←wave←   │  │ ▢▢▢▢ ▢▢▢▢   │
│◫│ 📷 Фотобудка: ▭▭▭▭▭▭ C1…C6 ×3 vel        │  │ A● B● C● D● │
│✂│ A●START B●LEN C●PITCH D●LVL  E○…H○      │  │ ◎ ⠿ ◍ ◫ ✂   │
└───────────────────────────────────────────┘  └─────────────┘
```

**Hidden:** voice allocation and zone/key-range editors. Mapping is automatic, one note per frame.

### (f) Розетка: connection and device status

**Dominant visualization:** phone/Mac outline, cable, Digitone outline. The cable has two lanes:
- **MIDI:** a thin dotted lane. Each message is a dot, colored with its knob when it carries a parameter.
- **Audio:** a thick lane showing level in both directions. It is dashed in USB MIDI-only mode.

**The Digitone outline:**
- Its 16 trig keys show channel use. The Auto Channel key (10 on the tested unit) has a ring and flashes when a CC arrives.
- Its label plate shows name, OS and build in mono.

**Checklist:** five toggles drawn like device menu rows (`INPUT FROM USB`, `RECEIVE NOTES`, `RECEIVE CC/NRPN`, `ENCODER DEST INT+EXT`, `PARAM OUTPUT`). Each lights **only on evidence**; for example, the first knob CC lights PARAM OUTPUT.

```
iPad / Mac                                   iPhone
┌──────────────────────────────────────────┐  ┌──────────────┐
│  ▯ iPad ═══ ·•·•·•· MIDI ═══ ▭ DN2 ▢▢▢▢  │  │ ▯ ══·•·══ ▭  │
│         ═══ ▁▃▇▅ AUDIO ═══▶  OS 1.10D    │  │   ▁▃▇ audio  │
│  ◉INPUT ◉NOTES ◉CC/NRPN ◌ENC ◉PARAM      │  │ ◉ ◉ ◉ ◌ ◉    │
│  ch: ▢▢▢▢▢▢▢▢▢◎▢▢▢▢▢▢  (◎ = auto ch 10)  │  │ ▢▢▢▢▢▢▢▢▢◎…  │
└──────────────────────────────────────────┘  └──────────────┘
```

**Hidden:** port lists (long-press the plug), the MIDI log (the cable dots replace it), and channel pickers (the observed channel is adopted automatically).

---

## 4. Visual language

**Canonical theme: light «бумага».** TE bodies and Soviet panels are neutral and pale, the four knob colors read best on paper, and studio work happens in daylight. A dark «ночь» theme follows the system setting for stage use.

| Token | Light | Dark | Use |
|---|---|---|---|
| body | `#ECEBE6` | `#0F0F0F` | background |
| surface | `#F7F6F2` | `#1A1A1A` | drawing plate |
| ink | `#141414` | `#F2F2EE` | lines, type |
| ink-2 | `#6E6E69` | `#8A8A85` | secondary |
| hairline | `#CFCDC6` | `#2C2C2C` | grid |
| hatch | `#B9B7AF` | `#3A3A38` | unknown values |
| **A/E blue** | `#2E5BFF` | `#4C78FF` | knob 1 |
| **B/F green** | `#00B864` | `#22D07A` | knob 2 |
| **C/G graphite** | `#1C1C1C` | `#F2F2EE` | knob 3 (white in dark) |
| **D/H orange** | `#FF5B14` | `#FF6B2C` | knob 4 |
| red | `#FF2D2D` | `#FF4040` | record and clip only |

**Color semantics:** colors belong to knobs only, and red means only "audio is being captured". Tracks are numbers, with the selected one an inverted ink square. Machines differ by **shape**, never by color.

**Type:**

| Use | Font |
|---|---|
| Hardware terms (`SYN`, `FLTR`, `A`) | SF Mono Medium 11, caps, +6% tracking |
| Russian words | SF Pro Text 13 |
| Magnifier values | SF Mono 17 |
| Tempo and big counters | SF Pro Rounded Bold, 34 (iPhone) / 56 (Mac) |

Scale: 10 / 11 / 13 / 17 / 34 / 56. The 10 pt size appears only on badge rims on Mac.

**Shape:** 8 pt grid. Strokes are 1.5 pt for drawings, 3 pt for grabbable parts, and knob pins are 6 pt. Panels have 6 pt corners and pills are fully round. No shadows, gradients or blur.

**Icons:** drawn on a 20 pt grid with 1.5 pt strokes. SF Symbols only for system actions (share, files).

**Motion:**
- Springs: 0.25 s response, 0.8 damping.
- Hardware changes arrive as a wiggle plus a ripple in the knob's color.
- Switching modes folds the drawing like paper (0.3 s).
- Idle animation runs only while notes play.
- Reduce Motion swaps transitions for crossfades and stops orbits.

**Haptics:** 16 detents per range plus a stronger tick at the default. Algorithm changes give a rigid impact, recording a heavy one, slicing a sharp tick per cut. Connecting plays a "plug" success pattern. On Mac, the Force Touch trackpad gives alignment ticks.

**UI sounds:** tiny synthesized clicks on the local speaker or headphones only, **never into the USB IN path**, so they can't leak into the mix. They are silent while recording.

---

## 5. Beyond the brief

| # | Feature | Uses | Impact | Effort |
|---|---|---|---|---|
| 1 | **Эхолот:** pings each track with a short note and listens on USB OUT. That reveals the routing (MAIN, track N, 2×MONO) and the MIDI→audio latency, and sets the band switch. | MIDI notes + USB audio | 4 | 2 |
| 2 | **Фотобудка freeze:** auto-samples any track into a multisample that survives preset changes and plays past the device's polyphony | MIDI + isolated USB track | 5 | 3 |
| 3 | **Призрачная машина:** app engines played from a Digitone MIDI track. Its 8 CC knobs act as A–H, and audio returns via USB IN | MIDI machine + USB IN | 5 | 4 |
| 4 | **Спектральный значок:** a preset's identity drawn from its recorded audio, honest without parameter reads | USB audio | 4 | 2 |
| 5 | **Запоминалка рук:** records hardware knob CC/NRPN as editable drawn curves and replays them in sync | CC/NRPN + clock | 4 | 2 |
| 6 | **Рисованный LFO:** draw any curve and it streams as hi-res NRPN to any parameter, an extra LFO beyond the MOD pages | NRPN | 4 | 2 |
| 7 | **Наклон-морф:** tilt the iPhone to roll a ball between two badges. Known parameters interpolate over NRPN; unknown ones stay put | NRPN + CoreMotion | 3 | 3 |
| 8 | **Сейф:** on connect, quietly reads all 128 pattern slots into a versioned timeline of discs with visual diffs | SysEx pattern dumps | 4 | 3 |
| 9 | **MIDI-сортировщик:** drop any `.mid` and drums, bass and chords are auto-assigned to rings by register and density | MIDI files | 3 | 2 |
| 10 | **Пульт с телефона:** while the Mac app is open, the iPhone becomes its 4-encoder remote | local network | 3 | 3 |
| 11 | **Эвклид-цветок:** euclidean rhythms drawn as polygons on the disc; drag a vertex to change the hit count | app sequencer → MIDI | 3 | 2 |

---

## 6. Roadmap fit: virtual machines and firmware

**The machine contract.** Each machine declares its pages, eight slots A–H per page (range, unit and the drawing element each one grabs), and its audio source. Hardware machines (FM TONE, FM DRUM, WAVETONE, SWARMER) and app machines implement the same contract.

**App machines** live on a Digitone MIDI-machine track.
- Their machine label is drawn in **outline** style (app engine) rather than **solid** (hardware), reusing the honesty line language.
- FLTR, AMP and MOD keep their drawings, implemented in the app.

| Machine | SYN page drawing |
|---|---|
| **SAMPLE** | the loaf |
| **GRAIN** | a snowfall of grains over the waveform (density, size, spray, position) |
| **SPECTRA** | a comb of bars you paint and freeze |
| **ADD** | 64 organ pipes |
| **SUB** | the oscillator wave + the horizon filter |

**If custom firmware ever ships,** a machine simply goes from outline to solid and the cable's audio lane becomes unnecessary. Pages, pins, colors and gestures stay the same.

---

## 7. Simplicity ledger

**Removed:** the sidebar; lists of 0–127 sliders; disclaimer paragraphs (now three line styles); the "Apply parameters" button (edits are live, offline drafts are outlines); port and channel pickers; the MIDI log; confirm dialogs (now hold-to-fill); settings screens; the read-only pattern table; the separate snapshot list (absorbed into badges).

**Hidden, one gesture away:**
- numeric values (long-press)
- text search (pull-down / ⌘F)
- port lists (long-press the plug)
- E–H on iPhone (flick)
- fine NRPN steps (⌥ or a two-finger drag)
- song mode, perform kit, arpeggiator and scales (read-only glyphs in v1)
- the mixer and send matrix (v2)

**Never shown:** sample-rate and bit-depth choices, file names, the snapshot/preset distinction.

---

## 8. Top 5 risks

1. **Metaphors can hide precision.** An orbit is charming, but exact-ratio work needs numbers. *Mitigation:* the magnifier, legal-value detents, and a two-finger "x-ray" hold that shows every value at once.
2. **First screens are mostly dashed.** Until kit-dump parameters are decoded, drawings start as ghosts. *Mitigation:* make the dashed state deliberately beautiful, let the first knob turn fill a part, and prioritize decoding the per-track synth block.
3. **USB audio realities.** The USB OUT source can only be set on the device, virtual-machine round-trip latency is untested, and iPhone USB-C power and hubs may cause trouble. *Mitigation:* Эхолот, latency compensation, and an honest dashed audio lane.
4. **Hardware writes aren't verified** (pattern write-back, preset upload). *Mitigation:* read-and-archive before every write, hold-to-confirm, the Сейф timeline, and the app sequencer as a fallback until writes are proven.
5. **Illustration scope and trade dress.** Bespoke drawings are needed for 4 SYN, 6 FLTR and 5 virtual machines in two layouts, and the reels and knob colors must be an homage rather than a copy of TE or Elektron. *Mitigation:* the machine contract plus a shared set of primitives (sun, moon, hill, horizon, ladle, ball).

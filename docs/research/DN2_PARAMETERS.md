# Digitone II: параметры, страницы и MIDI-адреса

Источник — руководство Elektron Digitone II для OS 1.12 (DOC10093enH): глава 11 (страницы трека), глава 12 (send FX и микшер), 13.4 (MIDI CONFIG), приложения A (машины), C (CC/NRPN) и D (цели LFO). Прибор пользователя работает на OS 1.10D build 0049; совместимость всех адресов и кодирования значений 1.12 с OS 1.10D ещё требует аппаратной проверки.

Данные живут в трёх местах и проверяются друг против друга тестом `HardwareCatalogTests`:

- `Sources/DigitoneCore/CatalogData*.swift` — каталог за контрактом `HardwareCatalog`;
- `docs/research/dn2-parameters.json` — машиночитаемая копия: все строки приложения C с привязкой к id, все параметры каталога, списки целей LFO, факты MIDI CONFIG;
- этот файл — обзор и принятые решения.

## Как читать

- **Ручка** — положение на экране прибора: A–D верхний ряд, E–H нижний (`slot` 0–7).
- **NRPN** — `MSB:LSB`, в коде `MSB × 128 + LSB`. MSB 1 и 3 идут на канал трека, MSB 2 — на FX CONTROL CH.
- **⁺** — тонкое разрешение: значение точнее 7 бит, отправлять NRPN с LSB. Признак ставится там, где руководство показывает дробные значения (HARM, смещения ratio, RATIO FM DRUM, DEP, TIME), и для FREQ фильтра по обычной практике Elektron (не подтверждено руководством).
- **Значения** — как `HardwareCatalog.display` показывает грубое значение 0–127.
- **По умолч.** — ★ означает, что значение названо в руководстве. Без звезды стоит нейтральное: 0, середина для биполярных, первая опция; уровни и громкости — 100, фильтры и ширины открыты (127). Это ориентир для кнопки «сброс», а не заводской пресет.
- В каталог попадают только ручки с CC или NRPN. Пустые ячейки «·» — ручки без MIDI-адреса или пустые места на экране.

## Страницы по машинам

| Машина | Страницы трека |
|---|---|
| FM TONE | TRIG · SYN1 · SYN2 · SYN3 · SYN4 · FLTR1 · FLTR2 · AMP · FX · MOD1 · MOD2 · MOD3 · EUCLID · TRACK |
| FM DRUM | TRIG · SYN1 · SYN2 · SYN3 · SYN4 · FLTR1 · FLTR2 · AMP · FX · MOD1 · MOD2 · MOD3 · EUCLID · TRACK |
| WAVETONE | TRIG · SYN1 · SYN2 · SYN3 · FLTR1 · FLTR2 · AMP · FX · MOD1 · MOD2 · MOD3 · EUCLID · TRACK |
| SWARMER | TRIG · SYN1 · FLTR1 · FLTR2 · AMP · FX · MOD1 · MOD2 · MOD3 · EUCLID · TRACK |
| MIDI | TRIG · SYN1 · FLTR1 · AMP · MOD1 · MOD2 · EUCLID · TRACK |
| глобальные (FX CONTROL CH) | DELAY · REVERB · CHORUS · COMP · MIXER · INPUT R |

У MIDI-машины нет FX и LFO 3; FLTR 2 и AMP 2 (SEL1–16) не имеют MIDI-адресов, поэтому в каталоге их нет. Страница TRACK не существует на приборе: на ней собраны параметры трека без собственной страницы.

## Ручки одним взглядом

| Страница | A | B | C | D | E | F | G | H |
|---|---|---|---|---|---|---|---|---|
| TRIG | NOTE | VEL | LEN | · | LFO.T | FLT.T | PTIM | PORT |
| FM TONE SYN1 | ALGO | RAT C | RAT A | RAT B | HARM | DTUN | FDBK | MIX |
| FM TONE SYN2 | ATK A | DEC A | END A | LEV A | ATK B | DEC B | END B | LEV B |
| FM TONE SYN3 | ADEL | ATRG | ARST | PHRT | BDEL | BTRG | BRST | · |
| FM TONE SYN4 | OFS C | OFS A | OFS B1 | OFS B2 | · | KEY A | KEY B1 | KEY B2 |
| FM DRUM SYN1 | TUNE | STIM | SDEP | ALGO | OP.C | OP.AB | FDBK | FOLD |
| FM DRUM SYN2 | RAT A | DEC A | END A | MOD A | RAT B | DEC B | END B | MOD B |
| FM DRUM SYN3 | HOLD | DEC | PH.C | LEV | · | · | NRST | NRM |
| FM DRUM SYN4 | NHLD | NDEC | TRAN | TLEV | BASE | WDTH | GRAN | NLEV |
| WAVETONE SYN1 | TUN1 | WAV1 | PD1 | LEV1 | TUN2 | WAV2 | PD2 | LEV2 |
| WAVETONE SYN2 | OFS1 | TBL1 | MOD | RSET | OFS2 | TBL2 | · | DRIF |
| WAVETONE SYN3 | ATK | HOLD | DEC | NLEV | BASE | WDTH | TYPE | CHAR |
| SWARMER SYN1 | TUNE | SWRM | DET | MIX | M.OCT | MAIN | ANIM | N.MOD |
| FLTR1 | ATK | DEC | SUS | REL | FREQ | F | G | ENV |
| FLTR2 | DEL | · | · | KEY.T | BASE | WDTH | · | RSET |
| AMP | ATK | DEC | SUS | REL | RSET | MODE | PAN | VOL |
| FX | BR | OVER | SRR | SR.RT | DEL | REV | CHR | OD.RT |
| MOD1 (и MOD2, MOD3) | SPD | MULT | FADE | DEST | WAVE | SPH | MODE | DEP |
| EUCLID | PL1 | PL2 | · | EUC | RO1 | RO2 | TRO | OP |
| TRACK | MUTE | LEV | PMUT | HOLD | · | · | · | · |
| MIDI TRIG | NOTE | VEL | LEN | · | LFO.T | · | · | · |
| MIDI SYN1 | CHAN | BANK | SBNK | PROG | PB | AT | MW | BC |
| MIDI FLTR1 | VAL1 | VAL2 | VAL3 | VAL4 | VAL5 | VAL6 | VAL7 | VAL8 |
| MIDI AMP | VAL9 | VAL10 | VAL11 | VAL12 | VAL13 | VAL14 | VAL15 | VAL16 |
| MIDI TRACK | MUTE | · | PMUT | · | · | · | · | · |
| DELAY | TIME | X | WID | FDBK | HPF | LPF | VOL | REV |
| REVERB | PRE | DEC | FREQ | GAIN | HPF | LPF | VOL | · |
| CHORUS | DPTH | SPD | HPF | WDTH | VOL | · | DEL | REV |
| COMP | THR | ATK | REL | MUP | RAT | SCS | SCF | MIX |
| MIXER | IN | DUAL | BAL | MOVD | DEL | REV | CHR | VOL |
| INPUT R | IN R | · | PAN | · | DEL | REV | CHR | · |

## Решения по раскладке

- **TRIG.** Одна `DNPage` на две страницы прибора. Ручки страницы 1 стоят на своих местах; PROB, FILL и COND без адреса. PTIM и PORT со страницы 2 занимают G и H — там же они стоят и на приборе. Ретриги (RTRG, VFAD, LEN, RATE) по MIDI недоступны.
- **AMP.** Раскладка снята со скриншота в режиме ADSR: ATK, DEC, SUS, REL / RSET, MODE, PAN, VOL. HOLD прибор показывает только в режиме AHD, девятой ручки нет, поэтому HOLD (`amp.hold`) живёт на TRACK, ручка D.
- **AMP SUS.** В C.5 у Sustain Level напечатан CC 86, как у Decay Time. Каталог хранит для SUS только NRPN 1:33 (`cc = nil`), чтобы приложение не крутило Decay вместо Sustain. Вероятно, это опечатка вместо свободного CC 87, но без проверки на приборе CC не назначен.
- **TRACK.** MUTE (C.1), LEV — ручка LEVEL трека (C.1), PMUT — Pattern Mute (C.12), HOLD (см. выше). У MIDI-трека только MUTE и PMUT.
- **Громкости LEVEL/DATA.** На страницах send FX и микшера громкость крутится отдельной ручкой LEVEL/DATA. Каталог кладёт её на свободную ручку: DELAY G, REVERB G, CHORUS E. Эти же три громкости на приборе дублирует страница FX MIXER (DEL/REV/CHR).
- **MIXER.** Ручки EXTERNAL MIXER (страница 5) на своих местах: IN, DUAL, BAL / DEL, REV, CHR. На пустой D — Master Overdrive (MOVD со страницы FX MIXER), на пустой H — Pattern Volume (LEVEL/DATA всех страниц микшера, в C.10 указан в таблице компрессора). При DUAL ON те же адреса управляют входом L, а BAL становится PAN.
- **INTERNAL MIXER 1/2** — это LEV каждого трека на его канале; отдельных глобальных адресов нет.
- **EUCLID** — евклидов SEQUENCER ([FUNC]+[AMP]: PL1, PL2, EUC, RO1, RO2, TRO, OP — NRPN 3:8–3:14). LEN без MIDI-адреса остаётся пустым. **INPUT R** — правый вход EXTERNAL MIXER 6 (CC 73, 75, 77, 79, 81), действует при DUAL ON. Все 167 строк приложения C теперь имеют адресуемые параметры каталога.
- **DEST** зависит от машины: в списке названы ручки SYN этой машины, поэтому id содержит машину (`fmTone.mod1.dest`). Остальные ручки MOD общие (`mod1.spd`).

## Ручки FLTR F и G

FLTR-машину нельзя прочитать по MIDI, поэтому у ручек F и G общие метки `F` и `G`. Значение зависит от машины:

| FLTR-машина | F | G | Заметка |
|---|---|---|---|
| MULTI-MODE | RESO | TYPE | TYPE плавно ведёт LP → BP → HP |
| LOWPASS 4 | RESO | — | 4 полюса, 24 дБ/окт; G не используется |
| LEGACY LP/HP | RESO | TYPE | TYPE: LP или HP, 2 полюса, 12 дБ/окт |
| COMB- | FDBK | LPF | отрицательная обратная связь; LPF в петле |
| COMB+ | FDBK | LPF | положительная обратная связь; LPF в петле |
| EQUALIZER | GAIN | Q | параметрический EQ; FREQ — центр полосы |

ATK/DEC/SUS/REL, DEL, KEY.T и RSET влияют только на выбранную FLTR-машину, не на base-width фильтр FLTR 2.

## Параметры по страницам

### Общие страницы аудиотрека

**TRIG**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | NOTE | Trig Note | 3 | 3:0 | C0 … G10 (128) | C5 |
| B | VEL | Trig Velocity | 4 | 3:1 | 0–127 | 100 |
| C | LEN | Trig Length | 5 | 3:2 | 0–127 | 0 |
| E | LFO.T | LFO Trig | 14 | — | OFF/ON | OFF |
| F | FLT.T | Filter Trig | 13 | — | OFF/ON | OFF |
| G | PTIM | Portamento Time | 9 | 3:6 | 0–127 | 0 |
| H | PORT | Portamento | 65 | 3:7 | OFF/ON | OFF |

**FLTR1**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | ATK | Attack Time | 20 | 1:16 | 0–127 | 0 |
| B | DEC | Decay Time | 21 | 1:17 | 0–127 | 0 |
| C | SUS | Sustain Level | 22 | 1:18 | 0–127 | 0 |
| D | REL | Release Time | 23 | 1:19 | 0–127 | 0 |
| E | FREQ | Frequency | 16 | 1:20 ⁺ | 0–127 | 127 |
| F | F | Filter knob F (RESO · FDBK · GAIN) | 17 | 1:21 | 0–127 | 0 |
| G | G | Filter knob G (TYPE · LPF · Q) | 18 | 1:22 | 0–127 | 0 |
| H | ENV | Env. Depth | 24 | 1:26 | −64…+63 | 0 |

**FLTR2**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | DEL | Env. Delay | 19 | 1:23 | 0–127 | 0 |
| D | KEY.T | Key Tracking | 26 | 1:69 | 0–127 | 0 |
| E | BASE | Base | 27 | 1:24 | 0–127 | 0 |
| F | WDTH | Width | 28 | 1:25 | 0–127 | 127 |
| H | RSET | Env. Reset | 25 | 1:68 | OFF/ON | ON ★ |

**AMP**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | ATK | Attack Time | 84 | 1:30 | 0–127 | 0 |
| B | DEC | Decay Time | 86 | 1:32 | 0–127 | 0 |
| C | SUS | Sustain Level | — | 1:33 | 0–127 | 127 |
| D | REL | Release Time | 88 | 1:34 | 0–127 | 0 |
| E | RSET | Env. Reset | 92 | 1:41 | OFF/ON | ON ★ |
| F | MODE | Envelope Mode | 91 | 1:40 | AHD · ADSR | AHD |
| G | PAN | Pan | 89 | 1:38 | −64…+63 | 0 |
| H | VOL | Volume | 90 | 1:39 | 0–127 | 100 |

**FX**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | BR | Bit Reduction | 78 | 1:5 | 0–127 | 0 |
| B | OVER | Overdrive | 81 | 1:8 | 0–127 | 0 |
| C | SRR | Sample Rate Reduction | 79 | 1:6 | 0–127 | 0 |
| D | SR.RT | SRR Routing | 80 | 1:7 | PRE · POST | PRE |
| E | DEL | Delay Send | 30 | 1:36 | 0–127 | 0 |
| F | REV | Reverb Send | 31 | 1:37 | 0–127 | 0 |
| G | CHR | Chorus Send | 29 | 1:35 | 0–127 | 0 |
| H | OD.RT | Overdrive Routing | 82 | 1:9 | PRE · POST | PRE |

**MOD1**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | SPD | Speed | 102 | 1:42 | −64…+63 | 0 |
| B | MULT | Multiplier | 103 | 1:43 | BPM 1 … 2K (24) | BPM 1 |
| C | FADE | Fade In/Out | 104 | 1:44 | −64…+63 | 0 |
| D | DEST | Destination | 105 | 1:45 | NONE … FX OVER (58) | NONE |
| E | WAVE | Waveform | 106 | 1:46 | TRI … RAND (7) | TRI |
| F | SPH | Start Phase / Slew | 107 | 1:47 | 0–127 | 0 |
| G | MODE | Trig Mode | 108 | 1:48 | FREE · TRIG · HOLD · ONE · HALF | FREE ★ |
| H | DEP | Depth | 109 | 1:49 ⁺ | −64…63 | 0.00 |

**MOD2**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | SPD | Speed | 111 | 1:50 | −64…+63 | 0 |
| B | MULT | Multiplier | 112 | 1:51 | BPM 1 … 2K (24) | BPM 1 |
| C | FADE | Fade In/Out | 113 | 1:52 | −64…+63 | 0 |
| D | DEST | Destination | 114 | 1:53 | NONE … FX OVER (65) | NONE |
| E | WAVE | Waveform | 115 | 1:54 | TRI … RAND (7) | TRI |
| F | SPH | Start Phase / Slew | 116 | 1:55 | 0–127 | 0 |
| G | MODE | Trig Mode | 117 | 1:56 | FREE · TRIG · HOLD · ONE · HALF | FREE ★ |
| H | DEP | Depth | 118 | 1:57 ⁺ | −64…63 | 0.00 |

**MOD3**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | SPD | Speed | — | 1:58 | −64…+63 | 0 |
| B | MULT | Multiplier | — | 1:59 | BPM 1 … 2K (24) | BPM 1 |
| C | FADE | Fade In/Out | — | 1:60 | −64…+63 | 0 |
| D | DEST | Destination | — | 1:61 | NONE … FX OVER (72) | NONE |
| E | WAVE | Waveform | — | 1:62 | TRI … RAND (7) | TRI |
| F | SPH | Start Phase / Slew | — | 1:70 | 0–127 | 0 |
| G | MODE | Trig Mode | — | 1:71 | FREE · TRIG · HOLD · ONE · HALF | FREE ★ |
| H | DEP | Depth | — | 1:72 ⁺ | −64…63 | 0.00 |

**TRACK**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | MUTE | Mute | 94 | 1:108 | OFF/ON | OFF |
| B | LEV | Track Level | 95 | 1:110 | 0–127 | 100 |
| C | PMUT | Pattern Mute | 110 | 1:109 | OFF/ON | OFF |
| D | HOLD | Amp Hold Time (AHD) | 85 | 1:31 | 0 … NOTE (128) | 0 |

### FM TONE

**SYN1**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | ALGO | Algorithm | 40 | 1:73 | 1–8 | 1 |
| B | RAT C | Ratio C | 41 | 1:74 | 0–127 | 0 |
| C | RAT A | Ratio A | 42 | 1:75 | 0–127 | 0 |
| D | RAT B | Ratio B (B1 · B2) | 43 | 1:76 | 0–127 | 0 |
| E | HARM | Harmonics | 44 | 1:77 ⁺ | −26…25.59 | 0.00 |
| F | DTUN | Detune | 45 | 1:78 | 0–127 | 0 |
| G | FDBK | Feedback | 46 | 1:79 | 0–127 | 0 |
| H | MIX | Mix X/Y | 47 | 1:80 | −64…+63 | 0 |

**SYN2**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | ATK A | Attack Time A | 48 | 1:81 | 0–127 | 0 |
| B | DEC A | Decay Time A | 49 | 1:82 | 0–127 | 0 |
| C | END A | End Level A | 50 | 1:83 | 0–127 | 0 |
| D | LEV A | Level A | 51 | 1:84 | 0–127 | 0 |
| E | ATK B | Attack Time B | 52 | 1:85 | 0–127 | 0 |
| F | DEC B | Decay Time B | 53 | 1:86 | 0–127 | 0 |
| G | END B | End Level B | 54 | 1:87 | 0–127 | 0 |
| H | LEV B | Level B | 55 | 1:88 | 0–127 | 0 |

**SYN3**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | ADEL | Env. Delay A | 56 | 1:89 | 0–127 | 0 |
| B | ATRG | Env. Trig A | 57 | 1:90 | OFF/ON | OFF |
| C | ARST | Env. Reset A | 58 | 1:91 | OFF/ON | OFF |
| D | PHRT | Phase Reset | 59 | 1:92 | OFF · ALL · C · A+B · A+B2 | OFF |
| E | BDEL | Env. Delay B | 60 | 1:93 | 0–127 | 0 |
| F | BTRG | Env. Trig B | 61 | 1:94 | OFF/ON | OFF |
| G | BRST | Env. Reset B | 62 | 1:95 | OFF/ON | OFF |

**SYN4**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | OFS C | Ratio Offset C | 70 | 1:97 ⁺ | −64…+63 | 0 |
| B | OFS A | Ratio Offset A | 71 | 1:98 ⁺ | −64…+63 | 0 |
| C | OFS B1 | Ratio Offset B1 | 72 | 1:99 ⁺ | −64…+63 | 0 |
| D | OFS B2 | Ratio Offset B2 | 73 | 1:100 ⁺ | −64…+63 | 0 |
| F | KEY A | Key Track A | 75 | 1:102 | 0–127 | 0 |
| G | KEY B1 | Key Track B1 | 76 | 1:103 | 0–127 | 0 |
| H | KEY B2 | Key Track B2 | 77 | 1:104 | 0–127 | 0 |

### FM DRUM

**SYN1**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | TUNE | Tune | 40 | 1:73 | −64…+63 | 0 |
| B | STIM | Sweep Time | 41 | 1:74 | 0–127 | 0 |
| C | SDEP | Sweep Depth | 42 | 1:75 | 0–127 | 0 |
| D | ALGO | Algorithm | 43 | 1:76 | 1–7 | 1 |
| E | OP.C | Operator C Wave | 44 | 1:77 | 0–127 | 0 |
| F | OP.AB | Operator A·B Wave | 45 | 1:78 | 0–127 | 0 |
| G | FDBK | Feedback | 46 | 1:79 | 0–127 | 0 |
| H | FOLD | Fold | 47 | 1:80 | 0–127 | 0 |

**SYN2**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | RAT A | Ratio A | 48 | 1:81 ⁺ | 0–127 | 0 |
| B | DEC A | Decay A | 49 | 1:82 | 0–127 | 0 |
| C | END A | End A | 50 | 1:83 | 0–127 | 0 |
| D | MOD A | Mod A | 51 | 1:84 | 0–127 | 0 |
| E | RAT B | Ratio B | 52 | 1:85 ⁺ | 0–127 | 0 |
| F | DEC B | Decay B | 53 | 1:86 | 0–127 | 0 |
| G | END B | End B | 54 | 1:87 | 0–127 | 0 |
| H | MOD B | Mod B | 55 | 1:88 | 0–127 | 0 |

**SYN3**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | HOLD | Body Hold | 56 | 1:89 | 0–127 | 0 |
| B | DEC | Body Decay | 57 | 1:90 | 0 … INF (128) | 0 |
| C | PH.C | OP C Phase | 58 | 1:91 | 0 … OFF (92) | 0 |
| D | LEV | Body Level | 59 | 1:92 | 0–127 | 0 |
| G | NRST | Noise Reset | 62 | 1:95 | OFF/ON | OFF |
| H | NRM | Noise Ring Mod | 63 | 1:96 | OFF/ON | OFF |

**SYN4**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | NHLD | Noise Hold | 70 | 1:97 | 0–127 | 0 |
| B | NDEC | Noise Decay | 71 | 1:98 | 0 … INF (128) | 0 |
| C | TRAN | Drum Transient | 72 | 1:99 | 0–127 | 0 |
| D | TLEV | Transient Level | 73 | 1:100 | 0–127 | 0 |
| E | BASE | Noise Base | 74 | 1:101 | 0–127 | 0 |
| F | WDTH | Noise Width | 75 | 1:102 | 0–127 | 127 |
| G | GRAN | Noise Grain | 76 | 1:103 | 0–127 | 0 |
| H | NLEV | Noise Level | 77 | 1:104 | 0–127 | 0 |

### WAVETONE

**SYN1**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | TUN1 | Osc1 Tune | 40 | 1:73 | −64…+63 | 0 |
| B | WAV1 | Osc1 Waveform | 41 | 1:74 | 0–127 | 0 |
| C | PD1 | Osc1 Phase Distortion | 42 | 1:75 | 0–127 | 0 |
| D | LEV1 | Osc1 Level | 43 | 1:76 | 0–127 | 0 |
| E | TUN2 | Osc2 Tune | 44 | 1:77 | −64…+63 | 0 |
| F | WAV2 | Osc2 Waveform | 45 | 1:78 | 0–127 | 0 |
| G | PD2 | Osc2 Phase Distortion | 46 | 1:79 | 0–127 | 0 |
| H | LEV2 | Osc2 Level | 47 | 1:80 | 0–127 | 0 |

**SYN2**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | OFS1 | Osc1 Lin Offset | 48 | 1:81 | −64…+63 | 0 |
| B | TBL1 | Osc1 Wavetable | 49 | 1:82 | PRIM · HARM | PRIM |
| C | MOD | Oscillator Modulation | 50 | 1:83 | OFF · RING MOD · RING MOD FIXED · HARD SYNC | OFF |
| D | RSET | Oscillator Phase Reset | 51 | 1:84 | OFF · ON · RAND | OFF |
| E | OFS2 | Osc2 Lin Offset | 52 | 1:85 | −64…+63 | 0 |
| F | TBL2 | Osc2 Wavetable | 53 | 1:86 | PRIM · HARM | PRIM |
| H | DRIF | Oscillator Drift | 55 | 1:88 | 0–127 | 0 |

**SYN3**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | ATK | Noise Attack | 56 | 1:89 | 0–127 | 0 |
| B | HOLD | Noise Hold | 57 | 1:90 | 0 … NOTE (128) | 0 |
| C | DEC | Noise Decay | 58 | 1:91 | 0–127 | 0 |
| D | NLEV | Noise Level | 59 | 1:92 | 0–127 | 0 |
| E | BASE | Noise Base | 60 | 1:93 | 0–127 | 0 |
| F | WDTH | Noise Width | 61 | 1:94 | 0–127 | 127 |
| G | TYPE | Noise Type | 62 | 1:95 | GRAIN · TUNED · S&H | GRAIN |
| H | CHAR | Noise Character | 63 | 1:96 | 0–127 | 0 |

### SWARMER

**SYN1**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | TUNE | Tune | 40 | 1:73 | −64…+63 | 0 |
| B | SWRM | Swarm Waveform | 41 | 1:74 | 0–127 | 0 |
| C | DET | Detune | 42 | 1:75 | 0–127 | 0 |
| D | MIX | Mix | 43 | 1:76 | 0–127 | 0 |
| E | M.OCT | Main Octave | 44 | 1:77 | 0 · -1 · -2 | 0 |
| F | MAIN | Main Waveform | 45 | 1:78 | 0–127 | 0 |
| G | ANIM | Swarm Animation | 46 | 1:79 | 0–127 | 0 |
| H | N.MOD | Noise Modulation | 47 | 1:80 | 0–127 | 0 |

### MIDI

**TRIG**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | NOTE | Trig Note | 3 | 3:0 | C0 … G10 (128) | C5 |
| B | VEL | Trig Velocity | 4 | 3:1 | 0–127 | 100 |
| C | LEN | Trig Length | 5 | 3:2 | 0–127 | 0 |
| E | LFO.T | LFO Trig | 14 | — | OFF/ON | OFF |

**SYN1**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | CHAN | MIDI Channel | 40 | 1:73 | OFF … 16 (17) | OFF |
| B | BANK | Bank (CC 0) | 41 | 1:74 | 0–127 | 0 |
| C | SBNK | Sub Bank (CC 32) | 42 | 1:75 | 0–127 | 0 |
| D | PROG | Program Change | 43 | 1:76 | 0–127 | 0 |
| E | PB | Pitch Bend | 44 | 1:77 | −64…+63 | 0 |
| F | AT | Aftertouch | 45 | 1:78 | 0–127 | 0 |
| G | MW | Mod Wheel | 46 | 1:79 | 0–127 | 0 |
| H | BC | Breath Controller | 47 | 1:80 | 0–127 | 0 |

**FLTR1**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | VAL1 | CC 1 Value | 70 | 1:16 | 0–127 | 0 |
| B | VAL2 | CC 2 Value | 71 | 1:17 | 0–127 | 0 |
| C | VAL3 | CC 3 Value | 72 | 1:18 | 0–127 | 0 |
| D | VAL4 | CC 4 Value | 73 | 1:19 | 0–127 | 0 |
| E | VAL5 | CC 5 Value | 74 | 1:20 | 0–127 | 0 |
| F | VAL6 | CC 6 Value | 75 | 1:21 | 0–127 | 0 |
| G | VAL7 | CC 7 Value | 76 | 1:22 | 0–127 | 0 |
| H | VAL8 | CC 8 Value | 77 | 1:23 | 0–127 | 0 |

**AMP**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | VAL9 | CC 9 Value | 78 | 1:60 | 0–127 | 0 |
| B | VAL10 | CC 10 Value | 79 | 1:61 | 0–127 | 0 |
| C | VAL11 | CC 11 Value | 80 | 1:62 | 0–127 | 0 |
| D | VAL12 | CC 12 Value | 81 | 1:63 | 0–127 | 0 |
| E | VAL13 | CC 13 Value | 82 | 1:64 | 0–127 | 0 |
| F | VAL14 | CC 14 Value | 83 | 1:65 | 0–127 | 0 |
| G | VAL15 | CC 15 Value | 84 | 1:66 | 0–127 | 0 |
| H | VAL16 | CC 16 Value | 85 | 1:67 | 0–127 | 0 |

**TRACK**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | MUTE | Mute | 94 | 1:108 | OFF/ON | OFF |
| C | PMUT | Pattern Mute | 110 | 1:109 | OFF/ON | OFF |

MOD1/MOD2 — как у аудиотрека, но с собственным списком DEST.

### Глобальные страницы (FX CONTROL CH)

**DELAY**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | TIME | Delay Time | 21 | 2:0 ⁺ | 1–128 | 32 |
| B | X | Ping-pong | 22 | 2:1 | OFF/ON | OFF |
| C | WID | Stereo Width | 23 | 2:2 | −64…+63 | 0 |
| D | FDBK | Feedback | 24 | 2:3 | 0–127 | 0 |
| E | HPF | Highpass Filter | 25 | 2:4 | 0–127 | 0 |
| F | LPF | Lowpass Filter | 26 | 2:5 | 0–127 | 127 |
| G | VOL | Mix Volume | 28 | 2:7 | 0–127 | 100 |
| H | REV | Reverb Send | 27 | 2:6 | 0–127 | 0 |

**REVERB**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | PRE | Predelay | 29 | 2:8 | 0–127 | 0 |
| B | DEC | Decay Time | 30 | 2:9 | 0–127 | 0 |
| C | FREQ | Shelving Freq | 31 | 2:10 | 0–127 | 0 |
| D | GAIN | Shelving Gain | 89 | 2:11 | 0–127 | 127 |
| E | HPF | Highpass Filter | 90 | 2:12 | 0–127 | 0 |
| F | LPF | Lowpass Filter | 91 | 2:13 | 0–127 | 127 |
| G | VOL | Mix Volume | 92 | 2:15 | 0–127 | 100 |

**CHORUS**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | DPTH | Depth | 16 | 2:41 | 0–127 | 0 |
| B | SPD | Speed | 9 | 2:42 | 0–127 | 0 |
| C | HPF | High Pass Filter | 70 | 2:43 | 0–127 | 0 |
| D | WDTH | Width | 71 | 2:44 | 0–127 | 127 |
| E | VOL | Mix Volume | 14 | 2:47 | 0–127 | 100 |
| G | DEL | Delay Send | 12 | 2:45 | 0–127 | 0 |
| H | REV | Reverb Send | 13 | 2:46 | 0–127 | 0 |

**COMP**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | THR | Threshold | 111 | 2:16 | 0–127 | 127 |
| B | ATK | Attack Time | 112 | 2:17 | 0–127 | 0 |
| C | REL | Release Time | 113 | 2:18 | 0–127 | 0 |
| D | MUP | Makeup Gain | 114 | 2:19 | 0–127 | 0 |
| E | RAT | Ratio | 115 | 2:20 | 1.50 … 20.00 (8) | 1.50 |
| F | SCS | Sidechain Source | 116 | 2:21 | COMP MIX … IN R (21) | COMP MIX |
| G | SCF | Sidechain Filter | 117 | 2:22 | −64…+63 | 0 |
| H | MIX | Dry/Wet Mix | 118 | 2:23 | 0–127 | 0 |

**MIXER**

| Ручка | Метка | Параметр | CC | NRPN | Значения | По умолч. |
|---|---|---|---:|---:|---|---|
| A | IN | Input Level | 72 | 2:30 | 0–127 | 0 |
| B | DUAL | Dual Mono | 82 | 2:40 | OFF/ON | OFF |
| C | BAL | Input Balance | 74 | 2:32 | −64…+63 | 0 |
| D | MOVD | Master Overdrive | 17 | 2:50 | 0–127 | 0 |
| E | DEL | Input Delay Send | 78 | 2:36 | 0–127 | 0 |
| F | REV | Input Reverb Send | 80 | 2:38 | 0–127 | 0 |
| G | CHR | Input Chorus Send | 76 | 2:34 | 0–127 | 0 |
| H | VOL | Pattern Volume | 119 | 2:24 | 0–127 | 100 |

## Цели LFO (DEST)

Список собран по приложению D в его порядке: NONE; ручки более ранних LFO (LFO1 видит только остальное, LFO2 — ручки LFO1, LFO3 — LFO1 и LFO2); ручки SYN этой машины страница за страницей, A–H, без пустых; FLTR ×13; AMP ×7; FX ×7. У MIDI-трека: NONE, ручки LFO1 (для LFO2), SYN PB/AT/MW/BC, CC VAL1–16. Полные списки — в JSON, ключ `lfoDestinations`.

Пример, FM TONE LFO 1 (58 целей): NONE, SYN ALGO, SYN RAT C, SYN RAT A, SYN RAT B, SYN HARM, SYN DTUN, SYN FDBK, SYN MIX, SYN ATK A, SYN DEC A, SYN END A, ….

## Совпадающие номера

Внутри одной области (канал трека одной машины или FX CONTROL CH) номера CC и NRPN уникальны — это проверяет тест. Одни и те же числа значат разное в разных областях:

| Номер | Канал трека | FX CONTROL CH |
|---|---|---|
| CC 9 | PTIM | Chorus SPD |
| CC 13, 14 | FLT.T, LFO.T | Chorus REV send, VOL |
| CC 16, 17 | FLTR FREQ, F | Chorus DPTH, Master Overdrive |
| CC 21–28 | FLTR DEC…Width | DELAY |
| CC 29–31 | FX CHR/DEL/REV send | REVERB PRE, DEC, FREQ |
| CC 70–77 | SYN4 A–H (аудио) / VAL1–8 (MIDI) | Chorus HPF, WDTH; входы микшера |
| CC 78–85 | FX и AMP (аудио) / VAL9–16 (MIDI) | входы микшера |
| CC 89–92 | AMP PAN, VOL, MODE, RSET | REVERB GAIN, HPF, LPF, VOL |
| CC 111–118 | LFO 2 | COMPRESSOR |
| NRPN 1:16–1:23 | FLTR (аудио) / VAL1–8 (MIDI) | — |
| NRPN 1:60–1:62 | LFO 3 (аудио) / VAL9–11 (MIDI) | — |

Поэтому `HardwareCatalog.match` всегда получает машину трека и флаг `global`.

## MIDI CONFIG (13.4)

**CHANNELS**

| Настройка | Что делает |
|---|---|
| TRACK 1–16 | канал параметров трека, приём и передача; OFF отключает |
| FX CONTROL CH | канал DELAY, REVERB, CHORUS, COMPRESSOR и master overdrive; OFF отключает |
| AUTO CHANNEL | всегда адресует активный трек; через него пишутся MIDI-треки с внешней клавиатуры |
| PROGRAM CHG IN CH | канал приёма program change; AUTO = AUTO CHANNEL |
| PROGRAM CHG OUT CH | канал отправки program change при смене паттерна; AUTO = AUTO CHANNEL |

Ноты секвенсора MIDI-трека уходят на канал его параметра CHAN (страница SYN), а не на канал TRACK.

**SYNC:** CLOCK RECEIVE, CLOCK SEND, TRANSPORT RECEIVE, TRANSPORT SEND, PRG CH RECEIVE (program change 0–127 выбирает паттерны A01–H16), PRG CH SEND. На скриншоте 13.4.1 включены только CLOCK RECEIVE и TRANSPORT RECEIVE; заводскими значениями руководство это не называет.

**PORT CONFIG**

| Настройка | Варианты |
|---|---|
| OUT PORT FUNC, THRU PORT FUNC | MIDI · DIN 24 · DIN 48 |
| INPUT FROM, OUTPUT TO | DISABLED · MIDI · USB · MIDI+USB |
| OUTPUT CH | AUTO CH · TRACK CH — куда ручки шлют CC/NRPN |
| PARAM OUTPUT | CC · NRPN — какие сообщения шлют ручки |
| ENCODER DEST | INT · INT + EXT — шлют ли ручки MIDI вообще |
| TRIG KEY DEST, MUTE DEST | INT · INT + EXT · EXT |
| RECEIVE NOTES, RECEIVE CC/NRPN | вкл/выкл |

Чтобы приложение видело ручки прибора, нужны ENCODER DEST = INT + EXT и OUTPUT TO с USB; для тонких значений — PARAM OUTPUT = NRPN. Чтобы прибор слушал приложение — INPUT FROM с USB и RECEIVE CC/NRPN.

**Ноты (8.4):** ноты 0–15 (C0–D#1) запускают треки 1–16 при каналах по умолчанию; 16–84 играют активный трек хроматически (в руководстве написано E2–C7, по его же нумерации нота 16 — это E1); C5 = 60.

## Заводские каналы (`factoryChannels`)

| Настройка | Значение | Откуда |
|---|---|---|
| TRACK 1–16 | каналы 1–16 | руководство, 8.4 («каналы по умолчанию 1–16») |
| AUTO CHANNEL | 10 | не указано; так настроен прибор пользователя |
| FX CONTROL CH | OFF (`nil`) | не указано; допущение |
| PROGRAM CHG IN CH | AUTO (`nil`) | не указано; допущение |

`DNChannelMap` хранит каналы с нуля: трек i → канал i − 1, AUTO = 9.

## Ручки без MIDI-адреса

| Страница | Ручка | Метка | Что это |
|---|---|---|---|
| TRIG 1 | D | PROB | вероятность трига |
| TRIG 1 | G | FILL | условие FILL |
| TRIG 1 | H | COND | условие трига |
| TRIG 2 | A | RTRG | ретриг вкл/выкл |
| TRIG 2 | B | VFAD | затухание ретрига |
| TRIG 2 | C | LEN | длина ретрига |
| TRIG 2 | D | RATE | частота ретрига |
| FLTR 2 | G | BW.RT | base-width фильтр до/после FLTR |
| MIDI FLTR 2 | A–H | SEL1–SEL8 | номера CC для VAL1–8 |
| MIDI AMP 2 | A–H | SEL9–SEL16 | номера CC для VAL9–16 |
| SEQUENCER | C | LEN | длина трека (PER TRACK) |
| INTERNAL MIXER 1/2 | A–H | TRK1–TRK16 | уровни треков = LEV на канале трека |

## Неуверенности

- **Кодирование списков по CC.** Каталог считает, что значение CC — номер опции (0, 1, 2…), как у других Elektron. Для MODE AMP, MULT, DEST, SCS, PHRT, MOD и RSET WAVETONE, CHAN порядок взят из текста руководства, а соответствие числам на приборе не проверено.
- **MULT:** вторая половина списка (фиксированные 120 BPM) показана просто числами; как прибор подписывает эти значения и в каком порядке идут половины — не проверено.
- **DEST:** порядок SYN-целей (страница за страницей или ручка за ручкой) и пропуск пустых ручек — допущение; приложение D перечисляет их сжато.
- **Таблицы ratio FM TONE и FM DRUM, волны OP.C/OP.AB, SWRM/MAIN, TRAN, длина трига LEN, BR, KEY.T в процентах, MUP в дБ** в руководстве не опубликованы — показывается сырое 0–127.
- **Диапазоны TUNE** (FM DRUM, WAVETONE, SWARMER), OFS1/OFS2, смещений ratio не опубликованы: формат биполярный −64…+63.
- **HARM** показан на шкале −26.00…25.59, чтобы 64 давало ровно 0.00; на полном NRPN прибор доходит до 26.00.
- **ALGO FM DRUM:** число алгоритмов не названо; 1–7 выведено из схемы голоса (алгоритмы 5–7).
- **Раскладка AMP в режиме AHD** не показана. Если прибор в AHD ставит HOLD на B, а DEC на C, слоты каталога остаются по ADSR-скриншоту — адреса от этого не меняются.
- **SUS CC 86** — см. выше; проверить на приборе, какой CC реально шлёт ручка SUS.
- **MIDI-машина по CC 40–47:** приложение C называет их «зависящими от машины», для страницы SYN MIDI-трека это не проверено; CHAN нельзя залочить, OFF для BANK/SBNK/PROG/VAL по CC, видимо, недостижим.
- **OS:** таблицы взяты из 1.12, прибор на 1.10D.

## Проверка на приборе

Отправлять на прибор можно только note on/off — CC/NRPN меняют проект пользователя. Проверка адресов делается в обратную сторону: включить на приборе ENCODER DEST = INT + EXT и PARAM OUTPUT = NRPN, крутить ручки и сверять входящие номера с `HardwareCatalog.match`. Уже подтверждены CC 16 (FREQ), 17 (FLTR F) и 20 (FLTR ATK) на AUTO CHANNEL 10.

import SwiftUI
import DigitoneCore
import DigitoneMIDI
import DigitoneDesign
#if os(macOS)
import AppKit
#endif

/// Logic-style piano roll: keyboard on the left, notes in the grid, velocity
/// stems below. Every key and every placed note plays on the Digitone.
struct PianoRollView: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var roll: PianoRollState
    var compact: Bool
    @Environment(\.isSnapshotRendering) private var snapshot
    @Environment(\.colorScheme) private var scheme
    @State private var drag: GridDrag?
    @State private var velocityDrag: VelocityDrag?
    @State private var rulerDrag: RulerDrag?
    @State private var lastTap: (time: Date, point: CGPoint)?
    @FocusState private var focused: Bool

    private var metrics: PianoRollMetrics { compact ? .compact : .regular }
    private var rollHeight: CGFloat { metrics.ruler + metrics.grid + metrics.velocity }
    private var laneChannel: Int { workspace.lane?.channel ?? 0 }
    private var playhead: Double? { model.isSequencePlaying ? model.sequencePlayhead : roll.demoPlayhead }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 14) {
            PianoRollLaneChips(lanes: workspace.sequence.lanes, current: workspace.laneIndex,
                               trackNames: model.pattern?.trackNames, length: workspace.sequence.length, compact: compact) { index in
                releaseEverything()
                workspace.selectLane(index)
                roll.topPitch = nil
            }
            VStack(spacing: 0) {
                toolbar
                Rectangle().fill(InstrumentTheme.line).frame(height: 1)
                GeometryReader { proxy in rollBody(width: proxy.size.width) }.frame(height: rollHeight)
            }
            .background(InstrumentTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 16 : 20))
            .overlay(RoundedRectangle(cornerRadius: compact ? 16 : 20).stroke(InstrumentTheme.line, lineWidth: 1))
            footer
        }
        .modifier(HardwareKeys(enabled: !snapshot, focused: $focused, handle: handleKey))
        .onReceive(model.midiInput) { receive($0) }
        .onReceive(model.$sequencePlayhead) { tick in
            roll.recorder.sync(playhead: tick, at: HostClock.now, bpm: workspace.sequence.tempo, length: workspace.sequence.length)
        }
        .onChange(of: workspace.sequence) { _, sequence in model.updatePlayingSequence(sequence) }
        .onChange(of: model.isSequencePlaying) { _, playing in playbackChanged(playing) }
        .onChange(of: model.connected) { _, connected in if !connected { releaseEverything() } }
        .onDisappear { releaseEverything(); roll.commandHeld = false }
    }

    // MARK: Layout

    private func geometry(width: CGFloat) -> PianoRollGeometry {
        let gridWidth = max(1, width - metrics.keyboard)
        let extent = currentExtent
        let rowHeight = min(PianoRollGeometry.rowHeights.upperBound, max(PianoRollGeometry.rowHeights.lowerBound, roll.rowHeight ?? metrics.rowHeight))
        var g = PianoRollGeometry(width: gridWidth, height: metrics.grid,
                                  pixelsPerTick: PianoRollGeometry.pixelsPerTick(width: gridWidth, extent: extent, zoom: roll.zoom),
                                  originTick: 0, rowHeight: rowHeight, topPitch: 0)
        g.originTick = g.clampedOriginTick(roll.originTick, extent: extent)
        g.topPitch = g.clampedTopPitch(roll.topPitch ?? autoTopPitch(rows: Double(metrics.grid / rowHeight)))
        return g
    }

    private var currentExtent: Int {
        roll.frozenExtent ?? PianoRollGeometry.extent(length: workspace.sequence.length, notes: workspace.laneNotes)
    }

    /// Centres the lane's notes, or the octave above middle C when empty.
    private func autoTopPitch(rows: Double) -> Double {
        let center = workspace.lane?.pitchRange.map { Double($0.lowerBound + $0.upperBound) / 2 + 0.5 } ?? 66.5
        return center + rows / 2
    }

    private func scene(_ g: PianoRollGeometry) -> PianoRollScene {
        PianoRollScene(geometry: g, sequence: workspace.sequence, laneIndex: workspace.laneIndex, selection: workspace.selection,
                       snap: roll.snap, lit: litKeys, playhead: playhead, cursor: roll.step.cursor, recording: roll.isRecording,
                       pending: roll.pending.filter { roll.pendingLane[$0.key] == workspace.laneIndex }.map(\.value).sorted { $0.pitch < $1.pitch }, marquee: roll.marquee,
                       dark: scheme == .dark, compact: compact)
    }

    private var litKeys: [Int: PianoKeyLight] {
        var lit: [Int: PianoKeyLight] = [:]
        if let playhead {
            for pitch in PianoRollRouting.sounding(workspace.laneNotes, at: playhead) { lit[pitch] = .playback }
        }
        for pitch in roll.incoming { lit[pitch] = .incoming }
        for pitch in roll.heldPitches { lit[pitch] = .pressed }
        return lit
    }

    private func rollBody(width: CGFloat) -> some View {
        let g = geometry(width: width)
        let scene = scene(g)
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                cornerBadge.frame(width: metrics.keyboard, height: metrics.ruler)
                    .overlay(alignment: .bottom) { Rectangle().fill(InstrumentTheme.line).frame(height: 1) }
                PianoKeyboardView(geometry: g, width: metrics.keyboard, lit: scene.lit, compact: compact,
                                  typingBase: compact ? nil : roll.typing.base, interactionDisabled: roll.multiTouch) { playPointer($0) }
                    .frame(width: metrics.keyboard, height: metrics.grid).clipped()
                velocityBadge.frame(width: metrics.keyboard, height: metrics.velocity)
                    .overlay(alignment: .top) { Rectangle().fill(InstrumentTheme.line).frame(height: 1) }
            }
            .overlay(alignment: .trailing) { Rectangle().fill(InstrumentTheme.line).frame(width: 1) }
            VStack(spacing: 0) {
                Canvas { context, size in scene.drawRuler(context, size: size) }
                    .frame(height: metrics.ruler).contentShape(Rectangle())
                    .gesture(rulerGesture(g))
                    .accessibilityLabel("Линейка: \(workspace.sequence.bars) такт.")
                Canvas { context, size in scene.drawGrid(context, size: size) }
                    .frame(height: metrics.grid).contentShape(Rectangle())
                    .gesture(gridGesture(g))
                    .modifier(GridHoverCursor(geometry: g, notes: workspace.laneNotes, selection: workspace.selection, pencil: roll.effectiveTool == .pencil))
                    .accessibilityElement()
                    .accessibilityLabel("Ноты: \(workspace.laneNotes.count)")
                Canvas { context, size in scene.drawVelocity(context, size: size) }
                    .frame(height: metrics.velocity).contentShape(Rectangle())
                    .gesture(velocityGesture(g))
                    .accessibilityLabel("Velocity")
            }
            .clipped()
        }
        .background {
            if !snapshot { PianoRollInputCatcher(handlers: inputHandlers(g)) }
        }
    }

    private var cornerBadge: some View {
        Group {
            if compact {
                Text("MIDI \(laneChannel + 1)")
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "keyboard").font(.system(size: 9))
                    Text(roll.typing.label)
                }
            }
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(InstrumentTheme.secondary)
        .lineLimit(1).minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(compact ? "MIDI-канал \(laneChannel + 1)" : "Клавиатура Mac: \(roll.typing.label)")
    }

    private var velocityBadge: some View {
        let values = workspace.selectedNotes.map(\.velocity)
        let text: String = values.isEmpty ? "" : (Set(values).count == 1 ? "\(values[0])" : "≈\(values.reduce(0, +) / values.count)")
        return VStack(spacing: 3) {
            Text("VEL").font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.5)
                .foregroundStyle(InstrumentTheme.secondary)
            if !text.isEmpty {
                Text(text).font(.system(size: compact ? 12 : 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(InstrumentTheme.ink)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: compact ? 6 : 8) {
            HStack(spacing: 2) {
                toolButton(.pointer, symbol: "cursorarrow", help: "Стрелка")
                toolButton(.pencil, symbol: "pencil", help: "Карандаш (⌘)")
            }
            .padding(2).background(InstrumentTheme.paper.opacity(0.8), in: RoundedRectangle(cornerRadius: 9))
            Menu {
                ForEach(PianoRollSnap.allCases) { snap in
                    Button { roll.snap = snap } label: {
                        if roll.snap == snap { Label(snap.label, systemImage: "checkmark") } else { Text(snap.label) }
                    }
                }
            } label: {
                Label(roll.snap.label, systemImage: "squareshape.split.3x3")
            }
            .menuStyle(.borderlessButton).fixedSize()
            .snapshotControl("▦ \(roll.snap.label)")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .help("Сетка")
            Button { workspace.quantizeSelection(grid: roll.snap == .off ? MusicalTime.ticksPerStep : roll.snap.grid) } label: {
                Text("Q").font(.system(size: 12, weight: .bold, design: .monospaced))
            }
            .buttonStyle(RollToolStyle()).help("Квантовать (Q)")
            .disabled(workspace.laneNotes.isEmpty)
            Button { toggleRecord() } label: {
                HStack(spacing: 5) {
                    Circle().fill(InstrumentTheme.record).frame(width: 9, height: 9)
                    if roll.isRecording {
                        Text(playhead != nil ? "REC" : "STEP").font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                }
            }
            .buttonStyle(RollToolStyle(active: roll.isRecording, tint: InstrumentTheme.record))
            .help("Запись (R)")
            if !compact {
                Rectangle().fill(InstrumentTheme.line).frame(width: 1, height: 20).padding(.horizontal, 4)
                laneLabel
            }
            Spacer(minLength: 4)
            Button { workspace.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(RollToolStyle()).disabled(!workspace.history.canUndo).help("Отменить (⌘Z)")
            Button { workspace.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(RollToolStyle()).disabled(!workspace.history.canRedo).help("Повторить (⌘⇧Z)")
            if !compact {
                PianoRollTempo(tempo: workspace.sequence.tempo) { workspace.setTempo($0) }
            }
        }
        .padding(.horizontal, compact ? 8 : 12).frame(height: compact ? 44 : 48)
    }

    private func toolButton(_ tool: PianoRollState.Tool, symbol: String, help: String) -> some View {
        Button { roll.tool = tool } label: { Image(systemName: symbol).font(.system(size: 12, weight: .medium)) }
            .buttonStyle(RollToolStyle(active: roll.effectiveTool == tool, size: 28))
            .help(help)
            .accessibilityAddTraits(roll.tool == tool ? .isSelected : [])
    }

    private var laneLabel: some View {
        HStack(spacing: 8) {
            Circle().fill(PianoRollPalette.lane(workspace.laneIndex)).frame(width: 8, height: 8)
            Text("T\(workspace.laneIndex + 1)").font(.system(size: 11, weight: .bold, design: .monospaced))
            Text(workspace.lane?.name ?? "").font(.system(size: 12)).lineLimit(1)
                .foregroundStyle(InstrumentTheme.secondary).frame(maxWidth: 140, alignment: .leading).fixedSize()
            Menu {
                ForEach(0..<16, id: \.self) { channel in
                    Button("MIDI \(channel + 1)") { releaseEverything(); workspace.setLaneChannel(channel) }
                }
            } label: { Text("MIDI \(laneChannel + 1)") }
                .menuStyle(.borderlessButton).fixedSize()
                .snapshotControl("MIDI \(laneChannel + 1)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .help("MIDI-канал дорожки")
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 13)).foregroundStyle(InstrumentTheme.secondary)
            Menu {
                ForEach(0..<8, id: \.self) { bank in
                    Menu(String(UnicodeScalar(65 + bank)!)) {
                        ForEach(0..<16, id: \.self) { slot in
                            Button(PatternSnapshot.slotName(bank * 16 + slot)) { model.patternIndex = bank * 16 + slot }
                        }
                    }
                }
            } label: { Text(PatternSnapshot.slotName(model.patternIndex)) }
                .menuStyle(.borderlessButton).fixedSize()
                .snapshotControl(PatternSnapshot.slotName(model.patternIndex))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            Button("Прочитать") { Task { await model.readPattern() } }
                .buttonStyle(InstrumentButtonStyle())
                .disabled(!model.connected || model.busy || model.isSequencePlaying)
            if let pattern = model.pattern {
                Button {
                    model.stopSequence(); releaseEverything(); workspace.copyPattern(pattern)
                } label: {
                    Label("\(PatternSnapshot.slotName(pattern.index)) · \(pattern.notes.count)", systemImage: "arrow.down.right")
                }
                .buttonStyle(InstrumentButtonStyle(prominent: true))
                .help("Открыть копию паттерна в piano roll")
            }
            Spacer(minLength: 0)
            if compact {
                PianoRollTempo(tempo: workspace.sequence.tempo) { workspace.setTempo($0) }
            }
        }
        .font(.system(size: 12))
    }

    // MARK: Grid gestures

    private struct GridDrag {
        enum Kind {
            case move(anchor: SequenceNote, copies: [UUID: UUID]?, collapse: Bool)
            case resize(anchor: SequenceNote)
            case marquee(base: Set<UUID>, additive: Bool)
            case idle
        }
        var kind: Kind
        var original: NoteSequence
        var ids: Set<UUID> = []
        var began = false
        var previewPitch: Int?
    }

    private func gridGesture(_ g: PianoRollGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if roll.multiTouch { cancelGridDrag(); return }
                if drag == nil { drag = gridDown(at: value.startLocation, g) }
                guard var current = drag else { return }
                gridDragged(&current, value: value, g)
                drag = current
            }
            .onEnded { value in
                if let current = drag, !roll.multiTouch { gridUp(current, value: value, g) }
                drag = nil
                roll.marquee = nil
            }
    }

    private func gridDown(at point: CGPoint, _ g: PianoRollGeometry) -> GridDrag {
        let modifiers = PianoRollModifiers.current
        let now = Date()
        let double = lastTap.map { now.timeIntervalSince($0.time) < 0.35 && hypot($0.point.x - point.x, $0.point.y - point.y) < 6 } ?? false
        lastTap = double ? nil : (now, point)
        let original = workspace.sequence
        let pencil = roll.tool == .pencil || modifiers.contains(.command)
        switch g.hit(point, notes: workspace.laneNotes, selected: workspace.selection) {
        case .note(let id, let edge):
            guard let note = workspace.laneNotes.first(where: { $0.id == id }) else { return GridDrag(kind: .idle, original: original) }
            if double && !pencil {
                workspace.deleteNote(id)
                return GridDrag(kind: .idle, original: original)
            }
            var collapse = false
            if modifiers.contains(.shift) {
                if workspace.selection.contains(id) {
                    workspace.selection.remove(id)
                    return GridDrag(kind: .idle, original: original)
                }
                workspace.selection.insert(id)
            } else if workspace.selection.contains(id) {
                collapse = workspace.selection.count > 1
            } else {
                workspace.selection = [id]
            }
            preview(note.pitch, velocity: note.velocity)
            if edge { return GridDrag(kind: .resize(anchor: note), original: original, ids: workspace.selection) }
            let copies = modifiers.contains(.option) ? Dictionary(uniqueKeysWithValues: workspace.selection.map { ($0, UUID()) }) : nil
            return GridDrag(kind: .move(anchor: note, copies: copies, collapse: collapse), original: original,
                            ids: workspace.selection, previewPitch: note.pitch)
        case .empty(let tick, let pitch):
            if pencil || double {
                let start = roll.snap.floor(tick)
                let length = pencil ? roll.snap.step : roll.lastLength
                guard let id = workspace.addNote(pitch: pitch, start: start, duration: length, velocity: roll.typing.velocity),
                      let note = workspace.laneNotes.first(where: { $0.id == id }) else { return GridDrag(kind: .idle, original: original) }
                preview(pitch, velocity: note.velocity)
                lastTap = nil
                guard pencil else { return GridDrag(kind: .idle, original: original) }
                return GridDrag(kind: .resize(anchor: note), original: workspace.sequence, ids: [id], began: true)
            }
            let additive = modifiers.contains(.shift)
            return GridDrag(kind: .marquee(base: additive ? workspace.selection : [], additive: additive), original: original)
        }
    }

    private func gridDragged(_ drag: inout GridDrag, value: DragGesture.Value, _ g: PianoRollGeometry) {
        let translation = value.translation
        let moved = abs(translation.width) > 3 || abs(translation.height) > 3
        let lane = workspace.laneIndex
        let selected = drag.original.lanes.indices.contains(lane) ? drag.original.lanes[lane].notes.filter { drag.ids.contains($0.id) } : []
        switch drag.kind {
        case .move(let anchor, let copies, _):
            guard moved || drag.began else { return }
            if !drag.began { workspace.beginGesture(); drag.began = true }
            let delta = PianoRollEdit.moveDelta(anchor: anchor, rawTicks: Double(translation.width / g.pixelsPerTick),
                                                rawPitch: -Int((translation.height / g.rowHeight).rounded()),
                                                snap: roll.snap, selection: selected, length: drag.original.length)
            workspace.updateGesture(PianoRollEdit.moved(drag.original, lane: lane, ids: drag.ids, ticks: delta.ticks, pitch: delta.pitch, copies: copies))
            if let copies { workspace.selection = Set(copies.values) }
            let pitch = anchor.pitch + delta.pitch
            if pitch != drag.previewPitch {
                drag.previewPitch = pitch
                preview(pitch, velocity: anchor.velocity)
            }
        case .resize(let anchor):
            guard moved || drag.began else { return }
            if !drag.began { workspace.beginGesture(); drag.began = true }
            let delta = PianoRollEdit.resizeDelta(anchor: anchor, rawTicks: Double(translation.width / g.pixelsPerTick), snap: roll.snap, selection: selected)
            workspace.updateGesture(PianoRollEdit.resized(drag.original, lane: lane, ids: drag.ids, by: delta))
            roll.lastLength = max(1, anchor.duration + delta)
        case .marquee(let base, _):
            guard moved else { return }
            let rect = CGRect(x: value.startLocation.x, y: value.startLocation.y, width: translation.width, height: translation.height).standardized
            roll.marquee = rect
            workspace.selection = base.union(g.notes(in: rect, from: workspace.laneNotes))
        case .idle:
            break
        }
    }

    private func gridUp(_ drag: GridDrag, value: DragGesture.Value, _ g: PianoRollGeometry) {
        let moved = abs(value.translation.width) > 3 || abs(value.translation.height) > 3
        switch drag.kind {
        case .marquee(_, let additive) where !moved:
            if !additive { workspace.deselectAll() }
            let tick = roll.snap.floor(g.tick(atX: value.startLocation.x))
            if (0..<workspace.sequence.length).contains(tick) { roll.step.reset(to: tick) }
        case .move(let anchor, _, let collapse) where !drag.began:
            if collapse { workspace.selection = [anchor.id] }
        case .move(_, let copies?, _) where drag.began && workspace.sequence.lanes.indices.contains(workspace.laneIndex):
            // A copy dropped where it started would only stack duplicates.
            let originals = drag.original.lanes[workspace.laneIndex].notes.filter { drag.ids.contains($0.id) }
            let placed = workspace.laneNotes.filter { copies.values.contains($0.id) }
            if Set(originals.map { [$0.start, $0.pitch] }) == Set(placed.map { [$0.start, $0.pitch] }) {
                workspace.updateGesture(drag.original)
                workspace.selection = drag.ids
            }
        default:
            break
        }
    }

    private func cancelGridDrag() {
        guard let current = drag else { return }
        if current.began { workspace.updateGesture(current.original) }
        drag = GridDrag(kind: .idle, original: current.original)
        roll.marquee = nil
    }

    // MARK: Ruler and velocity gestures

    private enum RulerDrag {
        case loop(original: NoteSequence, bars: Int, began: Bool)
        case cursor
    }

    private func rulerGesture(_ g: PianoRollGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !roll.multiTouch else { cancelRulerDrag(); return }
                if rulerDrag == nil {
                    let end = g.x(workspace.sequence.length)
                    if abs(value.startLocation.x - end) <= (compact ? 16 : 10) {
                        rulerDrag = .loop(original: workspace.sequence, bars: workspace.sequence.bars, began: false)
                        roll.frozenExtent = currentExtent
                    } else {
                        rulerDrag = .cursor
                    }
                }
                switch rulerDrag {
                case .loop(let original, let bars, let began):
                    let barWidth = CGFloat(original.barTicks) * g.pixelsPerTick
                    let target = min(PianoRollEdit.maximumBars, max(1, bars + Int((value.translation.width / max(1, barWidth)).rounded())))
                    guard target != workspace.sequence.bars || began else { return }
                    if !began { workspace.beginGesture(); rulerDrag = .loop(original: original, bars: bars, began: true) }
                    workspace.updateGesture(PianoRollEdit.withLoop(original, bars: target))
                case .cursor:
                    let tick = roll.snap.floor(g.tick(atX: value.location.x))
                    roll.step.reset(to: min(workspace.sequence.length - 1, max(0, tick)))
                case nil:
                    break
                }
            }
            .onEnded { _ in
                rulerDrag = nil
                roll.frozenExtent = nil
            }
    }

    private func cancelRulerDrag() {
        if case .loop(let original, _, let began) = rulerDrag, began { workspace.updateGesture(original) }
        rulerDrag = nil
        roll.frozenExtent = nil
    }

    private struct VelocityDrag {
        var anchor: UUID?
        var original: NoteSequence
        var originals: [UUID: Int] = [:]
        var began = false
    }

    private func velocityGesture(_ g: PianoRollGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !roll.multiTouch else { cancelVelocityDrag(); return }
                if velocityDrag == nil {
                    let notes = workspace.laneNotes
                    let near = notes.filter { abs(g.x($0.start) + 1.5 - value.startLocation.x) <= 7 }
                    let pick = near.min { a, b in
                        let sa = workspace.selection.contains(a.id), sb = workspace.selection.contains(b.id)
                        if sa != sb { return sa }
                        let ya = abs(PianoRollScene.velocityY(a.velocity, height: metrics.velocity) - value.startLocation.y)
                        let yb = abs(PianoRollScene.velocityY(b.velocity, height: metrics.velocity) - value.startLocation.y)
                        return ya < yb
                    }
                    guard let pick else {
                        velocityDrag = VelocityDrag(anchor: nil, original: workspace.sequence)
                        return
                    }
                    if !workspace.selection.contains(pick.id) { workspace.selection = [pick.id] }
                    velocityDrag = VelocityDrag(anchor: pick.id, original: workspace.sequence,
                                                originals: Dictionary(uniqueKeysWithValues: workspace.selectedNotes.map { ($0.id, $0.velocity) }))
                }
                guard var current = velocityDrag, let anchor = current.anchor, let base = current.originals[anchor] else { return }
                let span = max(1, metrics.velocity - 13)
                let target = base - Int((value.translation.height / span * 127).rounded())
                guard target != base || current.began else { return }
                if !current.began { workspace.beginGesture(); current.began = true; velocityDrag = current }
                workspace.updateGesture(PianoRollEdit.withVelocity(current.original, lane: workspace.laneIndex, originals: current.originals,
                                                                   anchor: anchor, value: target))
            }
            .onEnded { _ in velocityDrag = nil }
    }

    private func cancelVelocityDrag() {
        if let velocityDrag, velocityDrag.began { workspace.updateGesture(velocityDrag.original) }
        velocityDrag = nil
    }

    // MARK: Scroll and zoom

    private func inputHandlers(_ g: PianoRollGeometry) -> PianoRollInputHandlers {
        var handlers = PianoRollInputHandlers()
        handlers.key = { handleKey($0) }
        handlers.modifiers = { modifiers in
            let command = modifiers.contains(.command)
            if roll.commandHeld != command { roll.commandHeld = command }
        }
        handlers.scroll = { dx, dy, modifiers, location in scroll(dx: dx, dy: dy, modifiers: modifiers, at: location, g) }
        handlers.magnify = { amount, location in zoom(by: 1 + amount, atX: location.x - metrics.keyboard, g) }
        handlers.multiTouch = { active in
            roll.multiTouch = active
            if active { cancelGridDrag(); cancelRulerDrag(); cancelVelocityDrag() }
        }
        handlers.release = { releaseEverything(); roll.commandHeld = false }
        return handlers
    }

    private func scroll(dx: CGFloat, dy: CGFloat, modifiers: PianoRollModifiers, at location: CGPoint, _ g: PianoRollGeometry) {
        if modifiers.contains(.option) {
            zoom(by: 1 + dy / 150, atX: location.x - metrics.keyboard, g)
        } else if modifiers.contains(.command) {
            let height = min(PianoRollGeometry.rowHeights.upperBound, max(PianoRollGeometry.rowHeights.lowerBound, g.rowHeight * (1 + dy / 150)))
            let y = min(g.height, max(0, location.y - metrics.ruler))
            let pitchAtPointer = g.topPitch - Double(y / g.rowHeight)
            roll.rowHeight = height
            var next = g
            next.rowHeight = height
            roll.topPitch = next.clampedTopPitch(pitchAtPointer + Double(y / height))
        } else {
            if dy != 0 { roll.topPitch = g.clampedTopPitch(g.topPitch + Double(dy / g.rowHeight)) }
            if dx != 0 { roll.originTick = g.clampedOriginTick(g.originTick - Double(dx / g.pixelsPerTick), extent: currentExtent) }
        }
    }

    private func zoom(by factor: CGFloat, atX x: CGFloat, _ g: PianoRollGeometry) {
        guard factor.isFinite, factor > 0 else { return }
        let extent = currentExtent
        let fit = g.width / CGFloat(max(1, extent))
        let maximum = Double(PianoRollGeometry.maximumPixelsPerTick / max(0.0001, fit))
        let anchor = g.tick(atX: x)
        roll.zoom = min(max(1, maximum), max(1, roll.zoom * Double(factor)))
        var next = g
        next.pixelsPerTick = PianoRollGeometry.pixelsPerTick(width: g.width, extent: extent, zoom: roll.zoom)
        roll.originTick = next.clampedOriginTick(anchor - Double(x / next.pixelsPerTick), extent: extent)
    }

    // MARK: Keys

    private func handleKey(_ event: PianoRollKeyEvent) -> Bool {
        let command = PianoRollCommand.command(for: event.key, modifiers: event.modifiers)
        if !event.isDown {
            if case .key(let character) = event.key, roll.typing.held[character] != nil {
                typingUp(character)
                return true
            }
            return command != nil
        }
        guard let command else { return false }
        if event.isRepeat {
            switch command {
            case .nudge, .transpose: break
            default: return true
            }
        }
        perform(command)
        return true
    }

    private func perform(_ command: PianoRollCommand) {
        switch command {
        case .note(let character): typingDown(character)
        case .octaveDown: _ = roll.typing.keyDown("z")
        case .octaveUp: _ = roll.typing.keyDown("x")
        case .velocityDown: _ = roll.typing.keyDown("c")
        case .velocityUp: _ = roll.typing.keyDown("v")
        case .delete: workspace.deleteSelection()
        case .selectAll: workspace.selectAll()
        case .copy: workspace.copySelection()
        case .cut: workspace.cutSelection()
        case .paste: workspace.paste(at: insertionTick)
        case .duplicate: workspace.duplicateSelection(snap: roll.snap)
        case .undo: workspace.undo()
        case .redo: workspace.redo()
        case .transpose(let semitones):
            workspace.transposeSelection(semitones)
            if let note = workspace.selectedNotes.first { preview(note.pitch, velocity: note.velocity) }
        case .nudge(let steps): workspace.nudgeSelection(by: steps * roll.snap.grid)
        case .quantize: workspace.quantizeSelection(grid: roll.snap == .off ? MusicalTime.ticksPerStep : roll.snap.grid)
        case .playStop: model.toggleSequence(workspace.sequence)
        case .record: toggleRecord()
        case .deselect: workspace.deselectAll(); roll.tool = .pointer
        }
    }

    private var insertionTick: Int {
        if model.isSequencePlaying {
            let tick = roll.snap.round(model.sequencePlayhead)
            return tick >= workspace.sequence.length ? 0 : tick
        }
        return roll.step.cursor
    }

    private func toggleRecord() {
        roll.isRecording.toggle()
        if !roll.isRecording { commitPending(at: HostClock.now) }
    }

    // MARK: Playing

    private func typingDown(_ character: Character) {
        guard case .noteOn(let pitch, let velocity)? = roll.typing.keyDown(character) else { return }
        press(pitch, velocity: velocity, hostTime: HostClock.now)
    }

    private func typingUp(_ character: Character) {
        guard case .noteOff(let pitch)? = roll.typing.keyUp(character), !roll.heldPitches.contains(pitch) else { return }
        release(pitch, hostTime: HostClock.now)
    }

    private func playPointer(_ pitch: Int?) {
        let previous = roll.pointerPitch
        roll.pointerPitch = pitch
        if let previous, previous != pitch, !roll.heldPitches.contains(previous) { release(previous, hostTime: HostClock.now) }
        if let pitch, pitch != previous { press(pitch, velocity: roll.typing.velocity, hostTime: HostClock.now) }
    }

    private func press(_ pitch: Int, velocity: Int, hostTime: UInt64) {
        // Pointer and musical typing can hold the same pitch together.
        guard roll.sounding[pitch] == nil else { return }
        let channel = laneChannel
        roll.previews.removeValue(forKey: PianoRollRecorder.key(channel: channel, pitch: pitch))
        roll.sounding[pitch] = channel
        model.noteOn(channel: channel, note: pitch, velocity: velocity)
        captureOn(pitch: pitch, velocity: velocity, hostTime: hostTime, lane: workspace.laneIndex, channel: channel)
    }

    private func release(_ pitch: Int, hostTime: UInt64) {
        let channel = roll.sounding.removeValue(forKey: pitch) ?? laneChannel
        model.noteOff(channel: channel, note: pitch)
        captureOff(pitch: pitch, hostTime: hostTime, channel: channel)
    }

    /// Plays a placed or moved note briefly, as Logic does (~150 ms).
    private func preview(_ pitch: Int, velocity: Int) {
        guard model.connected, !snapshot, !roll.heldPitches.contains(pitch) else { return }
        let channel = laneChannel
        let key = PianoRollRecorder.key(channel: channel, pitch: pitch)
        let generation = UUID()
        roll.previews[key] = generation
        model.noteOn(channel: channel, note: pitch, velocity: velocity)
        Task { @MainActor [model, roll] in
            try? await Task.sleep(for: .milliseconds(150))
            guard roll.previews[key] == generation else { return }
            roll.previews.removeValue(forKey: key)
            if roll.sounding[pitch] != channel { model.noteOff(channel: channel, note: pitch) }
        }
    }

    private func releaseEverything() {
        let now = HostClock.now
        for pitch in roll.typing.releaseAll() { release(pitch, hostTime: now) }
        if let pitch = roll.pointerPitch { roll.pointerPitch = nil; release(pitch, hostTime: now) }
        for (pitch, channel) in roll.sounding { model.noteOff(channel: channel, note: pitch) }
        roll.sounding = [:]
        for key in roll.previews.keys { model.noteOff(channel: key / 128, note: key % 128) }
        roll.previews = [:]
        commitPending(at: now)
        roll.step.releaseAll(step: roll.snap.step)
        roll.incoming = []
    }

    // MARK: Recording

    private func receive(_ event: MIDIInputEvent) {
        guard case .note(let note) = event else { return }
        let lane = PianoRollRouting.lane(forChannel: note.channel, lanes: workspace.sequence.lanes, current: workspace.laneIndex)
        if lane == workspace.laneIndex {
            if note.isOn { roll.incoming.insert(note.note) } else { roll.incoming.remove(note.note) }
        }
        if note.isOn {
            captureOn(pitch: note.note, velocity: note.velocity, hostTime: note.hostTime, lane: lane, channel: note.channel)
        } else {
            captureOff(pitch: note.note, hostTime: note.hostTime, channel: note.channel)
        }
    }

    private func captureOn(pitch: Int, velocity: Int, hostTime: UInt64, lane: Int, channel: Int) {
        guard roll.isRecording, workspace.sequence.lanes.indices.contains(lane) else { return }
        if model.isSequencePlaying {
            roll.recorder.noteOn(pitch: pitch, velocity: velocity, at: hostTime, channel: channel)
            roll.pendingLane[PianoRollRecorder.key(channel: channel, pitch: pitch)] = lane
            roll.pending = roll.recorder.pending
        } else {
            let newChord = roll.step.held.isEmpty
            let tick = roll.step.press(PianoRollRecorder.key(channel: channel, pitch: pitch))
            guard tick < PianoRollEdit.maximumLoopTicks(workspace.sequence) else { return }
            workspace.record(SequenceNote(pitch: pitch, velocity: velocity, start: tick, duration: roll.snap.step), lane: lane, newStep: newChord)
        }
    }

    private func captureOff(pitch: Int, hostTime: UInt64, channel: Int) {
        let key = PianoRollRecorder.key(channel: channel, pitch: pitch)
        if roll.recorder.pending[key] != nil {
            if let note = roll.recorder.noteOff(pitch: pitch, at: hostTime, grid: roll.snap.grid, channel: channel) {
                workspace.record(note, lane: roll.pendingLane.removeValue(forKey: key) ?? workspace.laneIndex, newStep: !roll.takeOpen)
                roll.takeOpen = true
            }
            roll.pending = roll.recorder.pending
        } else if roll.step.held.contains(key) {
            roll.step.release(key, step: roll.snap.step)
        }
    }

    private func commitPending(at hostTime: UInt64) {
        for pending in roll.recorder.pending.values.sorted(by: { ($0.channel, $0.pitch) < ($1.channel, $1.pitch) }) {
            captureOff(pitch: pending.pitch, hostTime: hostTime, channel: pending.channel)
        }
    }

    private func playbackChanged(_ playing: Bool) {
        if !playing { commitPending(at: HostClock.now) }
        roll.takeOpen = false
        roll.incoming = []
    }
}

// MARK: - Pieces

/// Square tool button drawn by hand (renders in snapshots too).
struct RollToolStyle: ButtonStyle {
    var active = false
    var tint: Color = InstrumentTheme.ink
    var size: CGFloat = 30
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 8)
            .frame(minWidth: size, minHeight: size)
            .foregroundStyle(active ? (tint == InstrumentTheme.ink ? InstrumentTheme.panel : tint) : InstrumentTheme.ink)
            .background(active ? (tint == InstrumentTheme.ink ? InstrumentTheme.ink : tint.opacity(0.14)) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(active && tint != InstrumentTheme.ink ? tint.opacity(0.6) : .clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(enabled ? (configuration.isPressed ? 0.6 : 1) : 0.3)
    }
}

/// Tempo: −/+ or drag the number vertically.
struct PianoRollTempo: View {
    var tempo: Double
    var change: (Double) -> Void
    @State private var dragBase: Double?

    var body: some View {
        HStack(spacing: 0) {
            Button { change(tempo - 1) } label: { Image(systemName: "minus").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(RollToolStyle(size: 24))
            VStack(spacing: 0) {
                Text("\(Int(tempo.rounded()))").font(.system(size: 13, weight: .medium, design: .monospaced))
                Text("BPM").font(.system(size: 7, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(InstrumentTheme.secondary)
            }
            .frame(width: 38).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                let base = dragBase ?? tempo
                dragBase = base
                change(base - Double(value.translation.height / 3).rounded())
            }.onEnded { _ in dragBase = nil })
            Button { change(tempo + 1) } label: { Image(systemName: "plus").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(RollToolStyle(size: 24))
        }
        .padding(2)
        .background(InstrumentTheme.paper.opacity(0.8), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Темп \(Int(tempo)) BPM")
        .accessibilityAdjustableAction { direction in
            change(tempo + (direction == .increment ? 1 : -1))
        }
    }
}

/// Track chips T1…T16 with a miniature of each lane's notes.
struct PianoRollLaneChips: View {
    var lanes: [SequenceLane]
    var current: Int
    var trackNames: [String]?
    var length: Int
    var compact: Bool
    var select: (Int) -> Void

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: compact ? 5 : 6), count: compact ? 8 : 16)
        LazyVGrid(columns: columns, spacing: compact ? 5 : 6) {
            ForEach(0..<WorkspaceModel.laneLimit, id: \.self) { index in
                Button { select(index) } label: { chip(index) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("T\(index + 1) \(name(index))")
                    .accessibilityAddTraits(index == current ? .isSelected : [])
            }
        }
    }

    private func name(_ index: Int) -> String {
        if lanes.indices.contains(index) { return lanes[index].name }
        if let trackNames, trackNames.indices.contains(index) { return trackNames[index] }
        return ""
    }

    private func chip(_ index: Int) -> some View {
        let exists = lanes.indices.contains(index)
        let selected = index == current
        let color = PianoRollPalette.lane(index)
        let foreground = selected ? InstrumentTheme.panel : (exists ? InstrumentTheme.ink : InstrumentTheme.secondary)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(selected ? InstrumentTheme.panel : color).frame(width: 5, height: 5)
                    .opacity(exists ? 1 : 0.5)
                Text("T\(index + 1)").font(.system(size: compact ? 9 : 10, weight: .bold, design: .monospaced))
                if !compact, exists, let lane = lanes[safe: index] {
                    Text("\(lane.channel + 1)").font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(selected ? InstrumentTheme.panel.opacity(0.65) : InstrumentTheme.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            if !compact {
                Text(name(index).isEmpty ? " " : name(index)).font(.system(size: 9)).lineLimit(1)
                    .foregroundStyle(selected ? InstrumentTheme.panel.opacity(0.75) : InstrumentTheme.secondary)
            }
            Canvas { context, size in
                guard let lane = lanes[safe: index], !lane.notes.isEmpty else {
                    var line = Path(); line.move(to: CGPoint(x: 0, y: size.height / 2)); line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    context.stroke(line, with: .color(foreground.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    return
                }
                let range = lane.pitchRange ?? 60...60
                let span = Double(max(1, range.upperBound - range.lowerBound))
                for note in lane.notes {
                    let x = CGFloat(note.start) / CGFloat(max(1, length)) * size.width
                    let width = max(1.5, CGFloat(note.duration) / CGFloat(max(1, length)) * size.width - 0.5)
                    let y = (1 - CGFloat(Double(note.pitch - range.lowerBound) / span)) * (size.height - 2)
                    context.fill(Path(CGRect(x: x, y: y, width: width, height: 2)), with: .color(selected ? InstrumentTheme.panel : color))
                }
            }
            .frame(height: 8)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, compact ? 6 : 7).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? InstrumentTheme.ink : (exists ? InstrumentTheme.panel : Color.clear), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(exists ? InstrumentTheme.line : InstrumentTheme.line, style: StrokeStyle(lineWidth: 1, dash: exists ? [] : [3, 2]))
                .opacity(selected ? 0 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// iPad hardware keyboard: musical typing and commands while the roll has focus.
/// The Mac uses a window event monitor instead (see `PianoRollInputCatcher`).
private struct HardwareKeys: ViewModifier {
    var enabled: Bool
    var focused: FocusState<Bool>.Binding
    var handle: (PianoRollKeyEvent) -> Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        if enabled {
            content
                .focusable()
                .focusEffectDisabled()
                .focused(focused)
                .onKeyPress(phases: .all) { press in
                    PianoRollInputCatcher.lastModifiers = PianoRollModifiers(press.modifiers)
                    guard let event = PianoRollKeyEvent(press) else { return .ignored }
                    return handle(event) ? .handled : .ignored
                }
                .onAppear { focused.wrappedValue = true }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Mac pointer feedback: resize arrows on note ends, crosshair for the pencil.
private struct GridHoverCursor: ViewModifier {
    var geometry: PianoRollGeometry
    var notes: [SequenceNote]
    var selection: Set<UUID>
    var pencil: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onContinuousHover { phase in
            switch phase {
            case .active(let point):
                if case .note(_, let edge) = geometry.hit(point, notes: notes, selected: selection) {
                    (edge ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
                } else {
                    (pencil ? NSCursor.crosshair : NSCursor.arrow).set()
                }
            case .ended:
                NSCursor.arrow.set()
            }
        }
        #else
        content
        #endif
    }
}

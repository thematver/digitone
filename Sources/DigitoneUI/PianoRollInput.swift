import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct PianoRollKeyEvent: Equatable {
    var key: PianoRollKey
    var modifiers: PianoRollModifiers
    var isDown: Bool
    var isRepeat: Bool
}

/// Callbacks from platform input that SwiftUI does not expose directly.
struct PianoRollInputHandlers {
    /// Returns true when the key was used (it is then not passed on).
    var key: (PianoRollKeyEvent) -> Bool = { _ in false }
    var modifiers: (PianoRollModifiers) -> Void = { _ in }
    /// Content offset in points (positive = towards the top/left) at a location in the roll.
    var scroll: (_ dx: CGFloat, _ dy: CGFloat, _ modifiers: PianoRollModifiers, _ location: CGPoint) -> Void = { _, _, _, _ in }
    /// Relative magnification (e.g. 0.05 = 5% larger) at a location in the roll.
    var magnify: (_ amount: CGFloat, _ location: CGPoint) -> Void = { _, _ in }
    /// Touch: two-finger gesture began (true) or ended (false).
    var multiTouch: (Bool) -> Void = { _ in }
    /// Ends held notes when the window/app loses input or the surface detaches.
    var release: () -> Void = {}
}

#if os(macOS)
extension PianoRollModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var value: PianoRollModifiers = []
        if flags.contains(.shift) { value.insert(.shift) }
        if flags.contains(.command) { value.insert(.command) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.control) { value.insert(.control) }
        self = value
    }

    @MainActor static var current: PianoRollModifiers { PianoRollModifiers(NSEvent.modifierFlags) }
}

/// Installs window-scoped event monitors while the roll is on screen: keys
/// (musical typing and commands) unless a text field is editing, and scroll
/// and pinch over the roll's own frame.
struct PianoRollInputCatcher: NSViewRepresentable {
    var handlers: PianoRollInputHandlers

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.handlers = handlers
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.handlers = handlers }

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) { view.removeMonitor() }

    final class CatcherView: NSView {
        var handlers = PianoRollInputHandlers()
        private var monitor: Any?
        private var observers: [NSObjectProtocol] = []
        private var keys = PianoRollKeyOwnership()

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard let window else { return }
            let center = NotificationCenter.default
            for (name, object) in [(NSWindow.didResignKeyNotification, window as AnyObject?),
                                   (NSWindow.willCloseNotification, window as AnyObject?),
                                   (NSWindow.willBeginSheetNotification, window as AnyObject?),
                                   (NSApplication.didResignActiveNotification, nil)] {
                observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.releaseInput() }
                })
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .scrollWheel, .magnify]) { [weak self] event in
                // Local monitors run on the main thread.
                nonisolated(unsafe) let event = event
                let consumed = MainActor.assumeIsolated { self?.consumes(event) ?? false }
                return consumed ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers = []
            releaseInput()
        }

        private func releaseInput() {
            keys.releaseAll()
            handlers.modifiers([])
            handlers.release()
        }

        /// True when the roll used the event, which then goes no further.
        private func consumes(_ event: NSEvent) -> Bool {
            guard let window, event.window === window, !isHiddenOrHasHiddenAncestor else { return false }
            switch event.type {
            case .keyDown, .keyUp:
                guard let key = PianoRollKey(keyCode: event.keyCode) else { return false }
                let input = PianoRollKeyEvent(key: key, modifiers: PianoRollModifiers(event.modifierFlags),
                                             isDown: event.type == .keyDown, isRepeat: event.type == .keyDown && event.isARepeat)
                // A key released after text focus changes must still end its note.
                if !input.isDown {
                    guard keys.release(key) else { return false }
                    _ = handlers.key(input)
                    return true
                }
                if window.attachedSheet != nil || ((window.firstResponder as? NSText)?.isEditable ?? false) {
                    releaseInput()
                    return false
                }
                let consumed = handlers.key(input)
                if consumed { keys.press(key) }
                return consumed
            case .flagsChanged:
                handlers.modifiers(PianoRollModifiers(event.modifierFlags))
                return false
            case .scrollWheel:
                let point = convert(event.locationInWindow, from: nil)
                guard bounds.contains(point) else { return false }
                let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
                handlers.scroll(event.scrollingDeltaX * scale, event.scrollingDeltaY * scale, PianoRollModifiers(event.modifierFlags), point)
                return true
            case .magnify:
                let point = convert(event.locationInWindow, from: nil)
                guard bounds.contains(point) else { return false }
                handlers.magnify(event.magnification, point)
                return true
            default:
                return false
            }
        }
    }
}
#else
extension PianoRollModifiers {
    init(_ modifiers: EventModifiers) {
        var value: PianoRollModifiers = []
        if modifiers.contains(.shift) { value.insert(.shift) }
        if modifiers.contains(.command) { value.insert(.command) }
        if modifiers.contains(.option) { value.insert(.option) }
        if modifiers.contains(.control) { value.insert(.control) }
        self = value
    }

    @MainActor static var current: PianoRollModifiers { PianoRollInputCatcher.lastModifiers }
}

extension PianoRollKeyEvent {
    /// A hardware-keyboard press on iPad.
    init?(_ press: KeyPress) {
        let key: PianoRollKey?
        switch press.key {
        case .space: key = .space
        case .delete, .deleteForward: key = .delete
        case .escape: key = .escape
        case .leftArrow: key = .left
        case .rightArrow: key = .right
        case .upArrow: key = .up
        case .downArrow: key = .down
        default: key = PianoRollKey(character: press.characters.isEmpty ? String(press.key.character) : press.characters)
        }
        guard let key else { return nil }
        self.init(key: key, modifiers: PianoRollModifiers(press.modifiers), isDown: press.phase != .up, isRepeat: press.phase == .repeat)
    }
}

/// Two-finger scroll and pinch over the roll, recognised on the window next
/// to SwiftUI's single-finger editing gestures.
struct PianoRollInputCatcher: UIViewRepresentable {
    var handlers: PianoRollInputHandlers
    @MainActor static var lastModifiers: PianoRollModifiers = []

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.handlers = handlers
        return view
    }

    func updateUIView(_ view: CatcherView, context: Context) { view.handlers = handlers }

    static func dismantleUIView(_ view: CatcherView, coordinator: ()) { view.detach() }

    final class CatcherView: UIView, UIGestureRecognizerDelegate {
        var handlers = PianoRollInputHandlers()
        private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        private lazy var pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        private weak var host: UIView?
        private weak var pageScroll: UIScrollView?
        private var lastTranslation = CGPoint.zero
        private var lastScale: CGFloat = 1

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            guard let window else { return }
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
            for recognizer in [pan, pinch] as [UIGestureRecognizer] {
                recognizer.cancelsTouchesInView = false
                recognizer.delaysTouchesBegan = false
                recognizer.delegate = self
                window.addGestureRecognizer(recognizer)
            }
            host = window
            var view = superview
            while let current = view, !(current is UIScrollView) { view = current.superview }
            pageScroll = view as? UIScrollView
        }

        func detach() {
            host?.removeGestureRecognizer(pan)
            host?.removeGestureRecognizer(pinch)
            host = nil
            pageScroll?.isScrollEnabled = true
            handlers.release()
            handlers.multiTouch(false)
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            bounds.contains(touch.location(in: self))
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                lastTranslation = .zero
                pageScroll?.isScrollEnabled = false
                handlers.multiTouch(true)
            case .changed:
                let translation = recognizer.translation(in: self)
                handlers.scroll(translation.x - lastTranslation.x, translation.y - lastTranslation.y, [], recognizer.location(in: self))
                lastTranslation = translation
            default:
                pageScroll?.isScrollEnabled = true
                handlers.multiTouch(false)
            }
        }

        @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began:
                lastScale = 1
                handlers.multiTouch(true)
            case .changed:
                handlers.magnify(recognizer.scale / lastScale - 1, recognizer.location(in: self))
                lastScale = recognizer.scale
            default:
                handlers.multiTouch(false)
            }
        }
    }
}
#endif

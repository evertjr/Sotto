import AppKit
import ObjectiveC
import SwiftUI

/// Liquid Glass for the island, through AppKit's `NSGlassEffectView` instead of SwiftUI's
/// `glassEffect`, so it can use the clearer presets Apple uses for its own surfaces.
///
/// The public API only offers `.regular` and `.clear`, and both render frosted in a window that's
/// never key, which our island panel never is. The private `_variant`, `_subvariant` and `_setPath:`
/// selectors pick a refracting preset and give the glass our exact outline. They're looked up at
/// runtime and their type encodings checked before every call, so if Apple renames or retypes them
/// the glass quietly stays the public clear style instead of crashing.
///
/// Private API: fine for direct distribution, not for the Mac App Store.
struct IslandGlass: NSViewRepresentable {
    /// Apple's internal `GlassMaterialProvider.Variant` numbering, as of macOS 27.2. `bubbles` (11)
    /// is the only preset with strong refraction and a lit rim. `loupe` (20) barely refracts, and
    /// `dock` (2), `avplayer` (6) and `controlCenter` (8) render flat in our panel.
    private static let variant = 11
    /// The glass Siri uses for its answer cards, which matches Siri's look best.
    private static let subvariant = "siriSnippet"

    /// The glass outline for a given frame, in SwiftUI's top-left coordinates.
    let outline: (CGRect) -> Path

    func makeNSView(context: Context) -> IslandGlassView {
        let view = IslandGlassView()
        view.style = .clear
        PrivateGlass.set(.integer(Self.variant), selector: "set_variant:", on: view)
        PrivateGlass.set(.object(Self.subvariant as NSString), selector: "set_subvariant:", on: view)
        view.outline = outline
        return view
    }

    func updateNSView(_ view: IslandGlassView, context: Context) {
        view.outline = outline
        view.applyOutline()
    }
}

final class IslandGlassView: NSGlassEffectView {
    var outline: ((CGRect) -> Path)?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        applyOutline()
    }

    func applyOutline() {
        guard let outline, bounds.width > 0, bounds.height > 0 else { return }
        // SwiftUI paths grow downward, AppKit's coordinates grow upward.
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height)
        if let path = outline(bounds).cgPath.copy(using: &flip),
           PrivateGlass.set(.path(path), selector: "_setPath:", on: self) {
            return
        }
        // Without the private path, a capsule is the closest public outline.
        cornerRadius = min(bounds.width, bounds.height) / 2
    }
}

// MARK: - Runtime

/// Calls private `NSGlassEffectView` setters through the Objective-C runtime. Calling an IMP with
/// the wrong signature crashes, so a selector's existence is never trusted on its own: its argument
/// count and type encodings are checked first.
private enum PrivateGlass {
    enum Argument {
        case integer(Int)
        case object(AnyObject)
        case path(CGPath)

        /// `NSInteger` is `q` on 64-bit. Narrower integer encodings are rejected, so a call can
        /// never write the wrong register width.
        func accepts(_ encoding: String) -> Bool {
            switch self {
            case .integer: encoding == "q" || encoding == "Q"
            case .object: encoding == "@"
            case .path: encoding.hasSuffix("^{CGPath=}")
            }
        }
    }

    private typealias IntegerSetter = @convention(c) (AnyObject, Selector, Int) -> Void
    private typealias ObjectSetter = @convention(c) (AnyObject, Selector, AnyObject) -> Void
    private typealias PathSetter = @convention(c) (AnyObject, Selector, CGPath) -> Void

    /// Returns false when the selector is missing or its signature doesn't match.
    @discardableResult
    static func set(_ argument: Argument, selector name: String, on object: NSObject) -> Bool {
        let selector = NSSelectorFromString(name)
        guard let cls = object_getClass(object),
              let method = class_getInstanceMethod(cls, selector),
              method_getNumberOfArguments(method) == 3,
              returnEncoding(of: method) == "v",
              let argumentEncoding = argumentEncoding(at: 2, of: method),
              argument.accepts(argumentEncoding) else {
            return false
        }

        let implementation = method_getImplementation(method)
        switch argument {
        case .integer(let value):
            unsafeBitCast(implementation, to: IntegerSetter.self)(object, selector, value)
        case .object(let value):
            unsafeBitCast(implementation, to: ObjectSetter.self)(object, selector, value)
        case .path(let value):
            unsafeBitCast(implementation, to: PathSetter.self)(object, selector, value)
        }
        return true
    }

    private static func returnEncoding(of method: Method) -> String {
        let type = method_copyReturnType(method)
        defer { free(type) }
        return String(cString: type)
    }

    private static func argumentEncoding(at index: UInt32, of method: Method) -> String? {
        guard let type = method_copyArgumentType(method, index) else { return nil }
        defer { free(type) }
        return String(cString: type)
    }
}

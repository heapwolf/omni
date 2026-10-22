// src/lib/components/apple/Canvas+Apple.swift
#if os(macOS) || os(iOS)
import Foundation

#if os(macOS)
import AppKit
import CoreGraphics
#elseif os(iOS)
import UIKit
import CoreGraphics
#endif

#if os(macOS)
public class OmniCanvasView: NSView {
    nonisolated public override var isFlipped: Bool { true }

    var commands: [DrawCommand] = []

    // Trigger redraw when system dark/light mode switches
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        Canvas.executeApple(commands: commands, in: ctx)
    }
}
#elseif os(iOS)
public class OmniCanvasView: UIView {
    var commands: [DrawCommand] = []

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        // Drawn again at each new size. UIKit's default stretches what was
        // drawn before: a canvas first drawn before it had its size (a tab's
        // first appearance, the card art) stayed blank.
        self.contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError() }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsDisplay()
    }

    public override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        Canvas.executeApple(commands: commands, in: ctx)
    }
}
#endif

extension Canvas {
    @MainActor public func makeNative() -> NativeView {
        let v = OmniCanvasView()
        #if os(macOS)
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        #elseif os(iOS)
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        #endif
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    @MainActor public func updateNative(_ view: NativeView) {
        let ctx = DrawContext()
        drawClosure(ctx)

        if let v = view as? OmniCanvasView {
            v.commands = ctx.commands
            #if os(macOS)
            v.needsDisplay = true
            #elseif os(iOS)
            v.setNeedsDisplay()
            #endif
        }
    }

    static func executeApple(commands: [DrawCommand], in ctx: CGContext) {
        ctx.setLineWidth(2.0)

        for cmd in commands {
            switch cmd {
            case .beginPath:
                ctx.beginPath()
            case .moveTo(let x, let y):
                ctx.move(to: CGPoint(x: x, y: y))
            case .lineTo(let x, let y):
                ctx.addLine(to: CGPoint(x: x, y: y))
            case .addCurve(let c1x, let c1y, let c2x, let c2y, let x, let y):
                ctx.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: c1x, y: c1y), control2: CGPoint(x: c2x, y: c2y))
            case .setStrokeColor(let color):
                #if os(macOS)
                ctx.setStrokeColor(color.nsColor.cgColor)
                #elseif os(iOS)
                ctx.setStrokeColor(color.uiColor.cgColor)
                #endif
            case .setFillColor(let color):
                #if os(macOS)
                ctx.setFillColor(color.nsColor.cgColor)
                #elseif os(iOS)
                ctx.setFillColor(color.uiColor.cgColor)
                #endif
            case .setLineWidth(let width):
                ctx.setLineWidth(width)
            case .stroke:
                ctx.strokePath()
            case .fill:
                ctx.fillPath()
            }
        }
    }
}
#endif

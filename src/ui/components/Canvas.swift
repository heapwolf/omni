// src/lib/components/Canvas.swift
import Foundation

public enum DrawCommand {
    case beginPath
    case moveTo(Double, Double)
    case lineTo(Double, Double)
    case addCurve(Double, Double, Double, Double, Double, Double)
    case setStrokeColor(Color) // 💡 Accepts Color
    case setLineWidth(Double)
    case setFillColor(Color)   // 💡 Accepts Color
    case stroke
    case fill
}

public class DrawContext {
    var commands: [DrawCommand] = []

    public func beginPath() { commands.append(.beginPath) }
    public func moveTo(x: Double, y: Double) { commands.append(.moveTo(x, y)) }
    public func lineTo(x: Double, y: Double) { commands.append(.lineTo(x, y)) }
    public func addCurve(cp1x: Double, cp1y: Double, cp2x: Double, cp2y: Double, x: Double, y: Double) {
        commands.append(.addCurve(cp1x, cp1y, cp2x, cp2y, x, y))
    }
    public func setLineWidth(width: Double) { commands.append(.setLineWidth(width)) }
    public func stroke() { commands.append(.stroke) }
    public func fill() { commands.append(.fill) }

    // 💡 Primary Color APIs
    public func setFillColor(_ color: Color) { commands.append(.setFillColor(color)) }
    public func setStrokeColor(_ color: Color) { commands.append(.setStrokeColor(color)) }

    // Convenience RGBA overloads
    public func setFillColor(r: Double, g: Double, b: Double, a: Double = 1.0) {
        setFillColor(.rgba(r: r, g: g, b: b, a: a))
    }
    public func setStrokeColor(r: Double, g: Double, b: Double, a: Double = 1.0) {
        setStrokeColor(.rgba(r: r, g: g, b: b, a: a))
    }
}

public struct Canvas: NativeComponent {
    public var drawClosure: (DrawContext) -> Void
    public var body: any View { self }

    public init(_ drawClosure: @escaping (DrawContext) -> Void) {
        self.drawClosure = drawClosure
    }
}

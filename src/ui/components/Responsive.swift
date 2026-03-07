// src/lib/components/Responsive.swift
import Foundation

public struct Responsive: View {
    public var breakpoints: [Double]
    public var content: (GeometryProxy) -> any View

    @State private var measured = GeometryProxy(width: 0, height: 0)

    /// - Parameter breakpoints: widths, in points, where the layout changes.
    @MainActor public init(breakpoints: [Double] = [600],
                @ViewBuilder content: @escaping (GeometryProxy) -> any View) {
        self.breakpoints = breakpoints.sorted()
        self.content = content
    }

    /// How many breakpoints this width is past; the band it falls in.
    private func band(_ width: Double) -> Int {
        breakpoints.reduce(0) { $0 + (width >= $1 ? 1 : 0) }
    }

    @MainActor public var body: some View {
        let currentBand = band(measured.width)
        return GeometryReader(onResize: { proxy in
            guard band(proxy.width) != currentBand else { return }
            measured = proxy
        }) {
            content(measured)
        }
    }
}

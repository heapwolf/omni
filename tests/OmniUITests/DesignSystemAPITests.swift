#if os(macOS)
import XCTest
import AppKit
import CoreText
@testable import OmniUI

// The SwiftUI API a design system leans on: figures of one width, flexible
// frames, accessibility, selectable and redacted text, timelines, springs,
// implicit animation and glass.

@MainActor private var animationsSeen: [Animation?] = []
@MainActor private var flip: Binding<Bool>?

/// Records the animation in force each time its content renders.
private struct Probe: View {
    var body: some View {
        animationsSeen.append(Transaction.currentAnimation)
        return Text("probe")
    }
}

@MainActor private var ticks: [Date] = []

private struct Tick: View {
    let date: Date
    var body: some View {
        ticks.append(date)
        return Text("tick")
    }
}

private struct Animated: View {
    @State private var isOn = false
    var body: some View {
        flip = $isOn
        // Inside a stack, as a style's body puts it: flattened, it never animated.
        return VStack { VStack { Probe() }.animation(.spring(response: 0.3, dampingFraction: 0.8), value: isOn) }
    }
}

final class DesignSystemAPITests: XCTestCase {

    @MainActor private static func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let found = find(type, in: subview) { return found }
        }
        return nil
    }

    /// In drawing order: depth first.
    @MainActor private static func findAll<T: NSView>(_ type: T.Type, in view: NSView?) -> [T] {
        guard let view else { return [] }
        let inside = view.subviews.flatMap { findAll(type, in: $0) }
        if let match = view as? T { return [match] + inside }
        return inside
    }

    @MainActor private static func label(_ view: some View) -> NSTextField? {
        let node = Node(view)
        Engine.render(node)
        return find(NSTextField.self, in: node.native)
    }

    func testMonospacedDigitAsksTheFaceForTabularFigures() {
        MainActor.assumeIsolated {
            let font = Self.label(Text("1,234.50").monospacedDigit().font(.body))?.font
            let settings = font?.fontDescriptor.object(forKey: .featureSettings) as? [[NSFontDescriptor.FeatureKey: Int]]
            XCTAssertEqual(settings?.first?[.typeIdentifier], kNumberSpacingType,
                           "a later .font() dropped .monospacedDigit()")
            XCTAssertEqual(settings?.first?[.selectorIdentifier], kMonospacedNumbersSelector)
        }
    }

    func testAMinimumHeightIsAFloorNotAFixedSize() {
        MainActor.assumeIsolated {
            let node = Node(Text("x").frame(minHeight: 50))
            Engine.render(node)
            let floor = node.native?.constraints.first {
                $0.firstAttribute == .height && $0.relation == .greaterThanOrEqual
            }
            XCTAssertEqual(floor?.constant, 50)
            XCTAssertNil(node.native?.constraints.first {
                $0.firstAttribute == .height && $0.relation == .equal && $0.identifier == "Mod-Height"
            })
        }
    }

    func testAMinimumDoesNotTakeAStacksSurplus() {
        MainActor.assumeIsolated {
            let node = Node(VStack(spacing: 0) {
                Spacer()
                Text("Get Started").frame(maxWidth: .infinity, minHeight: 54)
            })
            Engine.render(node)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 600),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            let root = node.native!
            window.contentView?.addSubview(root)
            NSLayoutConstraint.activate([
                root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
                root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
                root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
                root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor)
            ])
            window.contentView?.layoutSubtreeIfNeeded()
            let field = Self.find(NSTextField.self, in: root)
            let frame = field?.superview
            XCTAssertEqual(frame?.frame.height ?? 0, 54, accuracy: 0.5, "the minimum took the Spacer's room")
            _ = window
        }
    }

    /// SwiftUI centres text in a frame wider than it: a segmented control's
    /// two halves, each `.frame(maxWidth: .infinity)`. Stretched to the frame,
    /// the label drew its text at the leading edge.
    func testTextInAFlexibleFrameIsCentred() {
        MainActor.assumeIsolated {
            let node = Node(HStack(spacing: 0) {
                Text("Virtual").foregroundColor(.black).frame(maxWidth: .infinity).frame(height: 36)
                Text("Physical").frame(maxWidth: .infinity, alignment: .leading)
            })
            Engine.render(node)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            let root = node.native!
            window.contentView?.addSubview(root)
            NSLayoutConstraint.activate([
                root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
                root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
                root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor)
            ])
            window.contentView?.layoutSubtreeIfNeeded()
            let labels = Self.findAll(NSTextField.self, in: root)
            XCTAssertEqual(labels.count, 2)
            guard labels.count == 2 else { return }
            let virtual = labels[0].convert(labels[0].bounds, to: root)
            let physical = labels[1].convert(labels[1].bounds, to: root)
            XCTAssertEqual(virtual.midX, 100, accuracy: 1, "centred in its half")
            XCTAssertLessThan(virtual.width, 150, "its own width, not the half's")
            XCTAssertEqual(physical.minX, 200, accuracy: 3, "a leading frame still puts it at the edge")
            _ = window
        }
    }

    /// .offset moves a view where it is drawn, and a click finds it there: a
    /// carousel's two cards, each offset across a full-width row, no longer
    /// take each other's clicks. AppKit hit-tests frames, not layer transforms.
    func testAnOffsetViewIsClickedWhereItIsDrawn() {
        MainActor.assumeIsolated {
            let node = Node(ZStack {
                HStack(spacing: 0) { Text("first").frame(width: 100, height: 50); Spacer() }
                HStack(spacing: 0) { Text("second").frame(width: 100, height: 50); Spacer() }.offset(x: 200, y: 0)
            }.frame(width: 400, height: 50))
            Engine.render(node)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 50),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            let root = node.native!
            window.contentView?.addSubview(root)
            NSLayoutConstraint.activate([
                root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
                root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor)
            ])
            window.contentView?.layoutSubtreeIfNeeded()
            let shifted = Self.findAll(OmniModifierView.self, in: root).first { $0.customOffsetX == 200 }
            guard let shifted else { return XCTFail("no offset view") }
            let content = window.contentView!
            // The first card, at x 50: under the second card's untransformed row.
            let first = content.hitTest(content.convert(NSPoint(x: 50, y: 25), to: content.superview))
            XCTAssertFalse(first.map { $0 === shifted || $0.isDescendant(of: shifted) } ?? false,
                           "the offset row took a click on the card beside it")
            let second = content.hitTest(content.convert(NSPoint(x: 250, y: 25), to: content.superview))
            XCTAssertTrue(second.map { $0 === shifted || $0.isDescendant(of: shifted) } ?? false,
                          "the offset card is not clicked where it is drawn")
            _ = window
        }
    }

    func testStackedAccessibilityModifiersAllLand() {
        MainActor.assumeIsolated {
            let node = Node(HStack { Text("Ada"); Text("Lovelace") }
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens the account"))
            Engine.render(node)
            XCTAssertEqual(node.native?.accessibilityLabel(), "Ada, Lovelace")
            XCTAssertEqual(node.native?.accessibilityHelp(), "Opens the account")
            XCTAssertEqual(node.native?.isAccessibilityElement(), true)
        }
    }

    /// Inside a stack, whose children are flattened: the carrier must survive.
    func testALabelOnAStacksChildLands() {
        MainActor.assumeIsolated {
            let text = Binding(get: { "" }, set: { _ in })
            let node = Node(HStack { TextField("x", text: text).accessibilityLabel("Email") })
            Engine.render(node)
            XCTAssertEqual(Self.find(NSTextField.self, in: node.native)?.accessibilityLabel(), "Email")
        }
    }

    func testAnExplicitLabelWinsOverTheText() {
        MainActor.assumeIsolated {
            let node = Node(HStack { Text("x") }.accessibilityLabel("Copy account number"))
            Engine.render(node)
            XCTAssertEqual(node.native?.accessibilityLabel(), "Copy account number")
        }
    }

    func testTextSelectionReachesTheLabelsUnderIt() {
        MainActor.assumeIsolated {
            XCTAssertEqual(Self.label(VStack { Text("0123456789") }.textSelection(.enabled))?.isSelectable, true)
            XCTAssertEqual(Self.label(VStack { Text("0123456789") })?.isSelectable, false)
        }
    }

    func testRedactedTextKeepsItsSizeAndDrawsABlock() {
        MainActor.assumeIsolated {
            guard let field = Self.label(VStack { Text("Balance") }.redacted(reason: .placeholder)) else {
                return XCTFail("no label")
            }
            XCTAssertEqual(field.stringValue, "Balance", "the text is kept, for its size")
            XCTAssertEqual(field.textColor, .clear)
            XCTAssertNotNil(field.layer?.backgroundColor)
        }
    }

    func testAPeriodicScheduleCountsFromItsStart() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let schedule = PeriodicTimelineSchedule.periodic(from: start, by: 1)
        XCTAssertEqual(schedule.nextDate(after: start.addingTimeInterval(0.4)), start.addingTimeInterval(1))
        XCTAssertEqual(schedule.nextDate(after: start.addingTimeInterval(1)), start.addingTimeInterval(2))
        XCTAssertEqual(schedule.nextDate(after: start.addingTimeInterval(-5)), start)
    }

    func testATimelineRendersAgainOnItsSchedule() {
        MainActor.assumeIsolated {
            ticks = []
            let node = Node(TimelineView(.periodic(from: .now, by: 0.05)) { context in
                Tick(date: context.date)
            })
            Engine.render(node)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            XCTAssertGreaterThanOrEqual(ticks.count, 3, "the timeline did not tick")
            XCTAssertEqual(ticks, ticks.sorted(), "a tick went back in time")
        }
    }

    func testASpringTakesSwiftUIsNumbers() {
        let spring = Animation.spring(response: 0.36, dampingFraction: 0.86)
        XCTAssertEqual(spring.curve, .spring(response: 0.36, dampingFraction: 0.86))
        XCTAssertGreaterThan(spring.duration, 0.2)
        XCTAssertEqual(spring.androidCurve, 1860)
        XCTAssertEqual(Animation.spring(duration: 0.5, bounce: 0.3).curve,
                       .spring(response: 0.5, dampingFraction: 0.7))
    }

    func testImplicitAnimationWrapsOnlyAChangeOfItsValue() {
        MainActor.assumeIsolated {
            animationsSeen = []
            let node = Node(Animated())
            Engine.render(node)
            XCTAssertEqual(animationsSeen.last ?? nil, nil, "the first render animated")
            flip?.wrappedValue = true
            XCTAssertEqual(animationsSeen.last ?? nil, .spring(response: 0.3, dampingFraction: 0.8))
            Engine.render(node)
            XCTAssertEqual(animationsSeen.last ?? nil, nil, "a render with the same value animated")
        }
    }

    func testGlassAndMaterialsDrawAnEffectBehindTheirContent() {
        MainActor.assumeIsolated {
            let glass = Node(Text("Glass").glassEffect())
            Engine.render(glass)
            let effect = glass.native as? OmniEffectView
            XCTAssertNotNil(effect)
            XCTAssertNotNil(Self.find(NSTextField.self, in: effect), "the content is not inside the effect")
            if #available(macOS 26.0, *) {
                XCTAssertNotNil(Self.find(NSGlassEffectView.self, in: effect))
            } else {
                XCTAssertNotNil(Self.find(NSVisualEffectView.self, in: effect))
            }

            let material = Node(Text("Blur").background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)))
            Engine.render(material)
            XCTAssertNotNil(Self.find(NSVisualEffectView.self, in: material.native))
        }
    }
}
#endif

import OmniUI

// Glass, materials, a styled button's press, springs and haptics: the pieces a
// design system is built from. Glass needs something behind it, so this
// screen puts it over a gradient.

/// A pill that shows its own press: darker, smaller, and a soft tap as it goes down.
struct PressPillStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        AnyView(configuration.label)
            .padding(horizontal: 24, vertical: 14)
            .background(configuration.isPressed ? .rgba(r: 0.78, g: 0.78, b: 0.8) : .rgba(r: 0.96, g: 0.96, b: 0.97))
            .cornerRadius(25)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.9), value: configuration.isPressed)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: configuration.isPressed) { _, down in down }
    }
}

struct DesignScreen: View {
    @State private var presses = 0
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(colors: [.rgba(r: 0.23, g: 0.54, b: 1), .rgba(r: 0.91, g: 1, b: 0.35),
                                    .rgba(r: 0.83, g: 0.69, b: 0.42)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            VStack(spacing: 20) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Glass").padding(horizontal: 18, vertical: 10).glassEffect()
                        Text("Clear").padding(horizontal: 18, vertical: 10).glassEffect(.clear)
                        Text("Tinted").padding(horizontal: 18, vertical: 10)
                            .glassEffect(.regular.tint(.rgba(r: 0.83, g: 0.69, b: 0.42)).interactive())
                    }
                }

                Text("Ultra-thin material").padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                Button(action: { presses += 1 }) {
                    Text("Pressed \(presses) times").font(.headline)
                        .foregroundColor(.rgba(r: 0.05, g: 0.05, b: 0.06))
                }
                .buttonStyle(PressPillStyle())
                .sensoryFeedback(.success, trigger: presses)

                Button(action: { isExpanded.toggle() }) {
                    Text(isExpanded ? "Spring back" : "Spring out").font(.headline)
                        .foregroundColor(.rgba(r: 0.05, g: 0.05, b: 0.06))
                }
                .buttonStyle(PressPillStyle())

                Text("Spring").padding(horizontal: 20, vertical: 10).glassEffect()
                    .offset(x: isExpanded ? 80 : -80, y: 0)
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .bouncy, value: isExpanded)

                Text(reduceMotion ? "Reduce Motion is on" : "Reduce Motion is off").font(.caption)
            }
            .padding(20)
        }
    }
}

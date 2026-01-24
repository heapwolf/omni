import OmniUI
@main
struct SmokeApp: App {
    @State var count = 0
    @State var isOn = false
    var window = WindowConfig(title: "Omni Linux Smoke", width: 420, height: 240)
    var body: some View {
        VStack(spacing: 12) {
            Text("Hello from Omni on Linux")
            Text("count = \(count)")
            Button("Tap me", action: { count += 1 })
            Toggle("Toggled: \(isOn)", isOn: $isOn)
        }
    }
}

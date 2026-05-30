import OmniUI
import OmniCamera
import OmniKeychain
import Foundation

// A small mail client, used as the framework's manual test app. It is shaped
// like a real application — header, scrolling content, bottom tab bar — because
// a flat list of widgets tells you very little about whether layout, nesting
// and state actually work.
//
// Between the three screens every component is exercised in a realistic
// position rather than in isolation.

// MARK: - Model

struct Message {
    let id: Int
    let sender: String
    let subject: String
    let preview: String
    let unread: Bool
}

let inbox = [
    Message(id: 1, sender: "Ada Lovelace", subject: "Analytical engine notes",
            preview: "The engine weaves algebraic patterns…", unread: true),
    Message(id: 2, sender: "Grace Hopper", subject: "Found a bug",
            preview: "Literally. It was a moth in relay 70.", unread: true),
    Message(id: 3, sender: "Alan Turing", subject: "On computable numbers",
            preview: "With an application to the decision problem.", unread: false),
    Message(id: 4, sender: "Barbara Liskov", subject: "Substitution",
            preview: "Subtypes must be substitutable for their base.", unread: false),
]

// MARK: - Shared pieces

struct Avatar: View {
    let initials: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle().fill(tint)
            Text(initials).font(.headline).foregroundColor(.rgba(r: 1, g: 1, b: 1, a: 1))
        }
        .frame(width: 40, height: 40)
    }
}

struct HeaderBar: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.largeTitle)
                    Text(subtitle).font(.caption).foregroundColor(.secondaryText)
                }
                Spacer()
                Image(systemName: "star").foregroundColor(.blue)
            }
            .padding(horizontal: 16, vertical: 14)
            Divider()
        }
        .background(.windowBackground)
    }
}

// MARK: - Inbox

struct MessageDetail: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message.subject).font(.title)
            HStack {
                Avatar(initials: String(message.sender.prefix(1)), tint: .blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.sender).font(.headline)
                    Text("message-id: \(message.id)").monospaced().font(.caption).foregroundColor(.secondaryText)
                }
                Spacer()
            }
            Divider()
            Text(message.preview)
        }
        .padding(16)
    }
}

// The sender name is the tappable element rather than the whole row, because
// Button (and so NavigationLink) only renders a plain Text label — a richer
// label is discarded and replaced with the word "Button".
struct MessageRow: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(initials: String(message.sender.prefix(1)),
                   tint: message.unread ? .blue : .gray)
            VStack(alignment: .leading, spacing: 3) {
                NavigationLink(message.sender,
                               destination: MessageDetail(message: message))
                Text(message.subject).font(.headline)
                Text(message.preview)
                    .font(.caption)
                    .foregroundColor(.secondaryText)
                    .truncationMode(.tail, lineLimit: 1)
            }
            Spacer()
        }
        .padding(horizontal: 16, vertical: 12)
    }
}

struct InboxScreen: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(inbox.filter(\.unread).count) unread")
                    .font(.caption)
                    .foregroundColor(.secondaryText)
                    .padding(horizontal: 16, vertical: 10)
                List {
                    ForEach(inbox, id: \.id) { message in
                        VStack(alignment: .leading, spacing: 0) {
                            MessageRow(message: message)
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Compose

struct ComposeScreen: View {
    @Binding var recipient: String
    @Binding var subject: String
    @Binding var body_: String
    @Binding var urgent: Bool
    @Binding var priority: Double
    @Binding var folder: Int
    @Binding var sent: Int
    @Binding var showAlert: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New message").font(.title)

            VStack(alignment: .leading, spacing: 6) {
                TextField($recipient, placeholder: "Recipient")
                TextField($subject, placeholder: "Subject")
                TextEditor(text: $body_)
            }

            // Toggle/Picker's own title isn't rendered on iOS today, so the
            // visible label comes from this sibling Text instead.
            HStack {
                Text("Mark urgent")
                Spacer()
                Toggle("Mark urgent", isOn: $urgent)
            }

            HStack {
                Text("Priority").font(.caption).foregroundColor(.secondaryText)
                Slider(value: $priority, in: 0...1)
            }

            // Unlike Toggle, Picker already renders its own title + Spacer
            // internally (see Picker.swift's body) — wrapping it in another
            // one duplicated the label.
            Picker("Folder", selection: $folder) {
                Text("Drafts").tag(0)
                Text("Scheduled").tag(1)
                Text("Outbox").tag(2)
            }

            Divider()

            Button("Send (\(sent) sent)", action: { sent += 1; showAlert = true })
                .foregroundColor(.rgba(r: 1, g: 1, b: 1, a: 1))
                .padding(horizontal: 20, vertical: 12)
                .background(.blue)
        }
        .padding(16)
    }
}

// MARK: - Profile

struct ActivityChart: View {
    var body: some View {
        Canvas { ctx in
            ctx.setStrokeColor(.blue)
            ctx.setLineWidth(width: 2)
            ctx.beginPath()
            ctx.moveTo(x: 0, y: 40)
            ctx.lineTo(x: 40, y: 15)
            ctx.lineTo(x: 80, y: 30)
            ctx.lineTo(x: 120, y: 5)
            ctx.stroke()
        }
        .frame(width: 160, height: 50)
    }
}

struct ProfileScreen: View {
    @Binding var secret: String
    @Binding var notify: Bool
    @Binding var showSheet: Bool
    @Binding var measured: String
    @Binding var photo: Data?
    @Binding var photoStatus: String
    @Binding var keychainStatus: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Avatar(initials: "P", tint: .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paolo").font(.headline)
                    Text("paolo@example.com").font(.caption).foregroundColor(.secondaryText)
                }
                Spacer()
            }

            Divider()

            // Grouped under one nested VStack, not three more direct children
            // of the outer one — ViewBuilder.buildBlock tops out at 10
            // arguments, and the outer VStack already has several.
            VStack(alignment: .leading, spacing: 14) {
                Text("Activity").font(.headline)
                ActivityChart()
                ProgressView()
            }

            // Toggle's own title isn't rendered on iOS today, so the visible
            // label comes from this sibling Text instead.
            HStack {
                Text("Notifications")
                Spacer()
                Toggle("Notifications", isOn: $notify)
            }

            SecureField("API token", text: $secret)

            GeometryReader(onResize: { proxy in
                measured = "\(Int(proxy.width))x\(Int(proxy.height))"
            }) {
                Text("viewport: \(measured)").monospaced().font(.caption).foregroundColor(.secondaryText)
            }

            Divider()

            // Same reason as above: one nested VStack instead of four more
            // direct children.
            VStack(alignment: .leading, spacing: 8) {
                Text("Photo").font(.headline)
                if let photo {
                    Image(data: photo)
                        .frame(width: 120, height: 120)
                }
                Text(photoStatus).font(.caption).foregroundColor(.secondaryText)

                HStack(spacing: 12) {
                    // photoStatus is written synchronously first, before the
                    // Task exists. If the label changes to "tapped…" the button
                    // and the re-render are fine and the async path is at fault;
                    // if it does not change at all, the action never ran.
                    Button("Take Photo", action: {
                        // Three probes, so the logcat trace says exactly which
                        // half is broken: the action itself, the Task body, and
                        // the first await. adb logcat -s Omni:I OmniCamera:I
                        Omni.log("1. button action ran")
                        photoStatus = "tapped, starting capture…"
                        Self.capture(into: $photo, status: $photoStatus)
                    })
                        .foregroundColor(.rgba(r: 1, g: 1, b: 1, a: 1))
                        .padding(horizontal: 16, vertical: 10)
                        .background(.blue)

                    Button("Choose Photo", action: {
                        photoStatus = "tapped, starting pick…"
                        Self.pick(into: $photo, status: $photoStatus)
                    })
                        .padding(horizontal: 16, vertical: 10)
                }
            }

            KeychainSection(status: $keychainStatus)

            VStack(alignment: .leading, spacing: 14) {
                Divider()
                Button("Account details", action: { showSheet = true })
                    .foregroundColor(.rgba(r: 1, g: 1, b: 1, a: 1))
                    .padding(horizontal: 20, vertical: 12)
                    .background(.blue)
            }
        }
        .padding(16)
    }

    // Static, and taking Bindings rather than closing over `self`, so the
    // async Task and its error handling are written once instead of
    // duplicated between the two buttons — Button's action is a synchronous
    // () -> Void, so reaching Camera's async API needs a Task the same way
    // TextField+Android.swift's own JNI callback does.
    private static func capture(into photo: Binding<Data?>, status: Binding<String>) {
        Omni.log("2. capture() called, creating Task")
        Task {
            Omni.log("3. Task body running — main actor is being serviced")
            do {
                Omni.log("4. about to await Camera.default.capture()")
                let result = try await Camera.default.capture()
                Omni.log("5. capture returned")
                photo.wrappedValue = result.data
                status.wrappedValue = describe(result)
            } catch {
                Omni.log("capture threw: \(error)")
                status.wrappedValue = describe(error)
            }
        }
    }

    private static func pick(into photo: Binding<Data?>, status: Binding<String>) {
        Task {
            do {
                let result = try await Camera.default.pickImage()
                photo.wrappedValue = result.data
                status.wrappedValue = describe(result)
            } catch {
                status.wrappedValue = describe(error)
            }
        }
    }

    private static func describe(_ image: CapturedImage) -> String {
        "\(image.width)x\(image.height) \(image.format.mimeType), \(image.data.count / 1024) KB"
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case CameraError.cancelled: return "cancelled"
        case CameraError.notAuthorized(let state): return "camera access: \(state)"
        case CameraError.noCameraAvailable: return "no camera available"
        case CameraError.notImplemented(let reason): return reason
        case CameraError.platform(let reason): return reason
        default: return "error: \(error)"
        }
    }
}

// MARK: - Web

/// The demo page, served from memory.
///
/// `loadHTML` rather than a URL on purpose: the kitchen sink has to work on a
/// device with no connectivity and on a CI box with no DNS, and nothing this
/// screen proves needs a server. What it proves is the two hooks, which are the
/// reason the component exists:
///
///   - **Pay** navigates to `omni://checkout/done?token=…`. `decidePolicy`
///     cancels that navigation and reads the token off it — exactly how a
///     hosted checkout hands a result back, minus the hosting.
///   - **Send a message** calls `window.omni.postMessage`, which is the same
///     call on WKWebView, android.webkit.WebView, WebKitGTK and WebView2
///     because each backend installs the shim over its own channel.
private let demoPage = """
<!doctype html>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body { font: 15px -apple-system, Roboto, sans-serif; margin: 0; padding: 20px;
         color: #1a1a1a; background: #fff; }
  h1 { font-size: 19px; margin: 0 0 4px; }
  p  { color: #666; margin: 0 0 18px; }
  a.pay, button { display: block; width: 100%; box-sizing: border-box;
                  padding: 13px; margin-bottom: 10px; border: 0; border-radius: 8px;
                  font-size: 15px; text-align: center; text-decoration: none; }
  a.pay  { background: #0a7; color: #fff; font-weight: 600; }
  button { background: #eee; color: #222; }
  #ping { margin-top: 16px; padding: 10px; border-radius: 6px; background: #f4f4f4;
          font-family: ui-monospace, monospace; font-size: 13px; color: #555; }
</style>
<h1>Hosted checkout</h1>
<p>Standing in for a payment page. Nothing here is real.</p>

<a class="pay" href="omni://checkout/done?token=tok_live_9f2a">Pay $12.00</a>
<button onclick="omni.postMessage(JSON.stringify({event:'ready',amount:1200}))">
  Send a message to the app
</button>
<div id="ping">waiting for the app…</div>
"""

/// Built once, when the node first adopts the object — `@StateObject`'s
/// initializer is an autoclosure, so this does not run again on re-render. That
/// matters: enqueuing a load from `body` would bump the page's revision, which
/// renders the node, which enqueues another load.
@MainActor private func demoWebPage() -> WebPage {
    let page = WebPage()
    page.loadHTML(demoPage)
    return page
}

struct WebScreen: View {
    @StateObject var page = demoWebPage()
    @State var caughtToken = "none yet"
    @State var lastMessage = "none yet"

    var body: some View {
        // Reassigned every render, which is free: they are plain closures, not
        // @Published, so setting them provokes nothing.
        page.decidePolicy = { url in
            guard url.scheme == "omni" else { return .allow }
            let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "token" })?.value
            caughtToken = token ?? "(no token on \(url.path))"
            return .cancel
        }
        page.onMessage = { lastMessage = $0 }

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(page.title.isEmpty ? "Hosted checkout" : page.title).font(.headline)
                Text(status).font(.caption).foregroundColor(.secondaryText).monospaced()

                HStack(spacing: 8) {
                    Button("Back", action: { page.goBack() })
                        .foregroundColor(page.canGoBack ? .blue : .gray)
                    Button("Reload", action: { page.reload() }).foregroundColor(.blue)
                    Button("Ping the page", action: {
                        page.evaluateJavaScript(
                            "document.getElementById('ping').textContent = 'the app said hello';")
                    }).foregroundColor(.blue)
                    Spacer()
                }
            }
            .padding(horizontal: 16, vertical: 12)

            Divider()

            // The web view itself takes the surplus; the readouts below are
            // fixed height. On a machine with no engine this is the backend's
            // own "no web engine" notice rather than an empty box, which is the
            // behaviour worth seeing in the sink.
            WebView(page)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
              HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("token from decidePolicy").font(.caption).foregroundColor(.secondaryText)
                    Text(caughtToken).monospaced()
                        .foregroundColor(caughtToken == "none yet" ? .gray : .green)
                    Text("window.omni.postMessage").font(.caption).foregroundColor(.secondaryText)
                    Text(lastMessage).monospaced()
                        .foregroundColor(lastMessage == "none yet" ? .gray : .green)
                }
                Spacer()
              }
              .padding(horizontal: 16, vertical: 12)
            }
            .background(.controlBackground)
        }
    }

    private var status: String {
        if let error = page.lastError { return "error · \(error)" }
        if page.isLoading { return "loading · \(Int(page.estimatedProgress * 100))%" }
        return page.url?.absoluteString ?? "in-memory document"
    }
}

// MARK: - Chrome

struct TabBar: View {
    @Binding var selection: Int

    private let titles = ["Inbox", "Compose", "Profile", "Web", "Design"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            // `.fill` distribution doesn't reliably split surplus space
            // evenly across more than a tied pair of Spacers (each nested
            // per-tab Spacer would need tying across a *different* stack's
            // arranged subviews, which the equal-spacer fix in
            // HStack+Apple.swift can't reach). A fixed, equal width per tab
            // — centered by exactly one tied leading/trailing Spacer pair,
            // which *is* reachable — sidesteps that entirely.
            //
            // 72 since the Design tab arrived: five at 72 is 360pt, the width of
            // a 360dp phone; any wider and the row would clip rather than wrap.
            HStack(spacing: 0) {
                Spacer()
                ForEach(0..<5, id: \.self) { index in
                    Button(titles[index], action: { selection = index })
                        .foregroundColor(selection == index ? .blue : .gray)
                        .frame(width: 72, height: 44)
                }
                Spacer()
            }
            .padding(horizontal: 0, vertical: 6)
        }
        .background(.windowBackground)
    }
}

// MARK: - Root

public struct KitchenSinkView: View {
    @State var tab = 0
    @State var recipient = "grace@example.com"
    @State var subject = "Re: found a bug"
    @State var messageBody = "Nice catch.\nShipping a fix."
    @State var urgent = false
    @State var priority: Double = 0.4
    @State var folder = 0
    @State var sent = 0
    @State var notify = true
    @State var secret = "hunter2"
    @State var showSheet = false
    @State var showAlert = false
    @State var measured = "unmeasured"
    @State var photo: Data? = nil
    @State var photoStatus = "no photo yet"
    @State var keychainStatus = "not tried"

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderBar(title: "Omni Mail", subtitle: "BUILD-MARKER-026 · tab \(tab)")

            screen

            TabBar(selection: $tab)
        }
        .sheet(isPresented: $showSheet) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Avatar(initials: "P", tint: .green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Paolo").font(.headline)
                        Text("paolo@example.com").font(.caption).foregroundColor(.secondaryText)
                    }
                    Spacer()
                }
                Divider()
                Button("Close", action: { showSheet = false })
                    .foregroundColor(.rgba(r: 1, g: 1, b: 1, a: 1))
                    .padding(horizontal: 20, vertical: 12)
                    .background(.blue)
            }
            .padding(20)
        }
        .alert("Message sent", isPresented: $showAlert)
    }

    // Each screen owns its own scrolling. Nesting a List inside an outer
    // ScrollView collapses the inner one: two scrollable containers give the
    // inner an unbounded height to measure against.
    private var screen: some View {
        if tab == 0 {
            return AnyView(InboxScreen())
        } else if tab == 1 {
            return AnyView(ScrollView(axis: .vertical) {
                ComposeScreen(recipient: $recipient, subject: $subject,
                              body_: $messageBody, urgent: $urgent,
                              priority: $priority, folder: $folder,
                              sent: $sent, showAlert: $showAlert)
            })
        } else if tab == 2 {
            return AnyView(ScrollView(axis: .vertical) {
                ProfileScreen(secret: $secret, notify: $notify,
                              showSheet: $showSheet, measured: $measured,
                              photo: $photo, photoStatus: $photoStatus,
                               keychainStatus: $keychainStatus)
            })
        } else if tab == 4 {
            return AnyView(DesignScreen())
        } else {
            // No ScrollView around this one: the web view scrolls itself, and
            // nesting it inside an outer scroller gives it an unbounded height
            // to measure against — the same collapse the comment above
            // describes for List.
            return AnyView(WebScreen())
        }
    }
}

/// The application itself. Identical on every platform: no platform entry
/// point, no JNI, no conditional compilation.
public struct KitchenSinkApp: App {
    public init() {}

    public var window = WindowConfig(
        title: "Omni Mail",
        width: 420,
        height: 860,
        // The scheme is declared in omni.json; this is the other half. Logged
        // rather than shown on screen: a deep link can only be delivered by the
        // OS, so there is nothing a render test could assert, and logcat is
        // where you would look anyway.
        //
        //   adb shell am start -a android.intent.action.VIEW -d "omnikitchen://pay/42"
        //   xdg-open "omnikitchen://pay/42"        # Linux, once installed
        onOpenURL: { url in Omni.log("deep link: \(url.absoluteString)") }
    )

    public var body: some View { KitchenSinkView() }
}

// Kept as its own view because ProfileScreen's VStack is at ViewBuilder's
// 10-child ceiling — the same reason the photo block is one nested VStack
// rather than four direct children.
struct KeychainSection: View {
    @Binding var status: String

    private static let tokenKey = "kitchensink.session.token"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Keychain").font(.headline)
            Text(status).font(.caption).foregroundColor(.secondaryText)

            // Synchronous on purpose: the Keychain API is not async, so this
            // exercises storage without the Task machinery the camera needs.
            // If one works and the other does not, that separates the two.
            HStack(spacing: 12) {
                Button("Store", action: { status = store() })
                    .foregroundColor(.rgba(r: 1, g: 1, b: 1, a: 1))
                    .padding(horizontal: 16, vertical: 10)
                    .background(.blue)

                Button("Read", action: { status = read() })
                    .padding(horizontal: 16, vertical: 10)

                Button("Delete", action: { status = remove() })
                    .padding(horizontal: 16, vertical: 10)
            }
        }
    }

    private func store() -> String {
        let value = "token-\(Int(Date().timeIntervalSince1970))"
        do {
            try Keychain.default.setString(value, for: Self.tokenKey, accessibility: .whenUnlocked)
            return "stored \(value)"
        } catch {
            return "store failed: \(error)"
        }
    }

    private func read() -> String {
        do {
            guard let value = try Keychain.default.getString(Self.tokenKey) else {
                return "absent (nil, which is not an error)"
            }
            return "read \(value)"
        } catch {
            return "read failed: \(error)"
        }
    }

    private func remove() -> String {
        do {
            try Keychain.default.delete(Self.tokenKey)
            // The contract: after delete, a read is absent rather than stale.
            let after = (try? Keychain.default.getString(Self.tokenKey)) ?? nil
            return after == nil ? "deleted, reads back absent" : "deleted but still readable — BUG"
        } catch let error as KeychainError where error == .notFound {
            return "nothing to delete (.notFound)"
        } catch {
            return "delete failed: \(error)"
        }
    }
}

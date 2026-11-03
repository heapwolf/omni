# Omni

SwiftUI-style Swift. Native views on macOS, iOS, Android, Linux and Windows.

Render native components on every platform. 

```swift
import OmniUI

@main
struct Counter: App {
    @State var count = 0
    var window = WindowConfig(title: "Counter", width: 320, height: 200)

    var body: some View {
        VStack(spacing: 12) {
            Text("count = \(count)")
            Button("Add", action: { count += 1 })
        }
    }
}
```

```bash
omni run                      # macOS
omni run -p ios-simulator
omni run -p ios
omni run -p android           # attached device
omni run -p linux
omni run -p windows
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/heapwolf/omni/master/install.sh | bash
```

Or `./install.sh` from a checkout, which builds that checkout: an app that
depends on omni by path (`../omni`) then uses a CLI that matches its library.
It installs Apple's Command Line Tools if needed, builds omni, and links it at
`~/.omni/bin/omni`. An older copy elsewhere on `PATH` is pointed at the new
build. Then:

```bash
omni doctor -p android --fix   # or ios, ios-simulator, macos
omni update                    # later: pull, rebuild, relink
```

## Use

```swift
// Package.swift
.package(url: "https://github.com/heapwolf/omni.git", branch: "master")

.product(name: "OmniUI", package: "Omni")
```

## Complete and Tested Cross-Platform Components

| Kind       | Views                                                                                         |
| ---------- | --------------------------------------------------------------------------------------------- |
| Layout     | `VStack` `HStack` `ZStack` `Stack` `LazyVStack` `LazyHStack` `Spacer` `Divider` `GeometryReader` `Responsive` `Group` `ForEach` |
| Scroll     | `ScrollView` `List` `Table`                                                                   |
| Navigation | `NavigationStack` `NavigationLink` `NavigationSplitView` `TabView` `Sidebar` `SplitView`      |
| Text       | `Text` `TextField` `SecureField` `TextEditor`                                                 |
| Controls   | `Button` `Toggle` `Slider` `Picker` `DatePicker` `ActionMenu` `Menu` `ShareLink`              |
| Media      | `Image` `WebView` `QRCode` `Canvas` `ProgressView` `TimelineView`                             |
| Shapes     | `Rectangle` `RoundedRectangle` `Circle` `Ellipse` `Capsule` `LinearGradient`                  |
| Effects    | `GlassEffectContainer`                                                                        |
| Utility    | `AnyView` `EmptyView`                                                                         |

## Modules

Take only what you use.

| Module         | For                               |
| -------------- | --------------------------------- |
| `OmniUI`       | Views, state, navigation          |
| `OmniData`     | SwiftData-style models on SQLite  |
| `OmniHTTP`     | `fetch`                           |
| `OmniKeychain` | Secrets, device and Face ID keys  |
| `OmniCamera`   | Capture, photo picker             |
| `OmniProbe`    | End-to-end tests. Never shipped.  |

```swift
let user = try await fetch(url).json(User.self)
```

```swift
try Keychain.default.setString(token, for: "token")
let token = try Keychain.default.getString("token")
```

```swift
let signature = try await ApprovalKeys.default.sign(payload, with: "approval",
                                                    prompt: ApprovalPrompt(reason: "Approve $25.00", cancel: "Use PIN"))
```

```swift
let photo = try await Camera.default.capture()
```

## CLI

| Command          | Does                                     |
| ---------------- | ---------------------------------------- |
| `omni build`     | Compile                                  |
| `omni run`       | Compile, install, launch                 |
| `omni package`   | Installer: `.pkg`, `.deb`/`.rpm`, `.msi` |
| `omni provision` | iOS certificate, App ID, device, profile |
| `omni doctor`    | Check this Mac for a platform; `--fix` installs what's missing |

```bash
omni package -p linux --format both
omni doctor -p android --fix
```

`build` and `run` check first and set up what they can: Homebrew, Apple's
Command Line Tools, a swift.org toolchain, the Android NDK, SDK and a JDK,
and for iOS, Xcode, its license and components, and a simulator. Anything
that needs a password, an Apple ID or a large download is asked about first.

## Config

Optional `omni.json` beside `Package.swift`:

```json
{
  "bundleIdentifier": "com.example.app",
  "urlSchemes": ["example"]
}
```

## Examples

`examples/smoke`, `examples/todo`, `examples/kitchensink`.

## License

[LICENSE.txt](LICENSE.txt)

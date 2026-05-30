import KitchenSinkUI

// Desktop entry point. Android needs no counterpart: the CLI generates its JNI
// entry at build time, so the app itself stays platform-free.
@main
struct Desktop {
    @MainActor static func main() {
        KitchenSinkApp.main()
    }
}

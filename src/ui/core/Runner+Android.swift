// src/lib/core/Runner+Android.swift
#if os(Android)
    import Foundation
    import CAndroid

    extension OmniAndroid {
        /// Boots an app from the JVM. The generated JNI entry point calls this
        /// and nothing else, so applications never see JNIEnv or jobject.
        /// The app is made after JNI is set up, not before: an argument is
        /// evaluated first, and an app whose init reads a file (a saved
        /// appearance, under AppDirectories) died for want of a JNI environment.
        @MainActor
        public static func launch(
            _ app: @autoclosure @MainActor () -> any App,
            env: UnsafeMutablePointer<JNIEnv?>?,
            activity: jobject?
        ) {
            guard let env, let activity else { return }
            omni_jni_init(env, activity)
            AndroidRunner().run(app())
        }
    }

    // Android does not use App.main(): the JVM owns the process and the startup
    // lifecycle, and calls in here over JNI once the Activity exists.
    public struct AndroidRunner {
        public init() {}

        @MainActor
        public func run(_ app: any App) {
            guard OmniAndroid.getEnv() != nil else {
                fatalError("JNI environment unavailable — omni_jni_init must run first")
            }

            // Edge to edge, the content padded clear of the bars and keyboard.
            // Again whenever the root's native changes: a root can show nothing
            // until something loads.
            var isFirst = true
            Engine.rootHost = { native in
                guard let native else { return }
                omni_jni_install_root(OmniAndroid.env, omni_jni_activity(), native)
                // The first screen's tree, in a debug build's log; not every swap's.
                if isFirst { omni_jni_dump_view_tree(OmniAndroid.env, native) }
                isFirst = false
            }
            // Node(app), not Node(app.body): the engine evaluates the body itself,
            // and skipping that level drops any @State declared on the App.
            let root = Node(app)
            Engine.root = root
            Engine.render(root)

            DeepLink.install(app.window.onOpenURL)
        }
    }
#endif

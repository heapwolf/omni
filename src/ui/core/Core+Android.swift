// src/lib/core/Core+Android.swift
#if os(Android)
    import CAndroid

    public struct OmniAndroid {
        public static var env: UnsafeMutablePointer<JNIEnv?> {
            guard let env = getEnv() else {
                fatalError("No JNI environment — omni_jni_init must run before any view is created")
            }
            return env
        }

        public static func getEnv() -> UnsafeMutablePointer<JNIEnv?>? {
            return omni_get_env()
        }

        public static func createView(
            _ env: UnsafeMutablePointer<JNIEnv?>?,
            _ classPath: String
        ) -> NativeView {
            guard let view = omni_jni_create_view(env, classPath) else {
                fatalError("JNI could not instantiate \(classPath)")
            }
            return view
        }
    }
#endif

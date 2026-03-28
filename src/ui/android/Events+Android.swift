// src/lib/android/events.swift

#if os(Android)
import Foundation
import CAndroid


@MainActor
public class EventHandlerInt {
    var action: (Int) -> Void
    public init(_ action: @escaping (Int) -> Void) { self.action = action }
}

@MainActor
public class EventHandlerFloat {
    var action: (Float) -> Void
    public init(_ action: @escaping (Float) -> Void) { self.action = action }
}

@MainActor
public class EventHandlerFloat2 {
    var action: (Float, Float) -> Void
    public init(_ action: @escaping (Float, Float) -> Void) { self.action = action }
}

@MainActor
public class EventHandlerVoid {
    var action: () -> Void
    public init(_ action: @escaping () -> Void) { self.action = action }
}

@MainActor
public class EventHandlerBool {
    var action: (Bool) -> Void
    public init(_ action: @escaping (Bool) -> Void) { self.action = action }
}

@MainActor
public class EventHandlerString {
    var action: (String) -> Void
    public init(_ action: @escaping (String) -> Void) { self.action = action }
}


/// Brings an EditText in line with its binding, for TextField, SecureField and
/// TextEditor. setText fires the TextWatcher just as typing does, so the text
/// is set with the handler muted: an echo wrote it into whichever binding the
/// handler held. On the PIN step one field moves from $pin to $confirmation,
/// and the echo emptied the PIN, so every confirmation was a mismatch. The
/// handler is then pointed at this render's binding; an earlier one's writes
/// to @State storage the node has since replaced.
@MainActor func syncTextField(_ view: NativeView, to text: String,
                              handlers: inout [UnsafeMutableRawPointer: EventHandlerString],
                              onEdit action: @escaping (String) -> Void) {
    let env = OmniAndroid.env
    let handler: EventHandlerString
    if let existing = handlers[view] {
        handler = existing
    } else {
        handler = EventHandlerString(action)
        handlers[view] = handler
        omni_jni_attach_text_watcher(env, view, Unmanaged.passUnretained(handler).toOpaque())
    }

    handler.action = { _ in }
    if let cStr = omni_jni_get_text(env, view) {
        let current = String(cString: cStr)
        free(cStr)
        if current != text { omni_jni_call_void_method_string(env, view, "setText", text) }
    }
    handler.action = action
}

@_cdecl("omni_swift_dispatch_void")
public func omni_swift_dispatch_void(_ ptr: UnsafeMutableRawPointer) {
    let handler = Unmanaged<EventHandlerVoid>.fromOpaque(ptr).takeUnretainedValue()
    MainActor.assumeIsolated { handler.action() }
}

@_cdecl("omni_swift_dispatch_int")
public func omni_swift_dispatch_int(_ ptr: UnsafeMutableRawPointer, _ val: Int32) {
    let handler = Unmanaged<EventHandlerInt>.fromOpaque(ptr).takeUnretainedValue()
    MainActor.assumeIsolated { handler.action(Int(val)) }
}

@_cdecl("omni_swift_dispatch_float")
public func omni_swift_dispatch_float(_ ptr: UnsafeMutableRawPointer, _ val: Float) {
    let handler = Unmanaged<EventHandlerFloat>.fromOpaque(ptr).takeUnretainedValue()
    MainActor.assumeIsolated { handler.action(val) }
}

@_cdecl("omni_swift_dispatch_float2")
public func omni_swift_dispatch_float2(_ ptr: UnsafeMutableRawPointer, _ x: Float, _ y: Float) {
    let handler = Unmanaged<EventHandlerFloat2>.fromOpaque(ptr).takeUnretainedValue()
    MainActor.assumeIsolated { handler.action(x, y) }
}

@_cdecl("omni_swift_dispatch_bool")
public func omni_swift_dispatch_bool(_ ptr: UnsafeMutableRawPointer, _ val: Int32) {
    let handler = Unmanaged<EventHandlerBool>.fromOpaque(ptr).takeUnretainedValue()
    MainActor.assumeIsolated { handler.action(val != 0) }
}

@_cdecl("omni_swift_dispatch_string")
public func omni_swift_dispatch_string(_ ptr: UnsafeMutableRawPointer, _ cStr: UnsafePointer<CChar>) {
    let str = String(cString: cStr)
    let handler = Unmanaged<EventHandlerString>.fromOpaque(ptr).takeUnretainedValue()
    MainActor.assumeIsolated { handler.action(str) }
}
#endif

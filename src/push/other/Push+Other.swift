#if !os(iOS) && !os(Android)
func platformRegister(prompting: Bool) async throws -> PushToken {
    throw PushError.unavailable("Push notifications are for iOS and Android.")
}
#endif

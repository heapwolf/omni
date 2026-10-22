#if os(Windows)
import Foundation

func makePlatformApprovalKeys() -> any ApprovalKeyStore { NoApprovalKeyStore() }
#endif

#if os(Linux)
import Foundation

func makePlatformApprovalKeys() -> any ApprovalKeyStore { NoApprovalKeyStore() }
#endif

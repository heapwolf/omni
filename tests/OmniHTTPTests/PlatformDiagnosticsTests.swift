import XCTest
import Foundation
@testable import OmniHTTP

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class PlatformDiagnosticsTests: XCTestCase {
    private func url(_ string: String) -> URL { URL(string: string)! }

    private func message(_ error: any Error, _ string: String) -> String {
        let diagnosed = PlatformDiagnostics.diagnose(error, url: url(string))
        guard case .transport(let text) = diagnosed else {
            XCTFail("expected .transport, got \(diagnosed)")
            return ""
        }
        return text
    }

    // MARK: the missing permission

    func testNoConnectivityAlsoPointsAtTheMissingPermission() {
        let text = message(URLError(.notConnectedToInternet), "https://api.example.com/")
        XCTAssertTrue(text.contains("android.permission.INTERNET"),
                      "a missing permission is indistinguishable from no signal: \(text)")
    }

    // MARK: the trust store

    func testUntrustedCertificateNamesTheStoreAndTheOverride() {
        for code in [URLError.Code.serverCertificateUntrusted,
                     .serverCertificateHasBadDate,
                     .serverCertificateHasUnknownRoot,
                     .serverCertificateNotYetValid] {
            let text = message(URLError(code), "https://api.example.com/")
            XCTAssertTrue(text.contains("cacerts"), "must point at the trust store: \(text)")
            XCTAssertTrue(text.contains("SSL_CERT_DIR"), "must name the override: \(text)")
        }
    }

    func testTlsHandshakeFailureAlsoGivesTheStoreHint() {
        let text = message(URLError(.secureConnectionFailed), "https://api.example.com/")
        XCTAssertTrue(text.contains("cacerts"), "must point at the trust store: \(text)")
    }

    // MARK: the emulator host

    func testDnsFailureMentionsTheEmulatorHostAlias() {
        let text = message(URLError(.cannotFindHost), "https://localhost:3000/")
        XCTAssertTrue(text.contains("10.0.2.2"), "localhost on an emulator is the emulator: \(text)")
    }

    func testConnectionRefusedNamesHostAndPort() {
        let text = message(URLError(.cannotConnectToHost), "https://10.0.2.2:3000/health")
        XCTAssertTrue(text.contains("10.0.2.2"), "must name the host: \(text)")
        XCTAssertTrue(text.contains("3000"), "must name the port: \(text)")
    }

    // MARK: cleartext

    func testPlainHttpFailureMentionsCleartextPolicy() {
        let error = NSError(domain: "test", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "connection failed"])
        let text = message(error, "http://api.example.com/")
        XCTAssertTrue(text.contains("usesCleartextTraffic"), "must name the policy: \(text)")
        XCTAssertTrue(text.contains("connection failed"), "must keep the cause: \(text)")
    }

    func testHttpsFailuresDoNotMentionCleartext() {
        let error = NSError(domain: "test", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "something else"])
        let text = message(error, "https://api.example.com/")
        XCTAssertFalse(text.contains("usesCleartextTraffic"))
        XCTAssertEqual(text, "something else")
    }

    // MARK: cases that keep their own identity

    func testTimeoutAndCancellationAreNotFlattenedIntoTransport() {
        let target = url("https://api.example.com/")
        XCTAssertEqual(PlatformDiagnostics.diagnose(URLError(.timedOut), url: target), .timedOut)
        XCTAssertEqual(PlatformDiagnostics.diagnose(URLError(.cancelled), url: target), .cancelled)
    }

    func testAnUnrecognisedErrorStillSurfacesItsDescription() {
        struct Weird: LocalizedError { var errorDescription: String? { "something specific" } }
        let text = message(Weird(), "https://api.example.com/")
        XCTAssertTrue(text.contains("something specific"), "must not swallow the cause: \(text)")
    }
}

/// Retryability is a Fetch-layer concept and stayed there when the diagnosis
/// moved down.
final class FetchErrorRetryabilityTests: XCTestCase {
    func testRetryabilityMatchesWhetherRetryingCouldWork() {
        XCTAssertTrue(FetchError.timedOut.isRetryable)
        XCTAssertTrue(FetchError.network("refused").isRetryable)
        XCTAssertFalse(FetchError.aborted.isRetryable, "an abort was deliberate")
        XCTAssertFalse(FetchError.invalidArgument("bad url").isRetryable, "a bad URL stays bad")
        XCTAssertFalse(FetchError.bodyAlreadyConsumed.isRetryable, "a programming error")
        XCTAssertFalse(FetchError.redirectNotAllowed(to: "https://x").isRetryable)
    }
}

final class TransportMappingTests: XCTestCase {
    private struct FailingClient: HTTPClient {
        let error: HTTPError
        func send(_ request: HTTPRequest) async throws -> HTTPResponse { throw error }
    }

    private func fetchError(for error: HTTPError) async -> FetchError? {
        let transport = HTTPClientTransport(client: FailingClient(error: error))
        do {
            _ = try await transport.send(try Request("https://example.com"))
            return nil
        } catch let error as FetchError {
            return error
        } catch { return nil }
    }

    func testEveryHTTPErrorMapsOntoAFetchError() async {
        let cases: [(HTTPError, FetchError)] = [
            (.timedOut, .timedOut),
            (.cancelled, .aborted),
            (.notHTTP, .network("Response was not HTTP")),
            (.transport("refused"), .network("refused")),
        ]
        for (platform, expected) in cases {
            let actual = await fetchError(for: platform)
            XCTAssertEqual(actual, expected, "\(platform) should map to \(expected)")
        }
    }
}

import Foundation
import XCTest
@testable import OmniHTTP

final class CookiesTests: XCTestCase {
    let url = URL(string: "https://admin-dev.example.com/api/auth/password-login")!

    func testASessionCookieParses() throws {
        let cookie = try XCTUnwrap(Cookie(setCookie: "adminjs=s%3Aabc.def; Path=/; HttpOnly; Secure; SameSite=Lax", from: url))
        XCTAssertEqual(cookie.name, "adminjs")
        XCTAssertEqual(cookie.value, "s%3Aabc.def")
        XCTAssertEqual(cookie.domain, "admin-dev.example.com")
        XCTAssertEqual(cookie.path, "/")
        XCTAssertTrue(cookie.secure)
        XCTAssertFalse(cookie.includesSubdomains)
    }

    /// Apple folds repeated Set-Cookie headers into one, comma-joined; an
    /// Expires date has a comma of its own.
    func testFoldedHeadersSplitOnCookiesNotOnDates() {
        let folded = "a=1; Expires=Wed, 21 Oct 2099 07:28:00 GMT; Path=/, b=2; Path=/"
        XCTAssertEqual(Cookie.split([folded]), ["a=1; Expires=Wed, 21 Oct 2099 07:28:00 GMT; Path=/", "b=2; Path=/"])
    }

    func testMaxAgeAndExpiresSetTheExpiry() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let byAge = try XCTUnwrap(Cookie(setCookie: "a=1; Max-Age=60", from: url, now: now))
        XCTAssertEqual(byAge.expires, now.addingTimeInterval(60))
        let byDate = try XCTUnwrap(Cookie(setCookie: "a=1; Expires=Wed, 21 Oct 2099 07:28:00 GMT", from: url, now: now))
        XCTAssertNotNil(byDate.expires)
    }

    func testTheJarSendsOnlyWhatMatches() {
        let jar = CookieJar()
        jar.store(setCookies: ["adminjs=x; Path=/", "scoped=y; Path=/api/ledger"], from: url)
        XCTAssertEqual(jar.header(for: URL(string: "https://admin-dev.example.com/api/me")!), "adminjs=x")
        XCTAssertEqual(jar.header(for: URL(string: "https://admin-dev.example.com/api/ledger/balances")!),
                       "scoped=y; adminjs=x")
        XCTAssertNil(jar.header(for: URL(string: "https://admin.example.com/api/me")!), "another host")
        XCTAssertEqual(jar.header(for: URL(string: "http://admin-dev.example.com/api/me")!), "adminjs=x",
                       "not Secure, so plain http (a local backend) still gets it")
    }

    func testASecureCookieIsNotSentOverHTTP() {
        let jar = CookieJar()
        jar.store(setCookies: ["adminjs=x; Secure"], from: url)
        XCTAssertNil(jar.header(for: URL(string: "http://admin-dev.example.com/api/me")!))
    }

    func testAnExpiredCookieRemovesTheOneItReplaces() {
        let jar = CookieJar()
        jar.store(setCookies: ["adminjs=x; Path=/"], from: url)
        jar.store(setCookies: ["adminjs=; Path=/; Max-Age=0"], from: url)
        XCTAssertTrue(jar.all.isEmpty)
    }

    func testTheTransportSendsAndKeeps() async throws {
        struct Echo: Transport {
            func send(_ request: Request) async throws -> Response {
                var headers = Headers()
                headers.append("set-cookie", "adminjs=new; Path=/")
                headers.append("x-sent-cookie", request.headers.get("cookie") ?? "none")
                return Response(status: 200, headers: headers, url: request.url)
            }
        }
        let jar = CookieJar([Cookie(name: "adminjs", value: "old", domain: "admin-dev.example.com")])
        let transport = CookieTransport(jar: jar, base: Echo())
        let response = try await fetch(url, using: transport)
        XCTAssertEqual(response.headers.get("x-sent-cookie"), "adminjs=old")
        XCTAssertEqual(jar.value("adminjs", for: url), "new")
    }
}

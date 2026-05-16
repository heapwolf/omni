import XCTest
@testable import OmniUI

final class TextFieldConfigurationTests: XCTestCase {
    @MainActor private static func field(_ text: Binding<String>) -> TextField {
        TextField(text, placeholder: "")
    }

    @MainActor private static func store(_ initial: String = "") -> (Binding<String>, () -> String) {
        var storage = initial
        return (Binding<String>(get: { storage }, set: { storage = $0 }), { storage })
    }

    // MARK: defaults

    func testDefaultsMatchSwiftUIsOwn() {
        MainActor.assumeIsolated {
            let configuration = TextFieldConfiguration()
            XCTAssertEqual(configuration.autocapitalization, .sentences)
            XCTAssertFalse(configuration.isAutocorrectionDisabled)
            XCTAssertNil(configuration.maxLength)
            XCTAssertNil(configuration.onSubmit)
            if case .default = configuration.keyboardType {} else { XCTFail("expected .default") }
            if case .done = configuration.submitLabel {} else { XCTFail("expected .done") }
        }
    }

    // MARK: the keyboard settles capitalisation and autocorrect

    func testTextKeyboardLeavesCapitalisationToTheCaller() {
        MainActor.assumeIsolated {
            var configuration = TextFieldConfiguration()
            configuration.keyboardType = .default
            configuration.autocapitalization = .words
            XCTAssertEqual(configuration.resolvedAutocapitalization, .words)
            XCTAssertFalse(configuration.resolvedAutocorrectionDisabled)
        }
    }

    /// Choosing an email or numeric keyboard is unambiguous. An autocapitalising
    /// email field is a bug every time, so the keyboard wins over the caller.
    func testEmailAndNumericKeyboardsForceCapitalisationAndAutocorrectOff() {
        MainActor.assumeIsolated {
            for keyboard in [KeyboardType.emailAddress, .URL, .numberPad, .phonePad, .decimalPad] {
                var configuration = TextFieldConfiguration()
                configuration.keyboardType = keyboard
                configuration.autocapitalization = .sentences
                configuration.isAutocorrectionDisabled = false
                XCTAssertEqual(configuration.resolvedAutocapitalization, .never,
                               "\(keyboard) must not autocapitalise")
                XCTAssertTrue(configuration.resolvedAutocorrectionDisabled,
                              "\(keyboard) must not autocorrect")
            }
        }
    }

    // MARK: environment propagation

    func testModifiersWriteIntoTheEnvironment() {
        MainActor.assumeIsolated {
            var environment = EnvironmentValues()
            // What the View extensions do, applied directly: the modifier
            // transforms the configuration the environment carries.
            environment.textFieldConfiguration.keyboardType = .emailAddress
            environment.textFieldConfiguration.maxLength = 6
            environment.textFieldConfiguration.submitLabel = .next

            let configuration = environment.textFieldConfiguration
            if case .emailAddress = configuration.keyboardType {} else { XCTFail("keyboard not carried") }
            XCTAssertEqual(configuration.maxLength, 6)
            if case .next = configuration.submitLabel {} else { XCTFail("submitLabel not carried") }
        }
    }

    func testAnUntouchedEnvironmentYieldsDefaults() {
        MainActor.assumeIsolated {
            let configuration = EnvironmentValues().textFieldConfiguration
            XCTAssertNil(configuration.maxLength)
            XCTAssertEqual(configuration.autocapitalization, .sentences)
        }
    }

    // MARK: maxLength, enforced once for every backend

    func testLimitedTruncatesToTheLimit() {
        MainActor.assumeIsolated {
            let (text, _) = Self.store()
            let field = Self.field(text)
            XCTAssertEqual(field.limited("123456789", to: 6), "123456")
            XCTAssertEqual(field.limited("123", to: 6), "123")
            XCTAssertEqual(field.limited("", to: 6), "")
        }
    }

    func testNoLimitLeavesTextAlone() {
        MainActor.assumeIsolated {
            let (text, _) = Self.store()
            let long = String(repeating: "x", count: 5_000)
            XCTAssertEqual(Self.field(text).limited(long, to: nil), long)
        }
    }

    func testLimitCountsCharactersNotBytes() {
        MainActor.assumeIsolated {
            let (text, _) = Self.store()
            let field = Self.field(text)
            // Three user-perceived characters, well over three bytes.
            XCTAssertEqual(field.limited("日本語です", to: 3), "日本語")
            XCTAssertEqual(field.limited("héllo", to: 3), "hél")
        }
    }

    func testZeroLimitYieldsEmpty() {
        MainActor.assumeIsolated {
            let (text, _) = Self.store()
            XCTAssertEqual(Self.field(text).limited("abc", to: 0), "")
        }
    }

    func testCommitWritesThroughTheLimit() {
        MainActor.assumeIsolated {
            let (text, read) = Self.store()
            Self.field(text).commit("123456", limit: 4)
            XCTAssertEqual(read(), "1234", "commit must apply the limit, not just limited()")
        }
    }

    func testCommitDoesNotWriteWhenUnchanged() {
        MainActor.assumeIsolated {
            var writes = 0
            var storage = "same"
            let text = Binding<String>(get: { storage }, set: { storage = $0; writes += 1 })
            Self.field(text).commit("same", limit: nil)
            XCTAssertEqual(writes, 0, "an unchanged commit must not feed the update loop")
        }
    }

    func testCommitWritesWhenChanged() {
        MainActor.assumeIsolated {
            var writes = 0
            var storage = "before"
            let text = Binding<String>(get: { storage }, set: { storage = $0; writes += 1 })
            Self.field(text).commit("after", limit: nil)
            XCTAssertEqual(writes, 1)
            XCTAssertEqual(storage, "after")
        }
    }

    // MARK: focus
    //
    // Focus stays on the field rather than in the environment: it is about one
    // field, and an inherited value would focus every descendant at once.

    func testFocusEqualsSetsTheValueWhenFocused() {
        MainActor.assumeIsolated {
            enum Field: Equatable { case email, password }
            var focused: Field = .password
            let focusBinding = Binding<Field>(get: { focused }, set: { focused = $0 })
            let (text, _) = Self.store()

            let subject = Self.field(text).focused(focusBinding, equals: .email)
            XCTAssertFalse(subject.focusBinding!.wrappedValue, "password is focused, not email")

            subject.focusBinding!.wrappedValue = true
            XCTAssertEqual(focused, .email, "taking focus must move the enum")
        }
    }

    func testFocusEqualsReportsTrueWhenAlreadyFocused() {
        MainActor.assumeIsolated {
            enum Field: Equatable { case email }
            var focused: Field = .email
            let focusBinding = Binding<Field>(get: { focused }, set: { focused = $0 })
            let (text, _) = Self.store()
            XCTAssertTrue(Self.field(text).focused(focusBinding, equals: .email).focusBinding!.wrappedValue)
        }
    }

    // MARK: onSubmit

    func testOnSubmitIsCarriedAndInvokable() {
        MainActor.assumeIsolated {
            var fired = 0
            var configuration = TextFieldConfiguration()
            configuration.onSubmit = { fired += 1 }
            XCTAssertNotNil(configuration.onSubmit)
            configuration.onSubmit?()
            XCTAssertEqual(fired, 1)
        }
    }
}

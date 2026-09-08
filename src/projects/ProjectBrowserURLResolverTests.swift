import XCTest

final class ProjectBrowserURLResolverTests: XCTestCase {
    func testOnlySupportedBrowsersAreRead() {
        XCTAssertTrue(ProjectBrowserURLResolver.supports("com.apple.Safari"))
        XCTAssertTrue(ProjectBrowserURLResolver.supports("com.google.Chrome"))
        XCTAssertFalse(ProjectBrowserURLResolver.supports("com.google.Chrome.helper"))
        XCTAssertFalse(ProjectBrowserURLResolver.supports(nil))
    }

    func testCanonicalOriginAndDefaultPortMatch() {
        XCTAssertEqual(ProjectBrowserURLResolver.normalized("HTTPS://Example.COM:443"), "https://example.com/")
    }

    func testCredentialsAndTransientSignInParametersAreNotStored() {
        XCTAssertEqual(ProjectBrowserURLResolver.normalized("https://user:secret@example.com/login?code=secret&state=random&returnUrl=%2Fwork"), "https://example.com/login?returnUrl=/work")
        XCTAssertEqual(ProjectBrowserURLResolver.normalized("https://example.com/#access_token=secret"), "https://example.com/")
    }

    func testDocumentQueriesAndApplicationRoutesRemainDistinct() {
        XCTAssertEqual(ProjectBrowserURLResolver.normalized("https://example.com/view?id=42#/work"), "https://example.com/view?id=42#/work")
        XCTAssertNotEqual(ProjectBrowserURLResolver.normalized("https://example.com/view?id=42"), ProjectBrowserURLResolver.normalized("https://example.com/view?id=43"))
    }

    func testUnavailableOrNonWebURLsRemainUnknown() {
        for raw in [nil, "", "example.com/typed", "javascript:alert(1)", "file:///private/document", "about:blank"] {
            XCTAssertNil(ProjectBrowserURLResolver.normalized(raw))
        }
    }
}

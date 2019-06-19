import XCTest
@testable import SwiftState

final class SwiftStateTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(SwiftState().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}

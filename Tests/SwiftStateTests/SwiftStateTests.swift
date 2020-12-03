import XCTest
@testable import SwiftState

struct Counter: Hashable {
    var count: Int
}

enum CounterAction: Action {
    case increment
    case reset
}

func rootReducer(state: Counter, action: Action) -> Counter {
    switch action {
    case CounterAction.increment:
        return Counter(count: state.count + 1)
        
    case CounterAction.reset:
        return Counter(count: 0)
        
    default:
        return state
    }
}

final class SwiftStateTests: XCTestCase {
    func testExample() {
        let store = Store(initialState: Counter(count: 0), rootReducer: rootReducer(state:action:))
        
        store.runSaga { yield in
            try yield.all(
                Effects.TakeEvery(CounterAction.self, predicate: {$0 == .reset}) { action, yield in
                    try print("resetting counter from \(yield.select(\Counter.count))")
                }
            )
        }
        
        print("start dispatch")
        store.dispatch(CounterAction.increment)
        store.dispatch(CounterAction.increment)
        store.dispatch(CounterAction.increment)
        store.dispatch(CounterAction.reset)
        store.dispatch(CounterAction.increment)
        store.dispatch(CounterAction.increment)
        store.dispatch(CounterAction.increment)
        store.dispatch(CounterAction.increment)
        store.dispatch(CounterAction.reset)
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}

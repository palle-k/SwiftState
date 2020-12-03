import XCTest
import SwiftState

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
                Effects.takeEvery(predicate: {$0 == CounterAction.reset}) { action, yield in
                    try print("resetting counter from \(yield.select(\Counter.count))")
                },
                Effects.fork { yield in
                    try yield.all(
                        Effects.take {$0 == CounterAction.increment},
                        Effects.take {$0 == CounterAction.reset}
                    )
                    print("one increment and one reset have been dispatched")
                },
                Effects.fork { yield in
                    _ = try yield.take {$0 == CounterAction.reset}
                    _ = try yield.take {$0 == CounterAction.reset}
                    _ = try yield.take {$0 == CounterAction.reset}
                    print("counter has been reset 3 times")
                }
            )
        }
        
        print("dispatch reset")
        store.dispatch(CounterAction.reset)
        print("dispatch increment")
        store.dispatch(CounterAction.increment)
        print("increment+reset dispatched")
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

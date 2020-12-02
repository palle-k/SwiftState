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
            print("starting saga")
            yield(Effects.All([
                Effects.TakeEvery(CounterAction.self) { action, _ in
                    print("receive \(action)")
                }.wrapped()
            ]))
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

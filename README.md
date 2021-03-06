# SwiftState

Redux + Saga unidirectional data flow built for SwiftUI and Combine

## Quick Start

### Install

Requires Swift 5.1 and iOS/iPadOS/tvOS 13, macOS 10.15 or watchOS 6

#### Swift Package Manager

Add the package as a dependency to the Package.swift file:

```
.package(url: "https://github.com/palle-k/SwiftState.git", branch: "master")
```

### Overview

The state of the app is managed by a single `Store<State>` object.
To modify the app state, an action must be dispatched against the store.
This triggers a root reducer of the app, which takes the current state and the action to produce a new state.

It is possible to read the app state from the store using the readonly `store.state` property.
Alternatively, the state can be subscribed to using the `store.didChange` publisher.

### Reducers

The store calls the root reducer with the current state and a dispatched action. 
The reducer then produces a new app state using only information from the current state and the action.

```swift
struct AppState {
    var username: String?
    var count: Int
}

enum AppAction {
    case setUsername(String?)
    case incrementCount
}

func rootReducer(state: AppState, action: Action) -> AppState {
    var state = state  // create a mutable copy of the app state
    switch Action {
    case AppAction.setUsername(let newUsername)
        state.username = newUsername
    case AppAction.incrementCount:
        state.count += 1
    }
    return state
}
```

### Middlewares

Middlewares can be used to dispatch additional actions following an initial action.
Examples for this can be network calls that are triggered by an action and then asynchronously dispatch a completion or error. 

```swift
enum RegisterAction {
    case register(username: String, password: String)
    case usernameTaken
    case passwordTooShort
    case success(LoginToken)
}

func registerMiddleware(getState: @escaping () -> AppState, dispatch: @escaping (Action) -> ()) {
    guard case RegisterAction.register(username: let username, password: let password) else {
        return
    }
    guard password.length >= 8 else {
        dispatch(RegisterAction.passwordTooShort)
        return
    }
    
    checkUsernameAvailability(username) { isAvailable in
        guard isAvailable else {
            dispatch(RegisterAction.usernameTaken)
            return
        }
        
        registerUser(name: username, password: password) { loginToken in
            dispatch(RegisterAction.success(loginToken))
        }
    }
}

func loginMiddleware(getState: @escaping () -> AppState, dispatch: @escaping (Action) -> ()) {
    // ...
}

let store = Store<AppState>(
    initialState: initialState,
    rootReducer: rootReducer,
    middleware: Middlewares.combine(registerMiddleware, loginMiddleware)
)

```

### Sagas

Sagas run asynchronous middleware in regular code through coroutines without the need to nest completion handlers.

```swift
store.runSaga { yield in
    yield(Effects.TakeEvery(RegisterAction.self) { action, yield in
        let state = yield(Effects.Select(AppState.self))
        let response = yield(Effects.Call { completion in
            performRegisterAPICall(state, action, completion: completion)
        })
        if let token = response.token {
            yield(Effects.Put(RegisterAction.success(token)))
        } else {
            yield(Effects.Put(RegisterAction.usernameTaken))
        }
    }
}
```

Each saga is a generator function that yields effects. 
As sagas are implemented using continuations (`setjmp` and `longjmp`), they can run on arbitrary threads without blocking them.
This mechanism allows long running sagas on the main thread (if desired) without the UI being frozen.

#### Effects

The following effects are available through the `Effects` namespace:

- `Select`: Retrieves the current state
- `Put`: Dispatches an action
- `Call`: Performs a method call to a function with a completion handler.
- `Sleep`: Waits for a given time interval (does not block the current thread).
- `Fork`: Runs a saga in parallel to the current saga.
- `Take`: Waits until an action of a given type is dispatched.
- `TakeLeading`: Forks and takes every action of the given type that is dispatched. If another instance of the provided saga is already running, the call is ignored.
- `TakeEvery`: Forks and takes every action of the given type that is dispatched and runs the provided saga with the action as an argument.
- `TakeLatest`: Forks and takes every action of the given type that is dispatched. If another instance of the saga is already running, it is cancelled.
- `Debounce`: Forks and takes every action of the given type that is dispatched. After the action is dispatched, a sleep is performed for the provided interval. If no other instance of the action has been dispatched in the meantime, the provided saga is executed.
- `Throttle`: Forks and takes every action of the given type that is dispatched. If the last dispatch of the action type occurred later than the given time interval ago, the action is ignored.
- `All`: Executes all provided effects in parallel and waits for completion of all of the effects.

### SwiftUI integration

The store can be integrated into a SwiftUI view hierarchy using the `@EnvironmentObject` property wrapper in the `scene` function of the `SceneDelegate`:

```swift
ContentView().environmentObject(store)
```

In every SwiftUI View that is placed in the hierarchy of the content view, it is then possible to access the store as an environment object.

```swift
struct YourView: View {
    @EnvironmentObject let store: Store<AppState>  // automatically set by SwiftUI
    
    var body: some View {
        VStack {
            Text(store.state.username ?? "not logged in")
            Button(
                action: {self.store.dispatch(AppAction.setUsername("John Appleseed"))}, 
                label: {Text("Set Username")}
            )
        }
    }
}
```

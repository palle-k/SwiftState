# SwiftState

Redux-like unidirectional data flow built SwiftUI and Combine

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

### SwiftUI integration

The store can be placed in the `SceneDelegate` class.

```swift
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    var store = Store<AppState>(
        initialState: AppState(username: nil, count: 0),
        rootReducer: rootReducer
    )
}
```

The store can then be integrated into a SwiftUI view hierarchy using the `@EnvironmentObject` property wrapper in the `scene` function of the `SceneDelegate`:

```swift
func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    let window = UIWindow(frame: UIScreen.main.bounds)
    window.rootViewController = UIHostingController(
        rootView: ContentView()
            .environmentObject(self.store)
    )

    self.window = window
    window.makeKeyAndVisible()
}
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

#### SwiftUI Previews

SwiftUI previews are not within the view hierarchy of the root ContentView and thereby require the store environment object to be set manually.

```swift
#if DEBUG
let previewStore = Store<AppState>(...)

struct YourView_Previews: PreviewProvider {
    static var previews: some View {
        YourView(...)
            .environmentObject(previewStore)
    }
}
#endif
```

This store is only used in the preview and therefore can be customized to provide a better preview experience in Xcode.
It can for example be pre-populated with demo data. Additionally, by providing a custom reducer and actions, network calls or other long running middlewares can be avoided.

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

#### Middleware Modifiers

A range of modifiers is provided by the `Middlewares` namespace.
These apply a transformation on the provided middleware(s) to produce a new middleware.

```swift
Middlewares.combine(middleware1, middleware2, ..., middlewareN) 
// combines all middlewares into a single middleware

Middlewares.takeLatest(middleware) 
// only dispatches actions from the latest running instance of the given middleware

Middlewares.filter(predicate, middleware)
// Only runs the middleware when an action is dispatched, that matches the given predicate.

Middlewares.throttle(interval: 1, middleware) 
// All subsequent calls to the middleware that occur within the given interval after the first call to the middleware are ignored.
// Should be combined with Middlewares.filter so the throttling is only applied to the relevant action.

Middlewares.debounce(interval: 1, middleware)
// Runs the middleware if no calls have been made to it within the given interval after the last call.
// Should be combined with Middlewares.filter so the debouncing is only applied to the relevant action.

Middlewares.delay(1, middleware)
// Runs the middleware after the given delay.
```

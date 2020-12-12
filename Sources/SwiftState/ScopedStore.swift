//
//  File.swift
//  
//
//  Created by Palle Klewitz on 12.12.20.
//

import Foundation
import Combine


public class StoreView<GlobalState, SubState: Equatable>: ObservableObject {
    @Published public private(set) var state: SubState
    
    private let store: Store<GlobalState>
    private var disposeBag: Set<AnyCancellable> = []
    private let path: KeyPath<GlobalState, SubState>
    
    public init(viewing substatePath: KeyPath<GlobalState, SubState>, in store: Store<GlobalState>) {
        self.state = store.state[keyPath: substatePath]
        self.store = store
        self.path = substatePath
        
        store.$state
            .map(substatePath)
            .removeDuplicates()
            .sink { [weak self] newValue in
                self?.state = newValue
            }
            .store(in: &disposeBag)
    }
    
    /// Dispatches the action to update the state of the underlying store and to call middlewares.
    /// - Parameter action: Action
    public func dispatch(_ action: Action) {
        self.store.dispatch(action)
    }
    
    /// Adds a middleware to the underlying store.
    /// - Parameter middleware: Middleware to add
    public func addMiddleware(_ middleware: @escaping Middleware<SubState>) {
        let path = self.path
        self.store.addMiddleware { state, action, dispatch in
            middleware({state()[keyPath: path]}, action, dispatch)
        }
    }
    
    /// Actions that are passed through a connected publisher will be dispatched to the underlying store
    /// - Parameter publisher: Publisher to connect
    public func connect<P: Publisher>(to publisher: P) -> AnyCancellable where P.Output: Action, P.Failure == Never {
        self.store.connect(to: publisher)
    }
    
    /// View onto a sub-state of the store that does only update when the value in its scope changes (i.e. duplicates are removed)
    /// - Parameter keyPath: Path to the sub-state
    /// - Returns: A view onto a sub-state of the store
    public func scoped<SubSubState: Equatable>(to keyPath: KeyPath<SubState, SubSubState>) -> StoreView<GlobalState, SubSubState> {
        let absolutePath = self.path.appending(path: keyPath)
        return StoreView<GlobalState, SubSubState>(viewing: absolutePath, in: store)
    }
}

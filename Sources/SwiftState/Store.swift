//
//  Store.swift
//  TransportInfo
//
//  Created by Palle Klewitz on 15.06.19.
//  Copyright (c) 2019 - 2020 Palle Klewitz
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import Foundation
import Combine

public protocol Action {}

public class Store<State> {
    
    let rootReducer: Reducer<State>
    var middleware: Middleware<State>
    
    /// Current state (readonly)
    ///
    /// To modify the state, dispatch an action against the store.
    @Published private(set) public var state: State
    
    
    public init(initialState: State, rootReducer: @escaping Reducer<State>, middleware: @escaping Middleware<State> = {_, _, _ in}) {
        self.state = initialState
        self.rootReducer = rootReducer
        self.middleware = middleware
    }
    
    /// Dispatches the action to update the state of the store and to call middlewares.
    /// - Parameter action: Action
    public func dispatch(_ action: Action) {
        let currentState = state
        
        middleware({self.state}, action, self.dispatch(_:))
        
        let newState = rootReducer(currentState, action)
        self.state = newState
    }
    
    /// Adds a middleware to the store.
    /// - Parameter middleware: Middleware to add
    public func addMiddleware(_ middleware: @escaping Middleware<State>) {
        let existingMiddleware = self.middleware
        self.middleware = { state, action, dispatch in
            existingMiddleware(state, action, dispatch)
            middleware(state, action, dispatch)
        }
    }
    
    /// Actions that are passed through a connected publisher will be dispatched to the store
    /// - Parameter publisher: Publisher to connect
    @discardableResult
    public func connect<P: Publisher>(to publisher: P) -> AnyCancellable where P.Output: Action, P.Failure == Never {
        publisher.sink(receiveValue: self.dispatch)
    }
    
    /// View onto a sub-state of the store that does only update when the value in its scope changes (i.e. duplicates are removed)
    /// - Parameter keyPath: Path to the sub-state
    /// - Returns: A view onto a sub-state of the store
    public func scoped<SubState>(to keyPath: KeyPath<State, SubState>) -> StoreView<State, SubState> {
        StoreView(viewing: keyPath, in: self)
    }
}

extension Store: ObservableObject {}


//
//  Store.swift
//  TransportInfo
//
//  Created by Palle Klewitz on 15.06.19.
//  Copyright © 2019 Palle Klewitz. All rights reserved.
//  Copyright (c) 2019 Palle Klewitz
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
    private let value: CurrentValueSubject<State, Never>
    
    public var didChange: CurrentValueSubject<State, Never> {
        value
    }
    
    let rootReducer: Reducer<State>
    var middleware: Middleware<State>
    
    
    /// Current state (readonly)
    ///
    /// To modify the state, dispatch an action against the store.
    public var state: State {
        value.value
    }
    
    
    public init(initialState: State, rootReducer: @escaping Reducer<State>, middleware: @escaping Middleware<State> = {_, _, _ in}) {
        self.value = CurrentValueSubject(initialState)
        self.rootReducer = rootReducer
        self.middleware = middleware
    }
    
    /// Dispatches the action to update the state of the store and to call middlewares.
    /// - Parameter action: Action
    public func dispatch(_ action: Action) {
        let currentState = value.value
        
        middleware({self.state}, action, self.dispatch(_:))
        
        let newState = rootReducer(currentState, action)
        value.value = newState
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
    public func connect<P: Publisher>(to publisher: P) -> Subscribers.Sink<P> where P.Output: Action, P.Failure == Never {
        publisher.sink(receiveValue: self.dispatch)
    }
}

#if canImport(SwiftUI)
import SwiftUI

extension Store: BindableObject {}
#endif

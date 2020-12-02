//
//  File.swift
//  
//
//  Created by Palle Klewitz on 19.06.19.
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
@_exported import SwiftCoroutine

/// A middleware can be used to dispatch further actions after an initial action.
/// This allows the encapsulation of side effects, such as network calls.
public typealias Middleware<State> = (@escaping () -> State, Action, @escaping (Action) -> ()) -> ()

public enum Middlewares {}

public extension Middlewares {
    /// Merges the given middlewares into a single middleware
    /// - Parameter middlewares: Middlewares to merge
    static func combine<State>(_ middlewares: [Middleware<State>]) -> Middleware<State> {
        { state, action, dispatch in
            for middleware in middlewares {
                middleware(state, action, dispatch)
            }
        }
    }
    
    /// Merges the given middlewares into a single middleware
    /// - Parameter middlewares: Middlewares to merge
    static func combine<State>(_ middlewares: Middleware<State>...) -> Middleware<State> {
        combine(middlewares)
    }
    
    /// Modifying a middleware with takeLatest prevents previously spawned middlewares from dispatching further actions when running the middleware again.
    /// - Parameter middleware: Middleware to modify
    static func takeLatest<State>(_ middleware: @escaping Middleware<State>) -> Middleware<State> {
        var changeToken = 0
        
        return { state, action, dispatch in
            changeToken += 1
            let currentChangeToken = changeToken
            
            let filteredDispatch = { (action: Action) in
                if changeToken == currentChangeToken {
                    dispatch(action)
                }
            }
            
            middleware(state, action, filteredDispatch)
        }
    }
    
    /// Modifying a middleware with takeLatest prevents previously spawned middlewares from dispatching further actions when running the middleware again.
    /// - Parameter middleware: Middleware to modify
    static func takeLatest<State, ActionType: Action>(_ pattern: ActionType.Type, _ middleware: @escaping Middleware<State>) -> Middleware<State> {
        return filter({$0 is ActionType}, takeLatest(middleware))
    }
    
    /// Throttles calls to the provided middleware
    /// - Parameter interval: Minimum interval in seconds between calls to the middleware
    /// - Parameter middleware: Middleware to modify
    static func throttle<State>(interval: TimeInterval, _ middleware: @escaping Middleware<State>) -> Middleware<State> {
        var lastCall: Date? = nil
        
        return { state, action, dispatch in
            if let lc = lastCall, Date().timeIntervalSince(lc) < interval {
                return
            }
            lastCall = Date()
            middleware(state, action, dispatch)
        }
    }
    
    /// Throttles calls to the provided middleware
    /// - Parameter interval: Minimum interval in seconds between calls to the middleware
    /// - Parameter middleware: Middleware to modify
    static func throttle<State, ActionType: Action>(_ pattern: ActionType.Type, interval: TimeInterval, _ middleware: @escaping Middleware<State>) -> Middleware<State> {
        return filter({$0 is ActionType}, throttle(interval: interval, middleware))
    }
    
    /// Runs the middleware if it has not been called in the given interval after the last call
    /// - Parameter interval: Interval to wait for in seconds
    /// - Parameter main: DispatchQueue to run the middleware on
    /// - Parameter middleware: Middleware to modify
    static func debounce<State>(interval: TimeInterval, on queue: DispatchQueue = .main, _ middleware: @escaping Middleware<State>) -> Middleware<State> {
        var changeToken = 0
        
        return { state, action, dispatch in
            changeToken += 1
            let currentChangeToken = changeToken
            
            let filteredDispatch = { (action: Action) in
                if changeToken == currentChangeToken {
                    dispatch(action)
                }
            }
            
            queue.asyncAfter(deadline: .now() + interval) {
                middleware(state, action, filteredDispatch)
            }
        }
    }
    
    /// Runs the middleware if it has not been called in the given interval after the last call
    /// - Parameter interval: Interval to wait for in seconds
    /// - Parameter main: DispatchQueue to run the middleware on
    /// - Parameter middleware: Middleware to modify
    static func debounce<State, ActionType: Action>(_ pattern: ActionType.Type, interval: TimeInterval, _ middleware: @escaping Middleware<State>) -> Middleware<State> {
        return filter({$0 is ActionType}, debounce(interval: interval, middleware))
    }
    
    /// Delays calls to the given middleware by the given interval.
    /// - Parameter interval: Delay interval in seconds
    /// - Parameter main: DispatchQueue to run the middleware on
    /// - Parameter middleware: Middleware to modify
    static func delay<State>(duration: TimeInterval, on queue: DispatchQueue = .main, _ middleware: @escaping Middleware<State>) -> Middleware<State> {
        return { state, action, dispatch in
            queue.asyncAfter(deadline: .now() + duration) {
                middleware(state, action, dispatch)
            }
        }
    }
    
    /// Delays calls to the given middleware by the given interval.
    /// - Parameter interval: Delay interval in seconds
    /// - Parameter main: DispatchQueue to run the middleware on
    /// - Parameter middleware: Middleware to modify
    static func delay<State, ActionType: Action>(_ pattern: ActionType.Type, duration: TimeInterval, on queue: DispatchQueue = .main, _ middleware: @escaping Middleware<State>) -> Middleware<State> {
        return filter({$0 is ActionType}, delay(duration: duration, on: queue, middleware))
    }
    
    /// Only calls the middleware when the action matches the given predicate
    /// - Parameter predicate: Predicate to match
    /// - Parameter middleware: Middleware to modify
    static func filter<State>(_ predicate: @escaping (Action) -> Bool, _ middleware: @escaping Middleware<State>) -> Middleware<State> {
        return { state, action, dispatch in
            if predicate(action) {
                middleware(state, action, dispatch)
            }
        }
    }
    
    /// Only calls the middleware when the action matches the given predicate
    /// - Parameter predicate: Predicate to match
    /// - Parameter middleware: Middleware to modify
    static func map<State, Substate>(_ keyPath: KeyPath<State, Substate>, _ middleware: @escaping Middleware<Substate>) -> Middleware<State> {
        return { state, action, dispatch in
            middleware({state()[keyPath: keyPath]}, action, dispatch)
        }
    }
}

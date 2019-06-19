//
//  File.swift
//  
//
//  Created by Palle Klewitz on 19.06.19.
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

public typealias Reducer<State> = (State, Action) -> State

public enum Reducers {
    public static func combine<State, SubStateA, SubStateB>(
        _ a: (WritableKeyPath<State, SubStateA>, Reducer<SubStateA>),
        _ b: (WritableKeyPath<State, SubStateB>, Reducer<SubStateB>)
        ) -> Reducer<State> {
        return { state, action -> State in
            var newState = state
            
            newState[keyPath: a.0] = a.1(newState[keyPath: a.0], action)
            newState[keyPath: b.0] = b.1(newState[keyPath: b.0], action)
            
            return newState
        }
    }
    
    public static func combine<State, SubStateA, SubStateB, SubStateC>(
        _ a: (WritableKeyPath<State, SubStateA>, Reducer<SubStateA>),
        _ b: (WritableKeyPath<State, SubStateB>, Reducer<SubStateB>),
        _ c: (WritableKeyPath<State, SubStateC>, Reducer<SubStateC>)
        ) -> Reducer<State> {
        return { state, action -> State in
            var newState = state
            
            newState[keyPath: a.0] = a.1(newState[keyPath: a.0], action)
            newState[keyPath: b.0] = b.1(newState[keyPath: b.0], action)
            newState[keyPath: c.0] = c.1(newState[keyPath: c.0], action)
            
            return newState
        }
    }
    
    public static func combine<State, SubStateA, SubStateB, SubStateC, SubStateD>(
        _ a: (WritableKeyPath<State, SubStateA>, Reducer<SubStateA>),
        _ b: (WritableKeyPath<State, SubStateB>, Reducer<SubStateB>),
        _ c: (WritableKeyPath<State, SubStateC>, Reducer<SubStateC>),
        _ d: (WritableKeyPath<State, SubStateD>, Reducer<SubStateD>)
        ) -> Reducer<State> {
        return { state, action -> State in
            var newState = state
            
            newState[keyPath: a.0] = a.1(newState[keyPath: a.0], action)
            newState[keyPath: b.0] = b.1(newState[keyPath: b.0], action)
            newState[keyPath: c.0] = c.1(newState[keyPath: c.0], action)
            newState[keyPath: d.0] = d.1(newState[keyPath: d.0], action)
            
            return newState
        }
    }
    
    public static func combine<State, SubStateA, SubStateB, SubStateC, SubStateD, SubStateE>(
        _ a: (WritableKeyPath<State, SubStateA>, Reducer<SubStateA>),
        _ b: (WritableKeyPath<State, SubStateB>, Reducer<SubStateB>),
        _ c: (WritableKeyPath<State, SubStateC>, Reducer<SubStateC>),
        _ d: (WritableKeyPath<State, SubStateD>, Reducer<SubStateD>),
        _ e: (WritableKeyPath<State, SubStateE>, Reducer<SubStateE>)
        ) -> Reducer<State> {
        return { state, action -> State in
            var newState = state
            
            newState[keyPath: a.0] = a.1(newState[keyPath: a.0], action)
            newState[keyPath: b.0] = b.1(newState[keyPath: b.0], action)
            newState[keyPath: c.0] = c.1(newState[keyPath: c.0], action)
            newState[keyPath: d.0] = d.1(newState[keyPath: d.0], action)
            newState[keyPath: e.0] = e.1(newState[keyPath: e.0], action)
            
            return newState
        }
    }
    
    public static func combine<State, SubStateA, SubStateB, SubStateC, SubStateD, SubStateE, SubStateF>(
        _ a: (WritableKeyPath<State, SubStateA>, Reducer<SubStateA>),
        _ b: (WritableKeyPath<State, SubStateB>, Reducer<SubStateB>),
        _ c: (WritableKeyPath<State, SubStateC>, Reducer<SubStateC>),
        _ d: (WritableKeyPath<State, SubStateD>, Reducer<SubStateD>),
        _ e: (WritableKeyPath<State, SubStateE>, Reducer<SubStateE>),
        _ f: (WritableKeyPath<State, SubStateF>, Reducer<SubStateF>)
        ) -> Reducer<State> {
        return { state, action -> State in
            var newState = state
            
            newState[keyPath: a.0] = a.1(newState[keyPath: a.0], action)
            newState[keyPath: b.0] = b.1(newState[keyPath: b.0], action)
            newState[keyPath: c.0] = c.1(newState[keyPath: c.0], action)
            newState[keyPath: d.0] = d.1(newState[keyPath: d.0], action)
            newState[keyPath: e.0] = e.1(newState[keyPath: e.0], action)
            newState[keyPath: f.0] = f.1(newState[keyPath: f.0], action)
            
            return newState
        }
    }
}

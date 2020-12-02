//
//  Effects.swift
//  
//
//  Created by Palle Klewitz on 02.12.20.
//  Copyright (c) 2020 Palle Klewitz
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


public enum Effects {}

public extension Effects {
    struct Select<State, Substate>: Effect {
        public typealias Response = Substate
        
        let keyPath: KeyPath<State, Substate>
        
        public init(_ keyPath: KeyPath<State, Substate>) {
            self.keyPath = keyPath
        }
        
        public func perform(in environment: EffectEnvironment) -> Substate {
            (environment.state() as! State)[keyPath: keyPath]
        }
    }
    
    struct Put: Effect {
        public typealias Response = Void
        let action: Action
        
        public init(action: Action) {
            self.action = action
        }
        
        public func perform(in environment: EffectEnvironment) {
            environment.dispatch(action)
        }
    }
    
    struct Call<Output>: Effect {
        public typealias Response = Output
        
        let execute: (_ completion: @escaping (Output) -> Void) -> Void
        
        public init(_ execute: @escaping (_ completion: @escaping (Output) -> Void) -> Void) {
            self.execute = execute
        }
        
        public func perform(in environment: EffectEnvironment) -> Output {
            (try! Coroutine.await(self.execute))
        }
    }
    
    struct Sleep: Effect {
        public typealias Response = Void
        
        let interval: TimeInterval
        
        public init(_ interval: TimeInterval) {
            self.interval = interval
        }
        
        public func perform(in environment: EffectEnvironment) -> Void {
            try! Coroutine.await { completion in
                environment.queue.asyncAfter(
                    deadline: .now() + .nanoseconds(Int(self.interval * TimeInterval(NSEC_PER_SEC))),
                    execute: completion
                )
            }
        }
    }
    
    struct Fork: Effect {
        public typealias Response = Void
        
        let saga: VoidSaga
        
        public init(_ saga: @escaping VoidSaga) {
            self.saga = saga
        }
        
        public func perform(in environment: EffectEnvironment) -> Void {
            startSaga(self.saga, in: environment)
        }
    }
    
    struct Take<ActionType: Action>: Effect {
        public typealias Response = ActionType
        
        public init(_: ActionType.Type) {}
        
        public func perform(in environment: EffectEnvironment) -> ActionType {
            let actionChannel = environment.actions()
            while true {
                if let action = try! actionChannel.awaitReceive() as? ActionType {
                    return action
                }
            }
        }
    }
    
    struct TakeLeading<ActionType: Action>: Effect {
        public typealias Response = Void
        
        let saga: Saga<ActionType>
        
        
        public init(_: ActionType.Type, _ saga: @escaping Saga<ActionType>) {
            self.saga = saga
        }
        
        public func perform(in environment: EffectEnvironment) -> Void {
            let forkEffect = Fork { yield in
                while true {
                    let action = try yield(Take(ActionType.self))
                    try self.saga(action, yield)
                }
            }
            return forkEffect.perform(in: environment)
        }
    }
    
    struct TakeEvery<ActionType: Action>: Effect {
        public typealias Response = Void
        
        let saga: Saga<ActionType>
        
        
        public init(_: ActionType.Type, _ saga: @escaping Saga<ActionType>) {
            self.saga = saga
        }
        
        public func perform(in environment: EffectEnvironment) -> Void {
            let forkEffect = Effects.Fork { yield in
                while true {
                    let action = try yield(Take(ActionType.self))
                    
                    startSaga(
                        { yield in
                            try self.saga(action, yield)
                        },
                        in: environment
                    )
                }
            }
            return forkEffect.perform(in: environment)
        }
    }
    
    struct TakeLatest<ActionType: Action>: Effect {
        public typealias Response = Void
        
        let saga: Saga<ActionType>
        
        public init(_: ActionType.Type, _ saga: @escaping Saga<ActionType>) {
            self.saga = saga
        }
        
        public func perform(in environment: EffectEnvironment) -> Void {
            let forkEffect = Effects.Fork { yield in
                var currentHandle: SagaHandle? = nil
                while true {
                    let action = try yield(Take(ActionType.self))
                    currentHandle?.cancel()
                    currentHandle = startSaga(
                        { yield in
                            try self.saga(action, yield)
                        },
                        in: environment
                    )
                }
            }
            return forkEffect.perform(in: environment)
        }
    }
    
    struct Debounce<ActionType: Action>: Effect {
        public typealias Response = Void
        
        let saga: Saga<ActionType>
        let interval: TimeInterval
        
        public init(_: ActionType.Type, interval: TimeInterval, _ saga: @escaping Saga<ActionType>) {
            self.saga = saga
            self.interval = interval
        }
        
        public func perform(in environment: EffectEnvironment) -> Void {
            let forkEffect = Effects.Fork { yield in
                var token: Int = 0
                while true {
                    let action = try yield(Take(ActionType.self))
                    token += 1
                    let currentToken = token
                    try yield(Effects.Fork { yield in
                        try yield(Sleep(self.interval))
                        if token != currentToken {
                            return
                        }
                        try self.saga(action, yield)
                    })
                }
            }
            return forkEffect.perform(in: environment)
        }
    }
    
    struct All: Effect {
        public typealias Response = Void
        
        let effects: [AnyEffect]
        
        public init(_ effects: [AnyEffect]) {
            self.effects = effects
        }
        
        public func perform(in environment: EffectEnvironment) -> Void {
            for effect in effects {
                _ = effect.perform(in: environment)
            }
        }
    }
}

public extension Effects.Select where State == Substate {
    init() {
        self.init(\.self)
    }
    
    init(_: State.Type) {
        self.init(\.self)
    }
}

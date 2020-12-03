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
import SwiftCoroutine

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
}

public extension Effects.Select where State == Substate {
    init(_: State.Type = State.self) {
        self.init(\.self)
    }
}

public extension Yielder {
    func select<State>(_ type: State.Type = State.self) throws -> State {
        try self(Effects.Select(\State.self))
    }
    
    func select<State, SubState>(_ path: KeyPath<State, SubState>) throws -> SubState {
        try self(Effects.Select(path))
    }
}

public extension Effects {
    struct Put: Effect {
        let action: Action
        
        public init(action: Action) {
            self.action = action
        }
        
        public func perform(in environment: EffectEnvironment) {
            environment.dispatch(action)
        }
    }
}

public extension Yielder {
    func put(_ action: Action) throws {
        try self(Effects.Put(action: action))
    }
}

public extension Effects {
    struct Call<Output>: Effect {
        let execute: (_ completion: @escaping (Output) -> Void) -> Void
        
        public init(_ execute: @escaping (_ completion: @escaping (Output) -> Void) -> Void) {
            self.execute = execute
        }
        
        public func perform(in environment: EffectEnvironment) throws -> Output {
            try Coroutine.await(self.execute)
        }
    }
}

public extension Yielder {
    func call<Output>(_ execute: @escaping (_ completion: @escaping (Output) -> Void) -> Void) throws -> Output {
        try self(Effects.Call(execute))
    }
}

public extension Effects {
    struct Sleep: Effect {
        let interval: TimeInterval
        
        public init(_ interval: TimeInterval) {
            self.interval = interval
        }
        
        public func perform(in environment: EffectEnvironment) throws -> Void {
            try Coroutine.await { completion in
                environment.queue.asyncAfter(
                    deadline: .now() + .nanoseconds(Int(self.interval * TimeInterval(NSEC_PER_SEC))),
                    execute: completion
                )
            }
        }
    }
}

public extension Yielder {
    func sleep(_ interval: TimeInterval) throws {
        try self(Effects.Sleep(interval))
    }
}

public extension Effects {
    struct Fork: Effect {
        let saga: VoidSaga
        let queue: DispatchQueue?
        
        public init(_ saga: @escaping VoidSaga, on queue: DispatchQueue? = nil) {
            self.saga = saga
            self.queue = queue
        }
        
        @discardableResult
        public func perform(in environment: EffectEnvironment) -> SagaHandle {
            var environment = environment
            environment.queue = self.queue ?? environment.queue
            return startSaga(self.saga, in: environment)
        }
    }
}

public extension Yielder {
    func fork<Input>(_ input: Input, _ perform: @escaping Saga<Input>) throws -> SagaHandle {
        try self.fork { yield in
            try perform(input, yield)
        }
    }
    
    func fork(_ perform: @escaping VoidSaga) throws -> SagaHandle {
        try self(Effects.Fork(perform))
    }
}

public extension Effects {
    struct Take<ActionType: Action>: Effect {
        let predicate: (ActionType) -> Bool
        
        public init(_: ActionType.Type = ActionType.self, predicate: @escaping (ActionType) -> Bool = {_ in true}) {
            self.predicate = predicate
        }
        
        public func perform(in environment: EffectEnvironment) throws -> ActionType {
            let actionChannel = environment.actions()
            while true {
                if let action = try actionChannel.awaitReceive() as? ActionType, predicate(action) {
                    return action
                }
            }
        }
    }
}

fileprivate extension Effects {
    struct MapEffect<Source: Effect, Output>: Effect {
        let effect: Source
        let mapping: (Source.Response) -> Output
        
        init(_ effect: Source, _ transform: @escaping (Source.Response) -> Output) {
            self.effect = effect
            self.mapping = transform
        }
        
        func perform(in environment: EffectEnvironment) throws -> Output {
            let result = try self.effect.perform(in: environment)
            return mapping(result)
        }
    }
}

public extension Yielder {
    func take<ActionType: Action>(_: ActionType.Type = ActionType.self, predicate: @escaping (ActionType) -> Bool = {_ in true}) throws -> ActionType {
        try self(Effects.Take(ActionType.self, predicate: predicate))
    }
    
    func take<ActionType: Action>(timeout: TimeInterval, _: ActionType.Type = ActionType.self, predicate: @escaping (ActionType) -> Bool = {_ in true}) throws -> ActionType? {
        var result: ActionType?
        
        try self.first(
            Effects.MapEffect<Effects.Take<ActionType>, Void>(
                Effects.Take(ActionType.self, predicate: predicate),
                { res in
                    result = res
                }
            ),
            Effects.Sleep(timeout)
        )
        
        return result
    }
}

public extension Effects {
    struct TakeEvent<Event>: Effect {
        let channel: EventChannel<Event>
        
        public init(_ channel: EventChannel<Event>) {
            self.channel = channel
        }
        
        public func perform(in environment: EffectEnvironment) -> Event {
            self.channel.next()
        }
    }
}

public extension Yielder {
    func take<Event>(_ channel: EventChannel<Event>) throws -> Event {
        try self(Effects.TakeEvent(channel))
    }
}

public extension Effects {
    struct TakeLeading<ActionType: Action>: Effect {
        let saga: Saga<ActionType>
        let predicate: (ActionType) -> Bool
        
        
        public init(_: ActionType.Type = ActionType.self, predicate: @escaping (ActionType) -> Bool = {_ in true}, saga: @escaping Saga<ActionType>) {
            self.saga = saga
            self.predicate = predicate
        }
        
        public func perform(in environment: EffectEnvironment) throws -> SagaHandle {
            let forkEffect = Fork { yield in
                while true {
                    let action = try yield.take(ActionType.self, predicate: self.predicate)
                    try self.saga(action, yield)
                }
            }
            return forkEffect.perform(in: environment)
        }
    }
}

public extension Yielder {
    func takeLeading<ActionType: Action>(_: ActionType.Type = ActionType.self, predicate: @escaping (ActionType) -> Bool = {_ in true}, saga: @escaping Saga<ActionType>) throws -> SagaHandle {
        try self(Effects.TakeLeading(ActionType.self, predicate: predicate, saga: saga))
    }
}

public extension Effects {
    struct TakeEvery<ActionType: Action>: Effect {
        let saga: Saga<ActionType>
        let predicate: (ActionType) -> Bool
        
        public init(_: ActionType.Type = ActionType.self, predicate: @escaping (ActionType) -> Bool = {_ in true}, saga: @escaping Saga<ActionType>) {
            self.saga = saga
            self.predicate = predicate
        }
        
        public func perform(in environment: EffectEnvironment) throws -> SagaHandle {
            let forkEffect = Effects.Fork { yield in
                while true {
                    let action = try yield(Take(ActionType.self, predicate: self.predicate))
                    
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
}

public extension Yielder {
    func takeEvery<ActionType: Action>(_: ActionType.Type = ActionType.self, predicate: @escaping (ActionType) -> Bool = {_ in true}, saga: @escaping Saga<ActionType>) throws -> SagaHandle {
        try self(Effects.TakeEvery(ActionType.self, predicate: predicate, saga: saga))
    }
}

public extension Effects {
    struct TakeLatest<ActionType: Action>: Effect {
        let saga: Saga<ActionType>
        let predicate: (ActionType) -> Bool
        
        public init(_: ActionType.Type = ActionType.self, predicate: @escaping (ActionType) -> Bool = {_ in true}, saga: @escaping Saga<ActionType>) {
            self.saga = saga
            self.predicate = predicate
        }
        
        public func perform(in environment: EffectEnvironment) throws -> SagaHandle {
            let forkEffect = Effects.Fork { yield in
                var currentHandle: SagaHandle? = nil
                while true {
                    let action = try yield(Take(ActionType.self, predicate: self.predicate))
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
}

public extension Yielder {
    func takeLatest<ActionType: Action>(_: ActionType.Type = ActionType.self, predicate: @escaping (ActionType) -> Bool = {_ in true}, saga: @escaping Saga<ActionType>) throws -> SagaHandle {
        try self(Effects.TakeLatest(ActionType.self, predicate: predicate, saga: saga))
    }
}

public extension Effects {
    struct Debounce<ActionType: Action>: Effect {
        let saga: Saga<ActionType>
        let interval: TimeInterval
        let predicate: (ActionType) -> Bool
        
        public init(interval: TimeInterval, _: ActionType.Type = ActionType.self, predicate: @escaping (ActionType) -> Bool = {_ in true}, saga: @escaping Saga<ActionType>) {
            self.saga = saga
            self.interval = interval
            self.predicate = predicate
        }
        
        public func perform(in environment: EffectEnvironment) throws -> SagaHandle {
            let forkEffect = Effects.Fork { yield in
                var token: Int = 0
                while true {
                    let action = try yield(Take(ActionType.self, predicate: predicate))
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
}

public extension Yielder {
    func debounce<ActionType: Action>(interval: TimeInterval, _: ActionType.Type = ActionType.self, predicate: @escaping (ActionType) -> Bool = {_ in true}, saga: @escaping Saga<ActionType>) throws -> SagaHandle {
        try self(Effects.Debounce(interval: interval, ActionType.self, predicate: predicate, saga: saga))
    }
}

public extension Effects {
    struct Throttle<ActionType: Action>: Effect {
        let saga: Saga<ActionType>
        let interval: TimeInterval
        let predicate: (ActionType) -> Bool
        
        public init(interval: TimeInterval, _: ActionType.Type = ActionType.self, predicate: @escaping (ActionType) -> Bool = {_ in true}, saga: @escaping Saga<ActionType>) {
            self.saga = saga
            self.interval = interval
            self.predicate = predicate
        }
        
        public func perform(in environment: EffectEnvironment) -> SagaHandle {
            let forkEffect = Effects.Fork { yield in
                var idle = true
                while true {
                    let action = try yield(Take(ActionType.self, predicate: predicate))
                    if !idle {
                        continue
                    }
                    idle = false
                    try yield(Effects.Fork { yield in
                        try self.saga(action, yield)
                    })
                    try yield(Effects.Fork { yield in
                        try yield(Sleep(self.interval))
                        idle = true
                    })
                }
            }
            return forkEffect.perform(in: environment)
        }
    }
}

public extension Yielder {
    func throttle<ActionType: Action>(interval: TimeInterval, _: ActionType.Type = ActionType.self, predicate: @escaping (ActionType) -> Bool = {_ in true}, saga: @escaping Saga<ActionType>) throws -> SagaHandle {
        try self(Effects.Throttle(interval: interval, ActionType.self, predicate: predicate, saga: saga))
    }
}

public extension Effects {
    struct All<BaseEffect: Effect>: Effect {
        let effects: [BaseEffect]
        
        public init(_ effects: [BaseEffect]) {
            self.effects = effects
        }
        
        public func perform(in environment: EffectEnvironment) throws -> [BaseEffect.Response] {
            try Coroutine.await { completion in
                var results = Array(repeating: BaseEffect.Response?.none, count: self.effects.count)
                var completedCount = 0
                
                if effects.count == 0 {
                    return completion([])
                }
                
                for (idx, effect) in effects.enumerated() {
                    startSaga(
                        { yield in
                            let result = try yield(effect)
                            results[idx] = result
                            completedCount += 1
                            if completedCount == effects.count {
                                completion(results.compactMap {$0})
                            }
                        },
                        in: environment
                    )
                }
            }
        }
    }
}

public extension Yielder {
    func all<BaseEffect: Effect>(_ effects: [BaseEffect]) throws -> [BaseEffect.Response] {
        try self(Effects.All(effects))
    }
    
    func all<BaseEffect: Effect>(_ effects: BaseEffect...) throws -> [BaseEffect.Response] {
        try self.all(effects)
    }
    
    @discardableResult
    func all(_ effects: [AnyEffectConvertible]) throws -> [Any] {
        try self.all(effects.map {$0.wrapped()})
    }
    
    @discardableResult
    func all(_ effects: AnyEffectConvertible...) throws -> [Any] {
        try all(effects)
    }
}

public extension Effects {
    struct First<BaseEffect: Effect>: Effect {
        let effects: [BaseEffect]
        
        public init(_ effects: [BaseEffect]) {
            self.effects = effects
        }
        
        public func perform(in environment: EffectEnvironment) throws -> BaseEffect.Response {
            try Coroutine.await { completion in
                var handles: [SagaHandle] = []
                handles.reserveCapacity(self.effects.count)
                
                for effect in self.effects {
                    let handle = startSaga({ yield in
                        let result = try yield(effect)
                        completion(result)
                        handles.forEach { handle in
                            handle.cancel()
                        }
                    }, in: environment)
                    handles.append(handle)
                }
            }
        }
    }
}

public extension Yielder {
    func first<BaseEffect: Effect>(_ effects: [BaseEffect]) throws -> BaseEffect.Response {
        try self(Effects.First(effects))
    }
    
    func first<BaseEffect: Effect>(_ effects: BaseEffect...) throws -> BaseEffect.Response {
        try self.first(effects)
    }
    
    @discardableResult
    func first(_ effects: [AnyEffectConvertible]) throws -> Any {
        try self(Effects.First(effects.map {$0.wrapped()}))
    }
    
    @discardableResult
    func first(_ effects: AnyEffectConvertible...) throws -> Any {
        try self.first(effects)
    }
}

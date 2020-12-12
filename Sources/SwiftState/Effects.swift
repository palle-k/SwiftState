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
    
    static func select<State>(_ type: State.Type = State.self) -> Effects.Select<State, State> {
        Effects.Select(\State.self)
    }
    
    static func select<State, SubState>(_ path: KeyPath<State, SubState>) -> Effects.Select<State, SubState> {
        Effects.Select(path)
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
            if environment.queue == DispatchQueue.main {
                environment.dispatch(action)
            } else {
                DispatchQueue.main.sync {
                    environment.dispatch(action)
                }
            }
        }
    }
    
    static func put(_ action: Action) -> Effects.Put {
        Effects.Put(action: action)
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
    
    static func call<Output>(_ execute: @escaping (_ completion: @escaping (Output) -> Void) -> Void) -> Effects.Call<Output> {
        Effects.Call(execute)
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
    
    static func sleep(_ interval: TimeInterval) -> Effects.Sleep {
        Effects.Sleep(interval)
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
    
    static func fork(on queue: DispatchQueue? = nil, _ perform: @escaping VoidSaga) -> Effects.Fork {
        Effects.Fork(perform, on: queue)
    }
}

public extension Yielder {
    @discardableResult
    func fork<Input>(_ input: Input, _ perform: @escaping Saga<Input>) throws -> SagaHandle {
        try self.fork { yield in
            try perform(input, yield)
        }
    }
    
    @discardableResult
    func fork(_ perform: @escaping VoidSaga) throws -> SagaHandle {
        try self(Effects.Fork(perform))
    }
}

public extension Effects {
    struct Take<Output>: Effect {
        let mapping: (Action) -> Output?
        
        public init(predicate: @escaping (Action) -> Bool = {_ in true}) where Output == Action {
            self.mapping = { action in
                predicate(action) ? action : nil
            }
        }
        
        public init(_: Output.Type = Output.self, predicate: @escaping (Output) -> Bool = {_ in true}) where Output: Action {
            self.mapping = { action in
                (action as? Output).flatMap { action in
                    predicate(action) ? action : nil
                }
            }
        }
        
        public init(_ mapping: @escaping (Action) -> Output?) {
            self.mapping = mapping
        }
        
        public func perform(in environment: EffectEnvironment) throws -> Output {
            let actionChannel = environment.actions()
            while true {
                let action = try actionChannel.awaitReceive()
                if let result = mapping(action) {
                    actionChannel.close()
                    return result
                }
            }
        }
    }
    
    static func take<Output: Action>(_: Output.Type = Output.self, predicate: @escaping (Output) -> Bool = {_ in true}) -> Effects.Take<Output> {
        Effects.Take(Output.self, predicate: predicate)
    }
    
    static func take(predicate: @escaping (Action) -> Bool = {_ in true}) -> Effects.Take<Action> {
        Effects.Take(predicate: predicate)
    }
    
    static func take<Output>(_ mapping: @escaping (Action) -> Output?) -> Effects.Take<Output> {
        Effects.Take(mapping)
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
    
    static func take<ActionType: Action>(timeout: TimeInterval, _: ActionType.Type = ActionType.self, predicate: @escaping (ActionType) -> Bool = {_ in true}) -> Effects.First<GenericEffect<ActionType?>> {
        Effects.First<GenericEffect<ActionType?>>([
            Effects.MapEffect<Effects.Take<ActionType>, ActionType?>(
                Effects.Take(ActionType.self, predicate: predicate),
                { res -> ActionType? in
                    res
                }
            ).generic(),
            Effects.MapEffect<Effects.Sleep, ActionType?>(
                Effects.Sleep(timeout),
                {_ in nil}
            ).generic()
        ])
    }
}

public extension Yielder {
    func take<ActionType: Action>(_: ActionType.Type = ActionType.self, predicate: @escaping (ActionType) -> Bool = {_ in true}) throws -> ActionType {
        try self(Effects.take(ActionType.self, predicate: predicate))
    }
    
    func take<ActionType: Action>(timeout: TimeInterval, _: ActionType.Type = ActionType.self, predicate: @escaping (ActionType) -> Bool = {_ in true}) throws -> ActionType? {
        return try self(Effects.take(timeout: timeout, ActionType.self, predicate: predicate).generic())
    }
    
    func take(predicate: @escaping (Action) -> Bool = {_ in true}) throws -> Action {
        try self(Effects.Take(predicate: predicate))
    }
    
    func take<Output>(_ mapping: @escaping (Action) -> Output?) throws -> Output {
        try self(Effects.Take(mapping))
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
    
    static func take<Event>(_ channel: EventChannel<Event>) -> TakeEvent<Event> {
        Effects.TakeEvent(channel)
    }
}

public extension Yielder {
    func take<Event>(_ channel: EventChannel<Event>) throws -> Event {
        try self(Effects.TakeEvent(channel))
    }
}

public extension Effects {
    struct TakeLeading<Output>: Effect {
        let saga: Saga<Output>
        let mapping: (Action) -> Output?
        
        public init(predicate: @escaping (Action) -> Bool = {_ in true}, saga: @escaping Saga<Output>) where Output == Action {
            self.mapping = { action in
                predicate(action) ? action : nil
            }
            self.saga = saga
        }
        
        public init(_: Output.Type = Output.self, predicate: @escaping (Output) -> Bool = {_ in true}, saga: @escaping Saga<Output>) where Output: Action {
            self.mapping = { action in
                (action as? Output).flatMap { action in
                    predicate(action) ? action : nil
                }
            }
            self.saga = saga
        }
        
        public init(_ mapping: @escaping (Action) -> Output?, saga: @escaping Saga<Output>) {
            self.mapping = mapping
            self.saga = saga
        }
        
        public func perform(in environment: EffectEnvironment) throws -> SagaHandle {
            let forkEffect = Fork { yield in
                while true {
                    let action = try yield(Effects.take(mapping))
                    try self.saga(action, yield)
                }
            }
            return forkEffect.perform(in: environment)
        }
    }
    
    static func takeLeading<ActionType: Action>(_: ActionType.Type = ActionType.self, predicate: @escaping (ActionType) -> Bool = {_ in true}, saga: @escaping Saga<ActionType>) -> Effects.TakeLeading<ActionType> {
        Effects.TakeLeading(ActionType.self, predicate: predicate, saga: saga)
    }
    
    static func takeLeading(predicate: @escaping (Action) -> Bool, saga: @escaping Saga<Action>) -> Effects.TakeLeading<Action> {
        Effects.TakeLeading(predicate: predicate, saga: saga)
    }
    
    static func takeLeading<Output>(_ mapping: @escaping (Action) -> Output, saga: @escaping Saga<Output>) -> Effects.TakeLeading<Output> {
        Effects.TakeLeading(mapping, saga: saga)
    }
}

public extension Yielder {
    @discardableResult
    func takeLeading<ActionType: Action>(_: ActionType.Type = ActionType.self, predicate: @escaping (ActionType) -> Bool = {_ in true}, saga: @escaping Saga<ActionType>) throws -> SagaHandle {
        try self(Effects.takeLeading(ActionType.self, predicate: predicate, saga: saga))
    }
    
    @discardableResult
    func takeLeading(predicate: @escaping (Action) -> Bool, saga: @escaping Saga<Action>) throws -> SagaHandle {
        try self(Effects.TakeLeading(predicate: predicate, saga: saga))
    }
    
    @discardableResult
    func takeLeading<Output>(_ mapping: @escaping (Action) -> Output, saga: @escaping Saga<Output>) throws -> SagaHandle {
        try self(Effects.TakeLeading(mapping, saga: saga))
    }
}

public extension Effects {
    struct TakeEvery<Output>: Effect {
        let saga: Saga<Output>
        let mapping: (Action) -> Output?
        
        public init(predicate: @escaping (Action) -> Bool = {_ in true}, saga: @escaping Saga<Output>) where Output == Action {
            self.mapping = { action in
                predicate(action) ? action : nil
            }
            self.saga = saga
        }
        
        public init(_: Output.Type = Output.self, predicate: @escaping (Output) -> Bool = {_ in true}, saga: @escaping Saga<Output>) where Output: Action {
            self.mapping = { action in
                (action as? Output).flatMap { action in
                    predicate(action) ? action : nil
                }
            }
            self.saga = saga
        }
        
        public init(_ mapping: @escaping (Action) -> Output?, saga: @escaping Saga<Output>) {
            self.mapping = mapping
            self.saga = saga
        }
        
        public func perform(in environment: EffectEnvironment) throws -> SagaHandle {
            let forkEffect = Effects.Fork { yield in
                while true {
                    let action = try yield(Take(mapping))
                    
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
    
    static func takeEvery<Output: Action>(_: Output.Type = Output.self, predicate: @escaping (Output) -> Bool = {_ in true}, saga: @escaping Saga<Output>) -> Effects.TakeEvery<Output> {
        Effects.TakeEvery(Output.self, predicate: predicate, saga: saga)
    }
    
    static func takeEvery(predicate: @escaping (Action) -> Bool, saga: @escaping Saga<Action>) -> Effects.TakeEvery<Action> {
        Effects.TakeEvery(predicate: predicate, saga: saga)
    }
    
    static func takeEvery<Output>(_ mapping: @escaping (Action) -> Output, saga: @escaping Saga<Output>) -> Effects.TakeEvery<Output> {
        Effects.TakeEvery(mapping, saga: saga)
    }
}

public extension Yielder {
    @discardableResult
    func takeEvery<Output: Action>(_: Output.Type = Output.self, predicate: @escaping (Output) -> Bool = {_ in true}, saga: @escaping Saga<Output>) throws -> SagaHandle {
        try self(Effects.takeEvery(Output.self, predicate: predicate, saga: saga))
    }
    
    @discardableResult
    func takeEvery(predicate: @escaping (Action) -> Bool, saga: @escaping Saga<Action>) throws -> SagaHandle {
        try self(Effects.takeEvery(predicate: predicate, saga: saga))
    }
    
    @discardableResult
    func takeEvery<Output>(_ mapping: @escaping (Action) -> Output, saga: @escaping Saga<Output>) throws -> SagaHandle {
        try self(Effects.takeEvery(mapping, saga: saga))
    }
}

public extension Effects {
    struct TakeLatest<Output>: Effect {
        let saga: Saga<Output>
        let mapping: (Action) -> Output?
        
        public init(predicate: @escaping (Action) -> Bool = {_ in true}, saga: @escaping Saga<Output>) where Output == Action {
            self.mapping = { action in
                predicate(action) ? action : nil
            }
            self.saga = saga
        }
        
        public init(_: Output.Type = Output.self, predicate: @escaping (Output) -> Bool = {_ in true}, saga: @escaping Saga<Output>) where Output: Action {
            self.mapping = { action in
                (action as? Output).flatMap { action in
                    predicate(action) ? action : nil
                }
            }
            self.saga = saga
        }
        
        public init(_ mapping: @escaping (Action) -> Output?, saga: @escaping Saga<Output>) {
            self.mapping = mapping
            self.saga = saga
        }
        
        
        public func perform(in environment: EffectEnvironment) throws -> SagaHandle {
            let forkEffect = Effects.Fork { yield in
                var currentHandle: SagaHandle? = nil
                while true {
                    let action = try yield(Take(mapping))
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
    
    static func takeLatest<Output: Action>(_: Output.Type = Output.self, predicate: @escaping (Output) -> Bool = {_ in true}, saga: @escaping Saga<Output>) -> Effects.TakeLatest<Output> {
        Effects.TakeLatest(Output.self, predicate: predicate, saga: saga)
    }
    
    static func takeLatest(predicate: @escaping (Action) -> Bool, saga: @escaping Saga<Action>) -> Effects.TakeLatest<Action> {
        Effects.TakeLatest(predicate: predicate, saga: saga)
    }
    
    static func takeLatest<Output>(_ mapping: @escaping (Action) -> Output, saga: @escaping Saga<Output>) -> Effects.TakeLatest<Output> {
        Effects.TakeLatest(mapping, saga: saga)
    }
}

public extension Yielder {
    @discardableResult
    func takeLatest<Output: Action>(_: Output.Type = Output.self, predicate: @escaping (Output) -> Bool = {_ in true}, saga: @escaping Saga<Output>) throws -> SagaHandle {
        try self(Effects.takeLatest(Output.self, predicate: predicate, saga: saga))
    }
    
    @discardableResult
    func takeLatest(predicate: @escaping (Action) -> Bool, saga: @escaping Saga<Action>) throws -> SagaHandle {
        try self(Effects.takeLatest(predicate: predicate, saga: saga))
    }
    
    @discardableResult
    func takeLatest<Output>(_ mapping: @escaping (Action) -> Output, saga: @escaping Saga<Output>) throws -> SagaHandle {
        try self(Effects.takeLatest(mapping, saga: saga))
    }
}

public extension Effects {
    struct Debounce<Output>: Effect {
        let saga: Saga<Output>
        let interval: TimeInterval
        let mapping: (Action) -> Output?
        
        public init(interval: TimeInterval, predicate: @escaping (Action) -> Bool = {_ in true}, saga: @escaping Saga<Output>) where Output == Action {
            self.interval = interval
            self.mapping = { action in
                predicate(action) ? action : nil
            }
            self.saga = saga
        }
        
        public init(interval: TimeInterval, _: Output.Type = Output.self, predicate: @escaping (Output) -> Bool = {_ in true}, saga: @escaping Saga<Output>) where Output: Action {
            self.interval = interval
            self.mapping = { action in
                (action as? Output).flatMap { action in
                    predicate(action) ? action : nil
                }
            }
            self.saga = saga
        }
        
        public init(interval: TimeInterval, _ mapping: @escaping (Action) -> Output?, saga: @escaping Saga<Output>) {
            self.interval = interval
            self.mapping = mapping
            self.saga = saga
        }
        
        
        public func perform(in environment: EffectEnvironment) throws -> SagaHandle {
            let forkEffect = Effects.Fork { yield in
                var token: Int = 0
                while true {
                    let action = try yield(Take(mapping))
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
    
    static func debounce<Output: Action>(interval: TimeInterval, _: Output.Type = Output.self, predicate: @escaping (Output) -> Bool = {_ in true}, saga: @escaping Saga<Output>) -> Effects.Debounce<Output> {
        Effects.Debounce(interval: interval, Output.self, predicate: predicate, saga: saga)
    }
    
    static func debounce(interval: TimeInterval, predicate: @escaping (Action) -> Bool, saga: @escaping Saga<Action>) -> Effects.Debounce<Action> {
        Effects.Debounce(interval: interval, predicate: predicate, saga: saga)
    }
    
    static func debounce<Output>(interval: TimeInterval, _ mapping: @escaping (Action) -> Output, saga: @escaping Saga<Output>) -> Effects.Debounce<Output> {
        Effects.Debounce(interval: interval, mapping, saga: saga)
    }
}

public extension Yielder {
    @discardableResult
    func debounce<Output: Action>(interval: TimeInterval, _: Output.Type = Output.self, predicate: @escaping (Output) -> Bool = {_ in true}, saga: @escaping Saga<Output>) throws -> SagaHandle {
        try self(Effects.debounce(interval: interval, Output.self, predicate: predicate, saga: saga))
    }
    
    @discardableResult
    func debounce(interval: TimeInterval, predicate: @escaping (Action) -> Bool, saga: @escaping Saga<Action>) throws -> SagaHandle {
        try self(Effects.debounce(interval: interval, predicate: predicate, saga: saga))
    }
    
    @discardableResult
    func debounce<Output>(interval: TimeInterval, _ mapping: @escaping (Action) -> Output, saga: @escaping Saga<Output>) throws -> SagaHandle {
        try self(Effects.debounce(interval: interval, mapping, saga: saga))
    }
}

public extension Effects {
    struct Throttle<Output>: Effect {
        let saga: Saga<Output>
        let interval: TimeInterval
        let mapping: (Action) -> Output?
        
        public init(interval: TimeInterval, predicate: @escaping (Action) -> Bool = {_ in true}, saga: @escaping Saga<Output>) where Output == Action {
            self.interval = interval
            self.mapping = { action in
                predicate(action) ? action : nil
            }
            self.saga = saga
        }
        
        public init(interval: TimeInterval, _: Output.Type = Output.self, predicate: @escaping (Output) -> Bool = {_ in true}, saga: @escaping Saga<Output>) where Output: Action {
            self.interval = interval
            self.mapping = { action in
                (action as? Output).flatMap { action in
                    predicate(action) ? action : nil
                }
            }
            self.saga = saga
        }
        
        public init(interval: TimeInterval, _ mapping: @escaping (Action) -> Output?, saga: @escaping Saga<Output>) {
            self.interval = interval
            self.mapping = mapping
            self.saga = saga
        }
        
        public func perform(in environment: EffectEnvironment) -> SagaHandle {
            let forkEffect = Effects.Fork { yield in
                var idle = true
                while true {
                    let action = try yield(Take(mapping))
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
    
    static func throttle<Output: Action>(interval: TimeInterval, _: Output.Type = Output.self, predicate: @escaping (Output) -> Bool = {_ in true}, saga: @escaping Saga<Output>) -> Effects.Throttle<Output> {
        Effects.Throttle(interval: interval, Output.self, predicate: predicate, saga: saga)
    }
    
    static func throttle(interval: TimeInterval, predicate: @escaping (Action) -> Bool, saga: @escaping Saga<Action>) -> Effects.Throttle<Action> {
        Effects.Throttle(interval: interval, predicate: predicate, saga: saga)
    }
    
    static func throttle<Output>(interval: TimeInterval, _ mapping: @escaping (Action) -> Output, saga: @escaping Saga<Output>) -> Effects.Throttle<Output> {
        Effects.Throttle(interval: interval, mapping, saga: saga)
    }
}

public extension Yielder {
    @discardableResult
    func throttle<Output: Action>(interval: TimeInterval, _: Output.Type = Output.self, predicate: @escaping (Output) -> Bool = {_ in true}, saga: @escaping Saga<Output>) throws -> SagaHandle {
        try self(Effects.throttle(interval: interval, Output.self, predicate: predicate, saga: saga))
    }
    
    @discardableResult
    func throttle(interval: TimeInterval, predicate: @escaping (Action) -> Bool, saga: @escaping Saga<Action>) throws -> SagaHandle {
        try self(Effects.throttle(interval: interval, predicate: predicate, saga: saga))
    }
    
    @discardableResult
    func throttle<Output>(interval: TimeInterval, _ mapping: @escaping (Action) -> Output, saga: @escaping Saga<Output>) throws -> SagaHandle {
        try self(Effects.throttle(interval: interval, mapping, saga: saga))
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
    
    static func all<BaseEffect: Effect>(_ effects: [BaseEffect]) -> Effects.All<BaseEffect> {
        Effects.All(effects)
    }
    
    static func all<BaseEffect: Effect>(_ effects: BaseEffect...) -> Effects.All<BaseEffect> {
        self.all(effects)
    }
    
    static func all(_ effects: [AnyEffectConvertible]) -> Effects.All<AnyEffect> {
        Effects.All(effects.map {$0.wrapped()})
    }
    
    static func all(_ effects: AnyEffectConvertible...) -> Effects.All<AnyEffect> {
        self.all(effects)
    }
}

public extension Yielder {
    func all<BaseEffect: Effect>(_ effects: [BaseEffect]) throws -> [BaseEffect.Response] {
        try self(Effects.all(effects))
    }
    
    func all<BaseEffect: Effect>(_ effects: BaseEffect...) throws -> [BaseEffect.Response] {
        try self.all(effects)
    }
    
    @discardableResult
    func all(_ effects: [AnyEffectConvertible]) throws -> [Any] {
        try self.all(effects.map {$0.wrapped()} as [AnyEffect])
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
    
    static func first<BaseEffect: Effect>(_ effects: [BaseEffect]) -> Effects.First<BaseEffect> {
        Effects.First(effects)
    }
    
    static func first<BaseEffect: Effect>(_ effects: BaseEffect...) -> Effects.First<BaseEffect> {
        self.first(effects)
    }
    
    static func first(_ effects: [AnyEffectConvertible]) -> Effects.First<AnyEffect> {
        Effects.First(effects.map {$0.wrapped()})
    }
    
    static func first(_ effects: AnyEffectConvertible...) -> Effects.First<AnyEffect> {
        self.first(effects)
    }
}

public extension Yielder {
    func first<BaseEffect: Effect>(_ effects: [BaseEffect]) throws -> BaseEffect.Response {
        try self(Effects.first(effects))
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

public extension Effects {
    struct Run: Effect {
        public typealias Response = Void
        
        let saga: VoidSaga
        
        public init(_ saga: @escaping VoidSaga) {
            self.saga = saga
        }
        
        public func perform(in environment: EffectEnvironment) throws -> Void {
            try Coroutine.await { completion in
                startSaga(self.saga, in: environment, completion: completion)
            }
        }
    }
    
    static func run(_ saga: @escaping VoidSaga) -> Effects.Run {
        Effects.Run(saga)
    }
}

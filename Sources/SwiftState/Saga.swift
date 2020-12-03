//
//  Saga.swift
//  
//
//  Created by Palle Klewitz on 01.12.20.
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

public struct SagaHandle {
    let cancel: () -> Void
}

public struct EffectEnvironment {
    var queue: DispatchQueue
    let state: () -> Any
    let actions: () -> CoChannel<Action>
    let dispatch: (Action) -> Void
}

public protocol AnyEffectConvertible {
    func wrapped() -> AnyEffect
}

public protocol Effect: AnyEffectConvertible {
    associatedtype Response
    
    func perform(in environment: EffectEnvironment) throws -> Response
}

public extension Effect {
    func wrapped() -> AnyEffect {
        AnyEffect(wrapping: self)
    }
    
    func generic() -> GenericEffect<Response> {
        GenericEffect(wrapping: self)
    }
}

public struct AnyEffect: Effect {
    public typealias Response = Any
    
    let performClosure: (EffectEnvironment) throws -> Any
    
    public init<WrappedEffect: Effect>(wrapping wrappedEffect: WrappedEffect) {
        self.performClosure = { environment in
            try wrappedEffect.perform(in: environment)
        }
    }
    
    public func perform(in environment: EffectEnvironment) throws -> Any {
        try performClosure(environment)
    }
}

public struct GenericEffect<Response>: Effect {
    let performClosure: (EffectEnvironment) throws -> Response
    
    public init<WrappedEffect: Effect>(wrapping wrappedEffect: WrappedEffect) where WrappedEffect.Response == Response {
        self.performClosure = { environment in
            try wrappedEffect.perform(in: environment)
        }
    }
    
    public func perform(in environment: EffectEnvironment) throws -> Response {
        try performClosure(environment)
    }
}

public struct Yielder {
    let yield: (AnyEffect) throws -> Any
    
    init(_ yield: @escaping (AnyEffect) throws -> Any) {
        self.yield = yield
    }
    
    @discardableResult
    public func callAsFunction<EffectType: Effect>(_ effect: EffectType) throws -> EffectType.Response {
        try self.yield(AnyEffect(wrapping: effect)) as! EffectType.Response
    }
}

public typealias VoidSaga = (_ yield: Yielder) throws -> Void
public typealias Saga<Args> = (_ args: Args, _ yield: Yielder) throws -> Void

@discardableResult
func startSaga(_ saga: @escaping VoidSaga, in environment: EffectEnvironment, completion: (() -> Void)? = nil) -> SagaHandle {
    var cancelClosure = {}
    let scope = CoScope()
    environment.queue.startCoroutine(in: scope) {
        let generator = Generator<AnyEffect, Any> { yield in
            let yielder = Yielder(yield)
            try saga(yielder)
        }
        generator.run(on: environment.queue)
        
        cancelClosure = {
            generator.cancel()
        }
        
        while let _ = generator.next({ effect -> Any in
            try effect.perform(in: environment)
        }) {}
        
        completion?()
    }
    
    return SagaHandle {
        scope.cancel()
        cancelClosure()
    }
}

public extension Store {
    func runSaga(_ saga: @escaping VoidSaga, on queue: DispatchQueue = .main) {
        let environment = EffectEnvironment(
            queue: queue,
            state: {self.state},
            actions: {
                let channel = CoChannel<Action>(bufferType: .conflated)
                self.addMiddleware { _, action, _ in
                    try? channel.awaitSend(action)
                }
                return channel
            },
            dispatch: self.dispatch(_:)
        )
        startSaga(saga, in: environment)
    }
}

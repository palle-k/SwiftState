//
//  Effects.swift
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


public class Generator<Element, Input> {
    public enum Event {
        case next(Element)
        case complete(Optional<Error>)
    }
    
    enum State {
        case idle
        case running
        case completed
    }
    
    private var state = State.idle
    private let execute: (_ yield: @escaping (Element) -> Input) throws -> Void
    private let scope: CoScope
    
    let outputChannel: CoChannel<Event>
    let inputChannel: CoChannel<Input>
    
    deinit {
        if !scope.isCanceled {
            scope.cancel()
        }
    }
    
    public init(_ execute: @escaping (_ yield: @escaping (Element) -> Input) throws -> Void) {
        self.inputChannel = CoChannel(bufferType: .unlimited)
        self.outputChannel = CoChannel(bufferType: .none)
        self.execute = execute
        self.scope = CoScope()
    }
    
    private func yield(_ element: Element) -> Input {
        try! outputChannel.awaitSend(.next(element))
        return try! inputChannel.awaitReceive()
    }
    
    public func run(on queue: CoroutineScheduler) {
        assert(state == .idle, "generator has already been started")
        state = .running
        queue.startCoroutine(in: self.scope) {
            do {
                try self.execute(self.yield)
            } catch let error {
                return try self.outputChannel.awaitSend(.complete(error))
            }
            try self.outputChannel.awaitSend(.complete(nil))
        }
    }
    
    public func cancel() {
        self.scope.cancel()
    }
    
    public func next(_ input: Input) throws -> Element? {
        try next {_ in input}
    }
    
    @discardableResult
    public func next(_ mapping: (Element) -> Input) throws -> Element? {
        assert(state != .idle)
        if state == .completed {
            return nil
        }
        let result = try! outputChannel.awaitReceive()
        switch result {
        case .next(let element):
            try! inputChannel.awaitSend(mapping(element))
            return element
        case .complete(.some(let error)):
            self.state = .completed
            inputChannel.close()
            outputChannel.close()
            throw error
        case .complete(.none):
            inputChannel.close()
            outputChannel.close()
            self.state = .completed
            return nil
        }
    }
}

extension Generator: IteratorProtocol, Sequence where Input == Void {
    public func next() -> Element? {
        try! next(())
    }
    
    public func makeIterator() -> Self {
        self
    }
}

public extension Generator where Element == Void {
    convenience init(_ execute: @escaping (_ yield: () -> Input) throws -> Void) {
        self.init({ yield in
            try execute {
                yield(())
            }
        })
    }
}

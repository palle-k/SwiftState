//
//  EventChannel.swift
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


public class EventChannel<Event> {
    let queue: CoChannel<Event>
    var cancel: () -> Void
    
    public init(subscribe: @escaping (_ put: @escaping (Event) -> Void) -> () -> Void) {
        let queue = CoChannel<Event>(bufferType: .conflated)
        self.queue = queue
        self.cancel = subscribe { event in
            Coroutine.start {
                try queue.awaitSend(event)
            }
        }
    }
    
    deinit {
        close()
    }
    
    public func close() {
        self.cancel()
        self.queue.close()
    }
    
    public func next() -> Event {
        do {
            return try self.queue.awaitReceive()
        } catch CoroutineError.canceled, CoChannelError.canceled, CoChannelError.closed {
            fatalError()
        } catch let error {
            fatalError(error.localizedDescription)
        }
    }
}

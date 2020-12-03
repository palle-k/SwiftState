//
//  GeneratorTests.swift
//  
//
//  Created by Palle Klewitz on 01.12.20.
//

import Foundation
import XCTest
import SwiftState

class GeneratorTests: XCTestCase {
    func testGenerator() {
        let generator = Generator<Void, Void> { (yield: @escaping (()) throws -> ()) in
            while true {
                print("yielding... (main thread? \(Thread.current.isMainThread))")
                try yield(())
            }
        }
        
        generator.run(on: DispatchQueue.main)
        
        for _ in 0 ..< 10 {
            print("sending... (main thread? \(Thread.current.isMainThread))")
            generator.next()
        }
        
        generator.cancel()
        print("done outside coroutine")
    }
}

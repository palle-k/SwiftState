//
//  GeneratorTests.swift
//  
//
//  Created by Palle Klewitz on 01.12.20.
//

import Foundation
import XCTest
@testable import SwiftState


class GeneratorTests: XCTestCase {
    func testGenerator() {
        let resendPlusOne = Generator<Int, Int> { yield in
            for i in 0... {
                print(yield(i))
            }
        }
        
        resendPlusOne.run(on: DispatchQueue.main)
        
        for _ in 0 ..< 10 {
            try! resendPlusOne.next {$0 + 1}
        }
    }
}

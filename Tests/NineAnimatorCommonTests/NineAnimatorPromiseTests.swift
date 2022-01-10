//
//  This file is part of the NineAnimator project.
//
//  Copyright © 2018-2021 Marcus Zhou. All rights reserved.
//
//  NineAnimator is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  NineAnimator is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with NineAnimator.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
@testable import NineAnimatorCommon
import XCTest

final class NineAnimatorPromiseTests: XCTestCase {
    func testBasicConcurrencyCompatibility() async {
        let correctResult = Int.random(in: 10...1000)
        let promise = NineAnimatorPromise<Int> {
            cb in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                cb(correctResult, nil)
            }
            return nil
        }
        
        do {
            let result = try await promise.awaitableResult()
            XCTAssert(result == correctResult, "Promise does not return expected result with swift concurrency (expected \(correctResult) got \(result).")
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func testConcurrencyExceptions() async {
        let promise = NineAnimatorPromise<Void> {
            cb in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                cb(nil, NineAnimatorError.unknownError)
            }
            return nil
        }
        
        do {
            _ = try await promise.awaitableResult()
            XCTFail("No error was thrown. Expecting NineAnimatorError.UnknownError.")
        } catch {
            XCTAssert(error is NineAnimatorError.UnknownError, "Caught error of wrong type.")
        }
    }
}

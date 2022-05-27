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
    
    class NACancellableIndicator: NineAnimatorAsyncTask {
        var isCancelled = false
        var didMarkAsComplete = false
        let expectation: XCTestExpectation
        
        func cancel() {
            isCancelled = true
        }
        
        func markAsComplete() {
            didMarkAsComplete = true
            if isCancelled {
                expectation.fulfill()
            }
        }
        
        init(_ exp: XCTestExpectation) {
            self.expectation = exp
        }
    }
    
    /// Ensures that cancellation of a converted swift concurrency task also affects the original NineAnimatorPromise
    func testConvertedConcurrencyTaskCancellation() async {
        let expectation = XCTestExpectation(description: "Swift concurrency cancellation not transferrable to NineAnimatorPromise")
        let cancellable = NACancellableIndicator(expectation)
        
        var didInitiateTask = false
        
        // Dispatch everything on the main queue
        let promise = NineAnimatorPromise<Void>(queue: DispatchQueue.main) {
            cb in
            // Wait for the cancellation to be initiated, then completes the promise with an error
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
                timer in
                // Mark the task as initiated
                didInitiateTask = true
                
                if cancellable.isCancelled {
                    timer.invalidate()
                    cancellable.markAsComplete()
                    cb(nil, NineAnimatorError.unknownError("The promise's error message should not be accepted after being cancelled."))
                }
            }
            return cancellable
        } .then {
            // Should never execute to this point since the task was cancelled immediately after initiation
            XCTFail("Promise continuation executed after being cancelled.")
        }
        
        let detachedTask = Task(priority: .userInitiated) {
            try await promise.awaitableResult()
        }
        
        // Wait for the task to be initiated, then cancel the task with swift concurrency
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            timer in
            if didInitiateTask {
                detachedTask.cancel()
                timer.invalidate()
            }
        }
        
        wait(for: [ expectation ], timeout: 5.0)
    }
    
    func testConvertedPromiseCancellation() async {
        let initiationExp = XCTestExpectation(description: "Swift concurrency task failed to initiate from NineAnimatorPromise")
        let cancellationExp = XCTestExpectation(description: "NineAnimatorPromise cancellation not transferrable to Swift concurrency")
        let promiseConclusionExp = XCTestExpectation(description: "NineAnimatorPromise defer statement not executed")
        
        let promise = NineAnimatorPromise.async(priority: .userInitiated) {
            initiationExp.fulfill()
            await withTaskCancellationHandler {
                while true {
                    await Task.yield()
                }
            } onCancel: { cancellationExp.fulfill() }
        }
        
        // Initiates the NineAnimatorPromise tasks
        let promiseAsyncTask = promise.error {
            XCTFail("Promise failed with error: \($0.localizedDescription)")
        } .defer {
            _ in promiseConclusionExp.fulfill()
        } .finally {
            XCTFail("Promise concluded without cancellation.")
        }
        
        // Wait for the task to be initiated
        wait(for: [ initiationExp ], timeout: 5.0)
        
        // Cancels the NineAnimator AsyncTask
        // Cancellation should propagate to the swift concurrency task
        promiseAsyncTask.cancel()
        
        // Wait for cancellation to become effective and the defer statement to be invoked
        wait(for: [ cancellationExp, promiseConclusionExp ], timeout: 5.0)
    }
}

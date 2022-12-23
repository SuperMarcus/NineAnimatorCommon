//
//  This file is part of the NineAnimator project.
//
//  Copyright © 2018-2022 Marcus Zhou. All rights reserved.
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

public extension NineAnimatorPromise {
    /// Returns a special promise producer that relays the return value of the promise, while only execute the promise once.
    static func once(queue: DispatchQueue = .global(), _ promiseProducer: @escaping () throws -> NineAnimatorPromise?) -> RunOnce {
        .init(promiseProducer, queue: queue)
    }
    
    static func once(queue: DispatchQueue = .global(), _ promise: @autoclosure @escaping () throws -> NineAnimatorPromise?) -> RunOnce {
        .init(promise, queue: queue)
    }
    
    /// Returns a promise-producing structure that runs the current promise at most once, and relays the values to later promises
    var once: RunOnce {
        NineAnimatorPromise.once(queue: self.queue, self)
    }
}

public extension NineAnimatorPromise {
    /// A structure that accepts a single promise and multiplexes it's results to consecutive sink promises.
    /// The original promise is run once and the result is preserved and passed to promises generated via `.sink`.
    ///
    /// This object preserves a strong reference to the result value, as long as its alive.
    class RunOnce {
        private var promiseProducer: (() throws -> NineAnimatorPromise?)?
        
        private var resolvingAsyncTask: NineAnimatorAsyncTask?
        
        private var result: Result<ResultType, Error>?
        
        private var pendingPromises: NSHashTable<NineAnimatorPromise>
        
        private var lock: NSLock
        
        private var queue: DispatchQueue
        
        init(_ promiseProducer: (() throws -> NineAnimatorPromise?)?, queue: DispatchQueue) {
            self.promiseProducer = promiseProducer
            self.pendingPromises = .weakObjects()
            self.lock = NSLock()
            self.queue = queue
        }
        
        internal convenience init(result: Result<ResultType, Error>, queue: DispatchQueue) {
            self.init(nil, queue: queue)
            self.result = result
        }
        
        /// Checks if the original promise has been resolved
        public var isResolved: Bool {
            // Read-only Ops so no need to lock
            self.result != nil
        }
        
        /// Produce a new promise that relays the return value from the original promise
        public var sink: NineAnimatorPromise {
            self.lock.lock()
            defer {
                self.lock.unlock()
            }
            
            if let resolvedResult = self.result {
                // Result must be available at the time of execution
                return .firstly(queue: self.queue) {
                    try resolvedResult.get()
                }
            } else {
                // Result is pending, so add the promise while still in the critical section
                let pendingPromise = NineAnimatorPromise(queue: self.queue) {
                    [weak self] _ in
                    // Start the original promise if haven't already
                    self?.runOriginalPromise()
                    return nil
                }
                self.pendingPromises.add(pendingPromise)
                return pendingPromise
            }
        }
        
        public func retrieve() throws -> Result<ResultType, Error> {
            self.lock.lock()
            defer { self.lock.unlock() }
            
            if let result = self.result {
                return result
            } else {
                throw NineAnimatorError.unknownError("Result is not yet available")
            }
        }
        
        private func runOriginalPromise() {
            self.lock.lock()
            
            defer {
                // Indicates that the current promise is resolving by resetting the promise producer
                self.promiseProducer = nil
                self.lock.unlock()
            }
            
            do {
                // Promise producer indicates if this promise is resolving or not
                if case .none = self.result, let promiseProducer = self.promiseProducer {
                    // Try to produce promise
                    guard let producedPromise = try promiseProducer() else {
                        throw NineAnimatorError.unknownError
                    }
                    
                    // Save reference to the resolving task
                    self.resolvingAsyncTask = producedPromise.error {
                        [weak self] producedError in
                        self?.resolve(newResult: .failure(producedError))
                    } .finally {
                        [weak self] producedResult in
                        self?.resolve(newResult: .success(producedResult))
                    }
                }
            } catch {
                let result: Result<ResultType, Error> = .failure(error)
                self.result = result
                self.resolveInCriticalSection(newResult: result)
            }
        }
        
        private func resolve(newResult: Result<ResultType, Error>) {
            self.lock.lock()
            self.resolveInCriticalSection(newResult: newResult)
            self.lock.unlock()
        }
        
        private func resolveInCriticalSection(newResult: Result<ResultType, Error>) {
            // Update result
            self.result = newResult
            
            // Resolve all pending promises
            for pendingPromise in self.pendingPromises.allObjects {
                // Relies on the asynchronous nature of the reject and resolve methods
                switch newResult {
                case .failure(let error):
                    pendingPromise.reject(error)
                case .success(let resultValue):
                    pendingPromise.resolve(resultValue)
                }
            }
            
            // Remove all pending objects
            self.pendingPromises.removeAllObjects()
        }
    }
}

public extension NineAnimatorPromise.RunOnce {
    /// Creates a constant ``NineAnimatorPromise.RunOnce`` object. This avoids creating any promise objects and should be more efficient.
    static func withResult(_ result: Result<ResultType, Error>, queue: DispatchQueue = .global()) -> NineAnimatorPromise<ResultType>.RunOnce {
        .init(result: result, queue: queue)
    }
}

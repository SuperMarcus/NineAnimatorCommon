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

import Combine
import Foundation

public extension NineAnimatorPromise {
    /// Converts this promise to an awaitable swift concurrency task.
    func awaitableResult() async throws -> ResultType {
        let references = AsyncTaskContainer()
        
        return try await withTaskCancellationHandler {
            let result: ResultType = try await withCheckedThrowingContinuation {
                [weak self] continuation in
                // For the duration of this function, referencedTask should maintain reference to this promise
                let newTask = self?.error {
                    continuation.resume(throwing: $0)
                } .finally {
                    continuation.resume(returning: $0)
                }
                references.add(newTask)
            }
            
            // Really just to silence the unread variable warning...
            if references.isEmpty {
                Log.debug("[NineAnimatorPromise] Awaitable task completed without a valid task? How can this be?")
            }
            
            return result
        } onCancel: {
            [weak references] in
            references?.cancel()
        }
    }
    
    /// Creates a new NineAnimatorPromise from a swift concurrency task closure.
    static func `async`(priority: TaskPriority? = nil, _ concurrentClosure: @escaping () async throws -> ResultType?) -> NineAnimatorPromise<ResultType> {
        NineAnimatorPromise {
            cb in
            let detachedTask = Task(priority: priority) {
                do {
                    let result = try await concurrentClosure()
                    cb(result, nil)
                } catch {
                    cb(nil, error)
                }
            }
            return AnyCancellable(detachedTask)
        }
    }
}

extension AnyCancellable: NineAnimatorAsyncTask { }

extension Task: Cancellable { }

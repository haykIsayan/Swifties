//
//  Continuation.swift
//  project-swifties
//
//  Created by Hayk Isayan on 4/10/26.
//

import Dispatch

protocol Continuation<DataType> {
    associatedtype DataType
    var context: SwiftieContext
        { get }
    
    func resumeWith(result: ContinuationResult<DataType>)
}

extension Continuation {
    func resume(returning value: DataType) {
        resumeWith(result: .success(value))
    }
    func resume(throwing error: Error) {
        resumeWith(result: .failure(error))
    }
}

enum ContinuationResult<DataType> {
    case success(DataType)
    case failure(Error)
}

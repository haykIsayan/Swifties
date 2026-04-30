//
//  Deferred.swift
//  project-swifties
//
//  Created by Hayk Isayan on 4/30/26.
//

actor Deferred<DataType> {
    private var result: ContinuationResult<DataType>? = nil
    private var continuations: [(ContinuationResult<DataType>) -> Void] = []
    private let job: Job
    
    var isCompleted: Bool {
        get async {
            await job.isCompleted
        }
    }
    
    var isFailed: Bool {
        get async {
            await job.isFailed
        }
    }
    
    var isCanceled: Bool {
        get async {
            await job.isCanceled
        }
    }
    
    init(job: Job) {
        self.job = job
    }
    
    func complete(with result: ContinuationResult<DataType>) {
        guard self.result == nil else { return }
        self.result = result
        self.continuations.forEach { $0(result) }
        self.continuations.removeAll()
    }
    
    func value() async throws -> DataType {
        if let result { return try unwrap(result: result) }
        let awaitResult = await withCheckedContinuation { continuation in
            continuations.append { result in
                continuation.resume(returning: result)
            }
        }
        
        return try unwrap(result: awaitResult)
    }
    
    private func unwrap(result: ContinuationResult<DataType>) throws -> DataType {
        switch result {
        case .success(let data):
            return data
        case .failure(let error):
            throw error
        }
    }
    
}

enum SwiftieError: Error {
    case cancellation
    case failure
}

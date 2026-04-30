//
//  SwiftieScope.swift
//  project-swifties
//
//  Created by Hayk Isayan on 4/30/26.
//

typealias LaunchBlock = (SwiftieScope) async throws -> Void

actor SwiftieScope {
    
    let context: SwiftieContext
    
    var rootJob: Job {
        guard let job = context[Job.self] else {
            fatalError("SwiftieScope always requires a Job in context")
        }
        return job
    }
    
    var swiftieDispatcher: SwiftieDispatcher {
        guard let dispatcher = context[SwiftieDispatcher.self] else {
            fatalError("SwiftieScope always requires a Dispatcher in context")
        }
        return dispatcher
    }
    
    init(context: SwiftieContext) {
        let job = Job(parent: nil)
        var base = context + job
        if context[SwiftieDispatcher.self] == nil {
            base = base + SwiftieDispatcherDefault()
        }
        self.context = base
    }
    
    fileprivate init(context: SwiftieContext, job: Job) {
        var base = context + job
        if context[SwiftieDispatcher.self] == nil {
            base = base + SwiftieDispatcherDefault()
        }
        self.context = base
    }
    
    @discardableResult
    func launch(block: @escaping LaunchBlock) async throws -> Job {
        let newJob = try await createAndStartJob()
        let childScope = createChildScope(with: newJob)
        await newJob.execute(
            block: {
                do {
                    try await block(childScope)
                    await newJob.complete()
                } catch {
                    await newJob.fail(error: error)
                }
            },
            dispatcher: swiftieDispatcher
        )
        return newJob
    }
    
    func asynchron<T>(block: @escaping (SwiftieScope) async throws -> T) async throws -> Deferred<T> {
        let newJob = try await createAndStartJob()
        let childScope = createChildScope(with: newJob)
    
        let deferred = Deferred<T>(job: newJob)
        
        await newJob.execute(
            block: {
                do {
                    let result = try await block(childScope)
                    await deferred.complete(with: .success(result))
                    await newJob.complete()
                } catch {
                    await deferred.complete(with: .failure(error))
                    await newJob.fail(error: error)
                }
            },
            dispatcher: swiftieDispatcher
        )
        
        return deferred
    }
    
    func withContext<T>(
        context newContext: SwiftieContext,
        block: @escaping (SwiftieScope) async throws -> T
    ) async throws -> T {
        let initialContext = self.context
        let mergedContext = initialContext + newContext
        let childScope = SwiftieScope(context: mergedContext, job: rootJob)
        let deferred = try await childScope.asynchron(block: block)
        let result = try await deferred.value()
        return result
    }
    
    func supervisorScope<T>(
        block: @escaping (SwiftieScope) async throws -> T
    ) async throws -> T {
        let supervisorJob = Job(parent: rootJob, type: .supervisor)
        await rootJob.addChild(supervisorJob)
        await supervisorJob.start()
        let childScope = SwiftieScope(context: context, job: supervisorJob)
            
        do {
            let result = try await block(childScope)
            await supervisorJob.complete()
            return result
        } catch {
            await supervisorJob.fail(error: error)
            throw error
        }
    }
    
    private func createAndStartJob() async throws -> Job {
        let newJob = Job(parent: rootJob)
        guard await rootJob.addChild(newJob) else {
            throw SwiftieError.cancellation
        }
        await newJob.start()
        return newJob
    }
    
    private func createChildScope(with childJob: Job) -> SwiftieScope {
        let childContext = self.context
        let childScope = SwiftieScope(context: childContext, job: childJob)
        return childScope
    }
    
    func cancel() async {
        await rootJob.cancel()
    }
}

func supervisorScope(context: SwiftieContext) -> SwiftieScope {
    return SwiftieScope(
        context: context,
        job: Job(parent: nil, type: .supervisor)
    )
}

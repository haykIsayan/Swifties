//
//  Continuation.swift
//  project-swifties
//
//  Created by Hayk Isayan on 4/10/26.
//

import Dispatch

/**
 CONTEXT
 */

struct SwiftieContext {
    private let storage: [ObjectIdentifier: ContextElement]

    init(storage: [ObjectIdentifier: ContextElement] = [:]) {
        self.storage = storage
    }

    init<T: ContextElement>(_ element: T) {
        self.storage = [ObjectIdentifier(T.contextKey): element]
    }

    subscript<T>(_ type: T.Type) -> T? {
        storage[ObjectIdentifier(type)] as? T
    }

    static func + (lhs: SwiftieContext, rhs: SwiftieContext) -> SwiftieContext {
        SwiftieContext(storage: lhs.storage.merging(rhs.storage) { _, rhs in rhs })
    }
    
    static func + (lhs: SwiftieContext, rhs: ContextElement) -> SwiftieContext {
        lhs + SwiftieContext(rhs)
    }
}

protocol ContextElement {
    static var contextKey: Any.Type { get }
}

extension ContextElement {
    static var contextKey: Any.Type { Self.self }
}

func + (lhs: some ContextElement, rhs: some ContextElement) -> SwiftieContext {
    SwiftieContext(lhs) + SwiftieContext(rhs)
}

func + (lhs: some ContextElement, rhs: SwiftieContext) -> SwiftieContext {
    SwiftieContext(lhs) + rhs
}

/**
 SWIFTIE NAME
 */

struct SwiftieName: ContextElement {
    let name: String
}

/**
 DISPATCHER
 */

typealias DispatchBlock = () -> Void

protocol Dispatcher: ContextElement {
    func dispatch(block: @escaping DispatchBlock)
}

extension Dispatcher {
    static var contextKey: Any.Type { Dispatcher.self }  // all dispatchers share one slot
}

struct DispatcherMain: Dispatcher {
    func dispatch(block: @escaping DispatchBlock) {
        DispatchQueue.main.async(execute: block)
    }
}

struct DispatcherIO: Dispatcher {
    func dispatch(block: @escaping DispatchBlock) {
        DispatchQueue.global(qos: .utility).async(execute: block)
    }
}

struct DispatcherGeneral: Dispatcher {
    func dispatch(block: @escaping DispatchBlock) {
        DispatchQueue.global(qos: .userInitiated).async(execute: block)
    }
}

struct UnconfinedDispatcher: Dispatcher {
    func dispatch(block: @escaping DispatchBlock) {
        block()
    }
}

enum Dispatchers {
    static let main = SwiftieContext(DispatcherMain())
    static let io = SwiftieContext(DispatcherIO())
    static let general = SwiftieContext(DispatcherGeneral())
    static let unconfined = SwiftieContext(UnconfinedDispatcher())
}

/**
 CONTINUATION
 */

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

/**
 JOB STATE MACHINE
 */


// TODO: Add .failed state to JobState and JobStateMachine
// failed = ran to completion but produced an error
// distinct from .canceled (externally stopped) and .completed (success)
// .active: [.complete: .completing, .fail: .failing, .cancel: .canceling]
// .failing: [.childrenCompleted: .failed]


typealias JobStateMachine = [JobState: [JobEvent: JobState]]

let jobStateMachine: JobStateMachine = [
    .new: [
        .start: .active,
        .cancel: .canceling
    ],
    .active: [
        .complete: .completing,
        .cancel: .canceling
    ],
    .completing: [
        .childrenCompleted: .completed,
        .cancel: .canceling
    ],
    .canceling: [
        .childrenCompleted: .canceled
    ],
]

func interpret(trigger event: JobEvent, from currentState: JobState) -> JobState? {
    return jobStateMachine[currentState]?[event]
}

/**
 JOB
 */

actor Job: ContextElement {
    let parent: Job?
    private var children: [Job] = []
    private var state: JobState = .new

    private var joinContinuations: [CheckedContinuation<Void, Never>] = []
    
    var isCompleted: Bool { state == .completed }
    
    var isCanceled: Bool { state == .canceled }
    
    var childCount: Int { children.count }
    
    init(parent: Job?) {
        self.parent = parent
    }
    
    @discardableResult
    func start() async -> Bool {
        guard let activeState = interpret(trigger: .start, from: state) else {
            return false
        }
        state = activeState
        return true
    }
    
    
    @discardableResult
    func complete() async -> Bool {
        guard let completingState = interpret(trigger: .complete, from: state) else {
            return false
        }
        state = completingState
        for child in children {
            await child.complete()
        }
        guard let completedState = interpret(trigger: .childrenCompleted, from: state) else {
            return false
        }
        state = completedState
        
        resumeAndCleanContinuations()
        return true
    }
    
    @discardableResult
    func cancel() async -> Bool {
        guard let cancelingState = interpret(trigger: .cancel, from: state) else {
            return false
        }
        state = cancelingState
        for child in children {
            await child.cancel()
        }
        guard let canceledState = interpret(trigger: .childrenCompleted, from: state) else {
            return false
        }
        state = canceledState
        
        resumeAndCleanContinuations()
        return true
    }
    
    private func resumeAndCleanContinuations() {
        joinContinuations.forEach { $0.resume() }
        joinContinuations.removeAll()
    }
    
    @discardableResult
    func addChild(_ child: Job) -> Bool {
        guard state == .new || state == .active else { return false }
        children.append(child)
        return true
    }
    
    func join() async {
        if state == .completed || state == .canceled { return }
        await withCheckedContinuation { continuation in
            joinContinuations.append(continuation)
        }
    }
}

enum JobState {
    case new
    case active
    case completing
    case completed
    case canceling
    case canceled
}

enum JobEvent {
    case start
    case complete
    case cancel
    case childrenCompleted
}

/**
 SWIFTIE SCOPE
 */

typealias LaunchBlock = (SwiftieScope) async throws -> Void

actor SwiftieScope {
    
    let context: SwiftieContext
    
    var rootJob: Job {
        guard let job = context[Job.self] else {
            fatalError("SwiftieScope always requires a Job in context")
        }
        return job
    }
    
    var scopeDispatcher: Dispatcher {
        guard let dispatcher = context[Dispatcher.self] else {
            fatalError("SwiftieScope always requires a Dispatcher in context")
        }
        return dispatcher
    }
    
    init(context: SwiftieContext) {
        let job = Job(parent: nil)
        var base = context + job
        if context[Dispatcher.self] == nil {
            base = base + DispatcherGeneral()
        }
        self.context = base
    }
    
    private init(context: SwiftieContext, job: Job) {
        var base = context + job
        if context[Dispatcher.self] == nil {
            base = base + DispatcherGeneral()
        }
        self.context = base
    }
    
    @discardableResult
    func launch(block: @escaping LaunchBlock) async throws -> Job {
        let newJob = try await createAndStartJob()
        let childScope = createChildScope(with: newJob)
        
        scopeDispatcher.dispatch {
            Task {
                do {
                    try await block(childScope)
                    await newJob.complete()
                } catch {
                    await newJob.complete()  // complete even on failure
                    // TODO: propagate to parent when SupervisorJob is implemented
                }
            }
        }
        return newJob
    }
    
    func asynchron<T>(block: @escaping (SwiftieScope) async throws -> T) async throws -> Deferred<T> {
        let newJob = try await createAndStartJob()
        let childScope = createChildScope(with: newJob)
    
        let deferred = Deferred<T>(job: newJob)
        
        scopeDispatcher.dispatch {
            Task {
                do {
                    let result = try await block(childScope)
                    await newJob.complete()
                    await deferred.complete(with: .success(result))
                } catch {
                    await newJob.complete()
                    await deferred.complete(with: .failure(error))
                }
            }
        }
        
        return deferred
    }
    
    func withContext<T>(
        context newContext: SwiftieContext,
        block: @escaping (SwiftieScope) async throws -> T
    ) async throws -> T {
        let initialContext = self.context
        let mergedContext = initialContext + newContext
        let childScope = SwiftieScope(context: mergedContext)
        let deferred = try await childScope.asynchron(block: block)
        let result = try await deferred.value()
        return result
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

/**
 DEFERRED
 */

actor Deferred<DataType> {
    private var result: ContinuationResult<DataType>? = nil
    private var continuations: [(ContinuationResult<DataType>) -> Void] = []
    private let job: Job
    
    var isCompleted: Bool {
        get async {
            await job.isCompleted
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

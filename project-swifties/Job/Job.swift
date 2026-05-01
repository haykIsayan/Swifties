//
//  Job.swift
//  project-swifties
//
//  Created by Hayk Isayan on 4/30/26.
//

enum JobType {
    case regular
    case supervisor
}

actor Job: ContextElement {
    let type: JobType
    
    let parent: Job?
    private var children: [Job] = []
    
    private var state: JobState = .new

    private var joinContinuations: [CheckedContinuation<Void, Never>] = []
    
    private var task: Task<Void, Error>?
    
    private var error: Error? = nil
    
    var isCompleted: Bool { state == .completed }
    
    var isCanceled: Bool { state == .canceled }
    
    var isFailed: Bool { state == .failed }
    
    var childCount: Int { children.count }
    
    init(parent: Job?, type: JobType = .regular) {
        self.parent = parent
        self.type = type
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
    func execute(block: @escaping SwiftieDispatchBlock, dispatcher: some SwiftieDispatcher) async -> Bool {
        guard state == .active else { return false }
        self.task = dispatcher.dispatch {
            try await block()
        }
        return true
    }
    
    @discardableResult
    func complete() async -> Bool {
        guard let completingState = interpret(trigger: .complete, from: state) else {
            return false
        }
        state = completingState
        for child in children {
            await child.join()
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
        task?.cancel()
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
    
    @discardableResult
    func fail(error: Error) async -> Bool {
        guard let failingState = interpret(trigger: .fail, from: state) else {
            return false
        }
        state = failingState
        self.error = error
        for child in children {
            await child.cancel()
        }
        guard let failedState = interpret(trigger: .childrenCompleted, from: state) else {
            return false
        }
        state = failedState
        
        await parent?.notifyChildFailed(error: error)
        
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
    
    fileprivate func notifyChildFailed(error: Error) async {
        guard type != .supervisor else { return }
        await fail(error: error)
    }
    
    func join() async {
        if state == .completed || state == .canceled || state == .failed { return }
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
    case failing
    case failed
}

enum JobEvent {
    case start
    case complete
    case fail
    case cancel
    case childrenCompleted
}

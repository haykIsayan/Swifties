//
//  SwiftieDispatcher.swift
//  project-swifties
//
//  Created by Hayk Isayan on 4/30/26.
//


typealias SwiftieDispatchBlock = @Sendable () async throws -> Void

protocol SwiftieDispatcher: ContextElement {
    func dispatch(block: @escaping SwiftieDispatchBlock) -> SwiftieExecutable
}

extension SwiftieDispatcher {
    static var contextKey: Any.Type { SwiftieDispatcher.self }
}

struct SwiftieDispatcherIO: SwiftieDispatcher {
    func dispatch(block: @escaping SwiftieDispatchBlock) -> SwiftieExecutable {
        return SwiftieExecutor(
            taskBuilder: {
                Task(priority: .utility) {
                    try await block()
                }
            }
        )
    }
}

struct SwiftieDispatcherMain: SwiftieDispatcher {
    func dispatch(block: @escaping SwiftieDispatchBlock) -> SwiftieExecutable {
        return SwiftieExecutor(
            taskBuilder: {
                Task { @MainActor in
                    try await block()
                }
            }
        )
    }
}

struct SwiftieDispatcherDefault: SwiftieDispatcher {
    func dispatch(block: @escaping SwiftieDispatchBlock) -> SwiftieExecutable {
        return SwiftieExecutor(
            taskBuilder: {
                Task(priority: .userInitiated) {
                    try await block()
                }
            }
        )
    }
}


struct SwiftieDispatcherUnconfined: SwiftieDispatcher {
    func dispatch(block: @escaping SwiftieDispatchBlock) -> SwiftieExecutable {
        return SwiftieExecutor(
            taskBuilder: {
                Task {
                    try await block()
                }
            }
        )
    }
}

enum SwiftieDispatchers {
    static let main = SwiftieContext(SwiftieDispatcherMain())
    static let io = SwiftieContext(SwiftieDispatcherIO())
    static let general = SwiftieContext(SwiftieDispatcherDefault())
    static let unconfined = SwiftieContext(SwiftieDispatcherUnconfined())
}

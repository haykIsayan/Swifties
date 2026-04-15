//
//  SwiftiesTest.swift
//  SwiftiesTest
//
//  Created by Hayk Isayan on 4/13/26.
//

import Testing
@testable import project_swifties

struct SwiftieTests {
    
    @Test func launchExecutesBlock() async throws {
        let scope = SwiftieScope(context: SwiftieContext() + DispatcherDefault())
        var executed = false
        let job = try await scope.launch { _ in executed = true }
        await job.join()  // wait for block to finish
        #expect(executed)
    }

    @Test func launchAddsChildToScope() async throws {
        let scope = SwiftieScope(context: SwiftieContext() + DispatcherDefault())
        let job = try await scope.launch { _ in }
        await job.join()
        #expect(await scope.rootJob.childCount == 1)
    }
    
    @Test func deferredReturnsValue() async throws {
        let scope = SwiftieScope(context: SwiftieContext() + DispatcherDefault())
        let deferred = try await scope.asynchron { _ in 42 }
        let result = try await deferred.value()
        #expect(result == 42)
        #expect(await deferred.isCompleted)
    }
    
    @Test func multipleWaitingDeferreds() async throws {
        let scope = SwiftieScope(context: SwiftieContext() + DispatcherDefault())
        let deferred = try await scope.asynchron { _ in 42 }
        async let a = deferred.value()
        async let b = deferred.value()
        #expect(try await a == 42)
        #expect(try await b == 42)
    }
    
    @Test func deferredResultIsCached() async throws {
        let scope = SwiftieScope(context: SwiftieContext() + DispatcherDefault())
        let deferred = try await scope.asynchron { _ in 42 }
        let first = try await deferred.value()
        let second = try await deferred.value()
        #expect(first == second)
    }
    
    @Test func concurrentDeferred() async throws {
        let scope = SwiftieScope(context: SwiftieContext() + DispatcherDefault())
        let a = try await scope.asynchron { _ in 1 }
        let b = try await scope.asynchron { _ in 2 }
        #expect(try await a.value() + b.value() == 3)
    }

    // 3. Error propagation
    @Test func deferredPropagatesError() async throws {
        struct TestError: Error {}
        let scope = SwiftieScope(context: SwiftieContext() + DispatcherDefault())
        let deferred = try await scope.asynchron { _ in throw TestError() }
        await #expect(throws: TestError.self) {
            try await deferred.value()
        }
        #expect(await deferred.isCompleted)
    }

    // 4. Cancellation
    @Test func cancellationStopsAsynchronJob() async throws {
        let scope = SwiftieScope(context: SwiftieContext() + DispatcherDefault())
        await scope.cancel()
        
        await #expect(throws: SwiftieError.cancellation) {
            try await scope.asynchron { _ in  5 }
        }
        #expect(await scope.rootJob.isCanceled)
    }
    
    @Test func cancellationStopsLaunchedJob() async throws {
        let scope = SwiftieScope(context: SwiftieContext() + DispatcherDefault())
        await scope.cancel()
        
        await #expect(throws: SwiftieError.cancellation) {
            try await scope.launch { _ in }
        }
        #expect(await scope.rootJob.isCanceled)
    }
}

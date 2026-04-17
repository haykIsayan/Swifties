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
        let scope = SwiftieScope(context: SwiftieContext() + SwiftieDispatchers.general)
        var executed = false
        let job = try await scope.launch { _ in executed = true }
        await job.join()  // wait for block to finish
        #expect(executed)
    }

    @Test func launchAddsChildToScope() async throws {
        let scope = SwiftieScope(context: SwiftieContext() + SwiftieDispatchers.general)
        let job = try await scope.launch { _ in }
        await job.join()
        #expect(await scope.rootJob.childCount == 1)
    }
    
    @Test func deferredReturnsValue() async throws {
        let scope = SwiftieScope(context: SwiftieContext() + SwiftieDispatchers.general)
        let deferred = try await scope.asynchron { _ in 42 }
        let result = try await deferred.value()
        #expect(result == 42)
        #expect(await deferred.isCompleted)
    }
    
    @Test func multipleWaitingDeferreds() async throws {
        let scope = SwiftieScope(context: SwiftieContext() + SwiftieDispatchers.general)
        let deferred = try await scope.asynchron { _ in 42 }
        async let a = deferred.value()
        async let b = deferred.value()
        #expect(try await a == 42)
        #expect(try await b == 42)
    }
    
    @Test func deferredResultIsCached() async throws {
        let scope = SwiftieScope(context: SwiftieContext() + SwiftieDispatchers.general)
        let deferred = try await scope.asynchron { _ in 42 }
        let first = try await deferred.value()
        let second = try await deferred.value()
        #expect(first == second)
    }
    
    @Test func concurrentDeferred() async throws {
        let scope = SwiftieScope(context: SwiftieContext() + SwiftieDispatchers.general)
        let a = try await scope.asynchron { _ in 1 }
        let b = try await scope.asynchron { _ in 2 }
        #expect(try await a.value() + b.value() == 3)
    }

    @Test func deferredPropagatesError() async throws {
        struct TestError: Error {}
        let scope = SwiftieScope(context: SwiftieContext() + SwiftieDispatchers.general)
        let deferred = try await scope.asynchron { _ in throw TestError() }
        await #expect(throws: TestError.self) {
            try await deferred.value()
        }
        #expect(await deferred.isFailed)
    }

    // 4. Cancellation
    @Test func cancellationStopsAsynchronJob() async throws {
        let scope = SwiftieScope(context: SwiftieContext() + SwiftieDispatchers.general)
        await scope.cancel()
        
        await #expect(throws: SwiftieError.cancellation) {
            try await scope.asynchron { _ in  5 }
        }
        #expect(await scope.rootJob.isCanceled)
    }
    
    @Test func cancellationStopsLaunchedJob() async throws {
        let scope = SwiftieScope(context: SwiftieContext() + SwiftieDispatchers.general)
        await scope.cancel()
        
        await #expect(throws: SwiftieError.cancellation) {
            try await scope.launch { _ in }
        }
        #expect(await scope.rootJob.isCanceled)
    }
    
    @Test func withContextSwitchesDispatcher() async throws {
        let scope = SwiftieScope(context: SwiftieDispatchers.general)
        
        var dispatcherInsideBlock: (any SwiftieDispatcher)? = nil
        
        try await scope.withContext(context: SwiftieDispatchers.io) { innerScope in
            dispatcherInsideBlock = await innerScope.context[SwiftieDispatcher.self]
        }
        
        #expect(dispatcherInsideBlock is SwiftieDispatcherIO)
    }
    
    @Test func childScopeInheritsParentContext() async throws {
        let ctx = SwiftieDispatchers.general + SwiftieName(name: "parent")
        let scope = SwiftieScope(context: ctx)
        var nameInsideBlock: String? = nil
        
        let job = try await scope.launch { childScope in
            nameInsideBlock = await childScope.context[SwiftieName.self]?.name
        }
        await job.join()
        
        #expect(nameInsideBlock == "parent")
    }
    
    @Test func nestedWithContextInnermostWins() async throws {
        let scope = SwiftieScope(context: SwiftieDispatchers.general)
        var innermostDispatcher: (any SwiftieDispatcher)? = nil
        
        let job = try await scope.launch { scope in
            try await scope.withContext(context: SwiftieDispatchers.io) { scope in
                try await scope.withContext(context: SwiftieDispatchers.main) { scope in
                    innermostDispatcher = await scope.context[SwiftieDispatcher.self]
                }
            }
        }
        await job.join()
        #expect(innermostDispatcher is SwiftieDispatcherMain)
    }
    
    @Test func dispatcherRestoredAfterWithContext() async throws {
        let scope = SwiftieScope(context: SwiftieDispatchers.general)
        
        let job = try await scope.launch { scope in
            try await scope.withContext(context: SwiftieDispatchers.io) { innerScope in
                
            }
        }
        await job.join()
        let dispatcherAfter = await scope.context[SwiftieDispatcher.self]
        #expect(dispatcherAfter is SwiftieDispatcherDefault)
    }
    
    @Test func childFailureCancelsScope() async throws {
        let scope = SwiftieScope(context: SwiftieDispatchers.general)
        
        let failingJob = try await scope.launch { _ in
            try await Task.sleep(for: .milliseconds(50))
            throw SwiftieError.failure
        }
        let siblingJob = try await scope.launch { _ in
            try await Task.sleep(for: .seconds(2))
        }
        
        await failingJob.join()
        await siblingJob.join()
        
        #expect(await scope.rootJob.isFailed)
        #expect(await failingJob.isFailed)  // ← add
        #expect(await siblingJob.isCanceled)  // ← add
    }
    
    @Test func supervisorIsolatesChildFailures() async throws {
        let scope = supervisorScope(context: SwiftieDispatchers.general)
        
        let failingJob = try await scope.launch { _ in
            throw SwiftieError.failure
        }
        let siblingJob = try await scope.launch { _ in
            try await Task.sleep(for: .seconds(2))
        }
        
        await failingJob.join()
        
        #expect(await siblingJob.isCanceled == false)
        #expect(await scope.rootJob.isCanceled == false)
    }
    
    @Test func nestedSupervisorScope() async throws {
        let outer = supervisorScope(context: SwiftieDispatchers.general)
        
        let outerJob = try await outer.launch { _ in
            let inner = supervisorScope(context: SwiftieDispatchers.general)
            
            let failingJob = try await inner.launch { _ in
                throw SwiftieError.failure
            }
            let siblingJob = try await inner.launch { _ in
                try await Task.sleep(for: .seconds(2))
            }
            
            await failingJob.join()
            
            // sibling should survive — inner is supervisor
            #expect(await siblingJob.isCanceled == false)
            #expect(await inner.rootJob.isCanceled == false)
        }
        
        let outerSiblingJob = try await outer.launch { _ in
            try await Task.sleep(for: .seconds(2))
        }
        
        await outerJob.join()
        
        // outer scope unaffected too
        #expect(await outerSiblingJob.isCanceled == false)
        #expect(await outer.rootJob.isCanceled == false)
    }
}

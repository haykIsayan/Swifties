//
//  SwiftieContext.swift
//  project-swifties
//
//  Created by Hayk Isayan on 4/30/26.
//


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

//
//  JobExecutable.swift
//  project-swifties
//
//  Created by Hayk Isayan on 5/1/26.
//

protocol SwiftieExecutable {
    func execute() async
    func cancel() async
}

actor SwiftieExecutor: SwiftieExecutable {
    
    private let taskBuilder: () -> Task<Void, Error>
    
    init(taskBuilder: @escaping () -> Task<Void, Error>) {
        self.taskBuilder = taskBuilder
    }
    
    private var task: Task<Void, Error>?
    
    func execute() async {
        guard task == nil else { return }
        self.task = taskBuilder()
    }
    
    func cancel() async {
        task?.cancel()
    }
}



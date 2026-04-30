//
//  JobStateMachine.swift
//  project-swifties
//
//  Created by Hayk Isayan on 4/30/26.
//

typealias JobStateMachine = [JobState: [JobEvent: JobState]]

let jobStateMachine: JobStateMachine = [
    .new: [
        .start: .active,
        .cancel: .canceling,
        .fail: .failing
    ],
    .active: [
        .complete: .completing,
        .cancel: .canceling,
        .fail: .failing
    ],
    .completing: [
        .childrenCompleted: .completed,
        .cancel: .canceling
    ],
    .canceling: [
        .childrenCompleted: .canceled
    ],
    .failing: [
        .childrenCompleted: .failed
    
    ]
]

func interpret(trigger event: JobEvent, from currentState: JobState) -> JobState? {
    return jobStateMachine[currentState]?[event]
}

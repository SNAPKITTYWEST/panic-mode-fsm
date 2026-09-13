"============================================================
 StateMachine.st — Panic-Mode State Machine in Smalltalk 80

 Deterministic 4-state FSM with deferred token buffer.
 States: #NORMAL #OVERLOAD #RECOVERY #ESCALATE
============================================================"

Object subclass: #StateMachine
    instanceVariableNames: 'state transitions buffer log'
    classVariableNames: ''
    poolDictionaries: ''
    category: 'SovereignSomatic'

"============================================================
 Initialization
============================================================"
StateMachine>>initialize
    super initialize.
    state       := #NORMAL.
    transitions := Dictionary new.
    buffer      := OrderedCollection new.
    log         := OrderedCollection new.

    "--- NORMAL -----------------------------------------------"
    transitions at: #NORMAL , #SHIFT
        put: [ self logTransition: 'NORMAL --SHIFT--> NORMAL'.
               state := #NORMAL ].
    transitions at: #NORMAL , #REDUCE
        put: [ self logTransition: 'NORMAL --REDUCE--> NORMAL'.
               state := #NORMAL ].
    transitions at: #NORMAL , #NO_ACTION
        put: [ self logTransition: 'NORMAL --NO_ACTION--> OVERLOAD'.
               state := #OVERLOAD ].

    "--- OVERLOAD ---------------------------------------------"
    transitions at: #OVERLOAD , #NO_ACTION
        put: [ self logTransition: 'OVERLOAD --NO_ACTION--> RECOVERY'.
               state := #RECOVERY ].
    transitions at: #OVERLOAD , #ESCALATE_REQ
        put: [ self logTransition: 'OVERLOAD --ESCALATE_REQ--> ESCALATE'.
               state := #ESCALATE ].

    "--- RECOVERY ---------------------------------------------"
    transitions at: #RECOVERY , #SYNC
        put: [ self logTransition: 'RECOVERY --SYNC--> NORMAL'.
               state := #NORMAL.
               self drainBuffer ].
    transitions at: #RECOVERY , #TIMEOUT
        put: [ self logTransition: 'RECOVERY --TIMEOUT--> ESCALATE'.
               state := #ESCALATE ].

    "--- ESCALATE is terminal — no outgoing transitions ------"

"============================================================
 Event processing
============================================================"
StateMachine>>process: anEvent
    | transition |
    "In RECOVERY, buffer overloading tokens rather than dropping them."
    (state = #RECOVERY and: [ anEvent ~= #SYNC and: [ anEvent ~= #TIMEOUT ] ])
        ifTrue: [ buffer addLast: anEvent. ^ self ].

    transition := transitions
        at: state , anEvent
        ifAbsent: [ nil ].
    transition isNil ifTrue: [ ^ self ].
    transition value.

"============================================================
 Deferred buffer management
============================================================"
StateMachine>>drainBuffer
    "Re-process all deferred tokens now that we're NORMAL."
    | pending |
    pending := buffer copy.
    buffer   := OrderedCollection new.
    pending do: [ :tok | self process: tok ].

StateMachine>>deferLast
    "Pop one token from the deferred buffer."
    buffer isEmpty ifTrue: [ ^ nil ].
    ^ buffer removeFirst.

StateMachine>>bufferSize
    ^ buffer size.

"============================================================
 Inspection
============================================================"
StateMachine>>currentState
    ^ state.

StateMachine>>logTransition: aString
    log addLast: aString.

StateMachine>>printLog
    log do: [ :entry | Transcript showCr: entry ].

StateMachine>>reset
    state  := #NORMAL.
    buffer := OrderedCollection new.
    log    := OrderedCollection new.

"============================================================
 Usage example (run in a Workspace)
============================================================

| sm |
sm := StateMachine new.

sm process: #SHIFT.       'NORMAL'
sm process: #SHIFT.       'NORMAL'
sm process: #NO_ACTION.   'NORMAL -> OVERLOAD'
sm process: #NO_ACTION.   'OVERLOAD -> RECOVERY'
sm process: #SYNC.        'RECOVERY -> NORMAL (buffer drained)'
Transcript showCr: sm currentState.  '=> NORMAL'

sm process: #NO_ACTION.   'NORMAL -> OVERLOAD'
sm process: #ESCALATE_REQ.'OVERLOAD -> ESCALATE'
Transcript showCr: sm currentState.  '=> ESCALATE'

sm printLog.

============================================================"

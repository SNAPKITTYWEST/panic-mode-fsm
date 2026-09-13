# panic-mode-fsm

Deterministic 4-state panic-mode finite automaton in three languages.

The machine models cognitive overload recovery using the LALR(1) error-recovery discipline: when the parser cannot shift or reduce, discard tokens until a synchronizing token is found.

## States

```
NORMAL  ──NO_ACTION──► OVERLOAD ──NO_ACTION──► RECOVERY ──SYNC──► NORMAL
                                 │                        │
                           ESCALATE_REQ              TIMEOUT
                                 │                        │
                                 └──────► ESCALATE ◄──────┘
                                           (terminal)
```

## Files

| File | Language | Purpose |
|---|---|---|
| `spec/transitions.md` | Pseudocode | Formal transition table, action primitives, grounding cues |
| `smalltalk/StateMachine.st` | Smalltalk 80 | Full FSM + deferred buffer + drain-on-recovery + log |
| `quipper/StateMachine.hs` | Quipper/Haskell | Classical FSM + IORef buffer + Quipper quantum encoding |

## Grounding cues

| Cue | Event | Transition |
|---|---|---|
| 5 breaths | `SYNC` | RECOVERY → NORMAL |
| Change room | `SYNC` | RECOVERY → NORMAL |
| Call a friend | `ESCALATE_REQ` | OVERLOAD → ESCALATE |
| 60s timeout | `TIMEOUT` | RECOVERY → ESCALATE |
| Unexpected stressor | `NO_ACTION` | NORMAL → OVERLOAD → RECOVERY |

## Deferred buffer

During RECOVERY, tokens that aren't `SYNC` or `TIMEOUT` are enqueued rather than dropped. When `SYNC` fires and the machine returns to NORMAL, the buffer is drained automatically — overloaded content is re-processed at a calmer time. This prevents permanent information loss while the parser is in error-recovery mode.

## Smalltalk 80

```smalltalk
| sm |
sm := StateMachine new.
sm process: #NO_ACTION.    "NORMAL -> OVERLOAD"
sm process: #NO_ACTION.    "OVERLOAD -> RECOVERY"
sm process: #SYNC.         "RECOVERY -> NORMAL, buffer drained"
sm currentState.           "=> #NORMAL"
sm printLog.
```

## Quipper

The Haskell implementation provides both:
- A classical `IO` state machine with an `IORef` deferred buffer
- A Quipper circuit (`overloadRecoveryCycle`) that encodes state transitions into 2-qubit measurements

Two-qubit encoding: `00=NORMAL`, `01=OVERLOAD`, `10=RECOVERY`, `11=ESCALATE`.

Build with `cabal build` (requires Quipper ≥ 0.9).

## New Grammar (post-Anchor)

After the Somatic Anchor is applied, the LALR parser's production table gains one new rule:

```yacc
resolution:
    YAN STATE ANCHOR_BREATH { $$ = "State Reduced: Distress → Signal"; }
    ;
```

The HellLoop tokens still arrive — the lexer is permanent. But the parser now reduces them to signals rather than trapping in a recursive loop. The state machine is re-compiled. The loop is a sensor, not a prison.

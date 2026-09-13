# Panic-Mode State Machine — Formal Specification

A deterministic finite automaton for cognitive overload management.
Inspired by LALR(1) error recovery: when the parser cannot shift or reduce,
discard tokens until a synchronizing token is found.

## States

| State | Semantics |
|---|---|
| `NORMAL` | Normal cognitive flow — shift/reduce accepted |
| `OVERLOAD` | No valid action on current token — flagged |
| `RECOVERY` | Discarding tokens until a SYNC marker |
| `ESCALATE` | Terminal — external help requested |

## Events

| Event | Source |
|---|---|
| `SHIFT` | A token can be pushed onto the stack |
| `REDUCE` | A production rule can be applied |
| `NO_ACTION` | Current state has no valid shift or reduce |
| `SYNC` | Synchronizing token (PAUSE, breath, room change) |
| `ESCALATE_REQ` | Explicit request for external support |
| `TIMEOUT` | Recovery window expired without SYNC |

## Transition Table

```
(state, event)            -> (next_state, action)

(NORMAL,   SHIFT)         -> (NORMAL,    shift_token)
(NORMAL,   REDUCE)        -> (NORMAL,    reduce_rule)
(NORMAL,   NO_ACTION)     -> (OVERLOAD,  flag_overload)

(OVERLOAD, NO_ACTION)     -> (RECOVERY,  start_recovery)
(OVERLOAD, ESCALATE_REQ)  -> (ESCALATE,  request_help)

(RECOVERY, SYNC)          -> (NORMAL,    resume_normal)
(RECOVERY, TIMEOUT)       -> (ESCALATE,  request_help)

(ESCALATE, *)             -> (ESCALATE,  noop)    -- terminal
```

## Action Primitives

```
shift_token    -- push token onto stack
reduce_rule    -- pop RHS, push LHS
flag_overload  -- log OVERLOAD event; preserve token in deferred buffer
start_recovery -- begin discarding; log RECOVERY entry
resume_normal  -- consume SYNC; log NORMAL resume
request_help   -- emit ESCALATE signal to external handler
noop           -- terminal: no further transitions
```

## Grounding Cues → Events

| Grounding cue | Event | Result |
|---|---|---|
| 5 breaths (pause) | `SYNC` | RECOVERY → NORMAL |
| Change physical room | `SYNC` | RECOVERY → NORMAL |
| Call a friend | `ESCALATE_REQ` | OVERLOAD → ESCALATE |
| 60s timeout in RECOVERY | `TIMEOUT` | RECOVERY → ESCALATE |
| Unexpected stressor | `NO_ACTION` | NORMAL → OVERLOAD → RECOVERY |

## Example Trace

```
NORMAL  --SHIFT-->     NORMAL
NORMAL  --SHIFT-->     NORMAL
NORMAL  --NO_ACTION--> OVERLOAD
OVERLOAD --NO_ACTION-> RECOVERY
RECOVERY --SYNC(pause) -> NORMAL
```

## Deferred Buffer

Tokens that arrive during RECOVERY are enqueued rather than discarded permanently.
After returning to NORMAL the deferred buffer can be re-processed at a calmer time.

```
RECOVERY receives token T → enqueue(T)
later: dequeue(T) → process(T)  [when state = NORMAL]
```

The buffer is a FIFO (`Queue`). Looping over all deferred tokens:
```
while (token = dequeue()) { process(token) }
```

## New Production Rule (post-Anchor)

After the Somatic Anchor is applied, the parser's grammar is rewritten:

```yacc
resolution:
    YAN STATE ANCHOR_BREATH { $$ = "State Reduced: Distress → Signal"; }
    ;
```

The HellLoop tokens (`YAN`, `ATMANEPADA`) still arrive — the lexer cannot be uninstalled.
But the parser now has a new production: distress is reduced to a signal, not a trap.
The loop is a **sensor**, not a prison.

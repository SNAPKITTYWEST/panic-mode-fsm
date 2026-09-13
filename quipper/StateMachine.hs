{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}

import Quipper
import QuipperLib.Classical

-- ─────────────────────────────────────────────
-- State & Event types
-- ─────────────────────────────────────────────

data State = Normal | Overload | Recovery | Escalate
  deriving (Eq, Show)

data Event = Shift | Reduce | NoAction | Sync | EscalateReq | Timeout
  deriving (Eq, Show)

-- ─────────────────────────────────────────────
-- Classical helpers
-- ─────────────────────────────────────────────

stateToBits :: State -> (Bit, Bit)
stateToBits Normal   = (false, false)
stateToBits Overload = (false, true)
stateToBits Recovery = (true,  false)
stateToBits Escalate = (true,  true)

bitsToState :: (Bit, Bit) -> State
bitsToState (b1, b2)
  | b1 == false && b2 == false = Normal
  | b1 == false && b2 == true  = Overload
  | b1 == true  && b2 == false = Recovery
  | otherwise                  = Escalate

-- Encode event as Int 0–5
eventToInt :: Event -> Int
eventToInt Shift       = 0
eventToInt Reduce      = 1
eventToInt NoAction    = 2
eventToInt Sync        = 3
eventToInt EscalateReq = 4
eventToInt Timeout     = 5

-- Classical transition table
nextState :: State -> Int -> State
nextState Normal   0 = Normal
nextState Normal   1 = Normal
nextState Normal   2 = Overload

nextState Overload 2 = Recovery
nextState Overload 4 = Escalate

nextState Recovery 3 = Normal
nextState Recovery 5 = Escalate

nextState Escalate _ = Escalate  -- terminal

-- ─────────────────────────────────────────────
-- Quipper circuit
--
-- State held in two qubits:
--   00 = Normal   01 = Overload
--   10 = Recovery 11 = Escalate
--
-- One step: initialise state qubits, compute next state classically,
-- re-init to new state, measure.
-- ─────────────────────────────────────────────

stateMachineCircuit :: Circ (Bit, Bit)
stateMachineCircuit = do
  -- 1. Start in NORMAL
  curStateQ <- qinit (false, false)

  -- 2. Event: NO_ACTION (binary 010 = 2) -> NORMAL -> OVERLOAD
  evQ <- qinit (false, true, false)

  -- 3. Compute next state classically
  let curState = bitsToState (classical id curStateQ)
      evInt    = 2   -- NoAction
      newState = nextState curState evInt

  -- 4. Re-init state qubits to new state
  let (nb1, nb2) = stateToBits newState
  newStateQ <- qinit (nb1, nb2)

  -- 5. Measure
  m1 <- measure (fst newStateQ)
  m2 <- measure (snd newStateQ)

  return (m1, m2)

-- Full overload-recovery cycle circuit:
-- NORMAL --NoAction--> OVERLOAD --NoAction--> RECOVERY --Sync--> NORMAL
overloadRecoveryCycle :: Circ (Bit, Bit, Bit, Bit, Bit, Bit)
overloadRecoveryCycle = do
  -- Step 1
  let s1 = nextState Normal   2  -- NoAction
  let (s1b1, s1b2) = stateToBits s1
  q1 <- qinit (s1b1, s1b2)
  m1a <- measure (fst q1)
  m1b <- measure (snd q1)

  -- Step 2
  let s2 = nextState Overload 2  -- NoAction
  let (s2b1, s2b2) = stateToBits s2
  q2 <- qinit (s2b1, s2b2)
  m2a <- measure (fst q2)
  m2b <- measure (snd q2)

  -- Step 3
  let s3 = nextState Recovery 3  -- Sync
  let (s3b1, s3b2) = stateToBits s3
  q3 <- qinit (s3b1, s3b2)
  m3a <- measure (fst q3)
  m3b <- measure (snd q3)

  return (m1a, m1b, m2a, m2b, m3a, m3b)

main :: IO ()
main = print_generic Preview stateMachineCircuit

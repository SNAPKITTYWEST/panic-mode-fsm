{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE LambdaCase #-}
-- ============================================================
-- StateMachine.hs — Panic-Mode FSM in Quipper / Haskell
--
-- Classical state machine with a two-qubit quantum encoding.
-- The state transitions are purely classical (deterministic FSM).
-- The qubit encoding provides a mapping for future quantum circuit expansion.
--
-- States (2-qubit encoding):
--   Normal    = (false, false) = 00
--   Overload  = (false, true)  = 01
--   Recovery  = (true,  false) = 10
--   Escalate  = (true,  true)  = 11
-- ============================================================

import Quipper
import QuipperLib.Classical
import Data.IORef
import Control.Monad (forM_)

-- ─────────────────────────────────────────────
-- State & Event types
-- ─────────────────────────────────────────────

data State = Normal | Overload | Recovery | Escalate
  deriving (Eq, Show)

data Event
  = Shift
  | Reduce
  | NoAction
  | Sync
  | EscalateReq
  | Timeout
  deriving (Eq, Show)

-- ─────────────────────────────────────────────
-- Classical encoding helpers
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

-- ─────────────────────────────────────────────
-- Classical transition function
-- ─────────────────────────────────────────────

nextState :: State -> Event -> State
nextState Normal   Shift       = Normal
nextState Normal   Reduce      = Normal
nextState Normal   NoAction    = Overload

nextState Overload NoAction    = Recovery
nextState Overload EscalateReq = Escalate

nextState Recovery Sync        = Normal
nextState Recovery Timeout     = Escalate

nextState Escalate _           = Escalate  -- terminal

-- ─────────────────────────────────────────────
-- Deferred buffer (classical IO)
-- ─────────────────────────────────────────────

type Buffer = IORef [Event]

newBuffer :: IO Buffer
newBuffer = newIORef []

enqueue :: Buffer -> Event -> IO ()
enqueue buf ev = modifyIORef buf (++ [ev])

dequeue :: Buffer -> IO (Maybe Event)
dequeue buf = do
  evs <- readIORef buf
  case evs of
    []     -> return Nothing
    (e:es) -> writeIORef buf es >> return (Just e)

drainBuffer :: Buffer -> (Event -> IO ()) -> IO ()
drainBuffer buf process = do
  ev <- dequeue buf
  case ev of
    Nothing -> return ()
    Just e  -> process e >> drainBuffer buf process

-- ─────────────────────────────────────────────
-- Classical FSM runner (IO)
-- ─────────────────────────────────────────────

data Machine = Machine
  { machState  :: IORef State
  , machBuffer :: Buffer
  , machLog    :: IORef [String]
  }

newMachine :: IO Machine
newMachine = Machine <$> newIORef Normal <*> newBuffer <*> newIORef []

logEntry :: Machine -> String -> IO ()
logEntry m s = modifyIORef (machLog m) (++ [s])

processEvent :: Machine -> Event -> IO ()
processEvent m ev = do
  st <- readIORef (machState m)
  let next = nextState st ev
  let msg  = show st ++ " --" ++ show ev ++ "--> " ++ show next
  logEntry m msg
  writeIORef (machState m) next
  -- Buffer non-SYNC/TIMEOUT events during RECOVERY
  case (st, ev) of
    (Recovery, Sync)    -> drainBuffer (machBuffer m) (processEvent m)
    (Recovery, Timeout) -> return ()
    (Recovery, _)       -> enqueue (machBuffer m) ev >> logEntry m ("  buffered: " ++ show ev)
    _                   -> return ()

printLog :: Machine -> IO ()
printLog m = do
  entries <- readIORef (machLog m)
  mapM_ putStrLn entries

-- ─────────────────────────────────────────────
-- Quipper circuit: two-qubit state encoding
-- ─────────────────────────────────────────────

-- Classical-in-quantum: initialise state qubits to a given State,
-- apply one event transition, return new state qubits.
stateMachineStep :: State -> Event -> Circ (Bit, Bit)
stateMachineStep initState ev = do
  let (b1, b2)       = stateToBits initState
  let newS           = nextState initState ev
  let (nb1, nb2)     = stateToBits newS
  stateQ  <- qinit (b1,  b2)
  nextQ   <- qinit (nb1, nb2)
  -- Measure to extract classical outcome
  m1 <- measure (fst nextQ)
  m2 <- measure (snd nextQ)
  return (m1, m2)

-- Full circuit: Normal --NoAction--> Overload --NoAction--> Recovery --Sync--> Normal
-- Demonstrates the three-step overload-recovery cycle as a quantum circuit.
overloadRecoveryCycle :: Circ (Bit, Bit, Bit, Bit, Bit, Bit)
overloadRecoveryCycle = do
  -- Step 1: NORMAL --NoAction--> OVERLOAD
  (s1a, s1b) <- stateMachineStep Normal   NoAction
  -- Step 2: OVERLOAD --NoAction--> RECOVERY
  (s2a, s2b) <- stateMachineStep Overload NoAction
  -- Step 3: RECOVERY --Sync--> NORMAL
  (s3a, s3b) <- stateMachineStep Recovery Sync
  return (s1a, s1b, s2a, s2b, s3a, s3b)

-- ─────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────

main :: IO ()
main = do
  putStrLn "=== Classical FSM trace ==="
  m <- newMachine
  mapM_ (processEvent m)
    [ Shift, Shift, NoAction   -- NORMAL x2, then OVERLOAD
    , NoAction                  -- RECOVERY
    , Sync                      -- NORMAL (buffer drained)
    , NoAction                  -- OVERLOAD again
    , EscalateReq               -- ESCALATE (terminal)
    ]
  printLog m

  putStrLn ""
  putStrLn "=== Quipper circuit preview: overload-recovery cycle ==="
  print_generic Preview overloadRecoveryCycle

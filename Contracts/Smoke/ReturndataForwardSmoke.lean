import Compiler.CheckContract
import Contracts.Common

namespace Contracts.Smoke

open Contracts
open Verity hiding pure bind
open Verity.EVM.Uint256

/-! Returndata forwarding: `forward` calls `callee` with the words `flag, length` and ends
the call with the callee's returndata, verbatim, as revert payload (`revertReturndata`) or
success payload (`returnReturndata`). -/
verity_contract ReturndataForwardSmoke where
  storage
    calls : Uint256 := slot 0

  constants
    ALL_GAS : Uint256 := 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff

  -- Modifiers are precondition-only: their statements run before the body, none after
  -- (`docs/MODIFIERS_AND_INHERITANCE.md`), so a tail `returnReturndata` skips nothing.
  modifier countCall := do
    let current ← getStorage calls
    setStorage calls (add current 1)

  function reentrancy_trusted forward (callee : Address, flag : Uint256, length : Uint256)
    local_obligations [returndata_forwarding := assumed "The callee's returndata is forwarded verbatim as this call's revert or success payload."]
    : Unit := do
    mstore 0 flag
    mstore 32 length
    let ok := call ALL_GAS (addressToWord callee) 0 0 64 0 0
    if ok == 0 then
      revertReturndata
    else
      returnReturndata

  -- Tail of one branch; on failure the other path falls through to the end (empty success).
  function reentrancy_trusted forwardIfSuccess (callee : Address, flag : Uint256, length : Uint256)
    local_obligations [returndata_forwarding := assumed "The callee's returndata is forwarded verbatim on success."]
    : Unit := do
    mstore 0 flag
    mstore 32 length
    let ok := call ALL_GAS (addressToWord callee) 0 0 64 0 0
    if ok != 0 then
      returnReturndata

  -- Plain tail: whatever the callee returned or reverted with becomes the success payload.
  function reentrancy_trusted forwardAlways (callee : Address, flag : Uint256, length : Uint256)
    local_obligations [returndata_forwarding := assumed "The callee's returndata is forwarded verbatim as success payload."]
    : Unit := do
    mstore 0 flag
    mstore 32 length
    let _ok := call ALL_GAS (addressToWord callee) 0 0 64 0 0
    returnReturndata

  -- With a modifier: its write lands before the call, and the tail still ends the call.
  function reentrancy_trusted forwardCounted (callee : Address, flag : Uint256, length : Uint256) with countCall
    local_obligations [returndata_forwarding := assumed "The callee's returndata is forwarded verbatim as success payload."]
    : Unit := do
    mstore 0 flag
    mstore 32 length
    let _ok := call ALL_GAS (addressToWord callee) 0 0 64 0 0
    returnReturndata

  function callCount () : Uint256 := do
    let current ← getStorage calls
    return current

/-- info: #check_contract ok: Contracts.Smoke.ReturndataForwardSmoke -/
#guard_msgs in
#check_contract ReturndataForwardSmoke

-- `returnReturndata` is a low-level mechanic: it needs `unsafe` or `local_obligations`.
verity_contract ReturnReturndataRequiresBoundary where
  storage

  fallback := do
    returnReturndata

/--
error: #check_contract failed for 'Contracts.Smoke.ReturnReturndataRequiresBoundary': Compilation error: function 'fallback' uses low-level/assembly mechanic(s) returnReturndata outside an unsafe block without any local_obligations entry (Issue #1424 (controlled unsafe/assembly escape hatches)). Wrap the low-level code in `unsafe "reason" do` or add local_obligations [...] to make the trust boundary explicit.
-/
#guard_msgs in
#check_contract ReturnReturndataRequiresBoundary

-- Tail position only: nothing may follow it in its block ...
/--
error: `returnReturndata` ends the call: it is only allowed as the last statement of a Unit function body, directly or under if/else, with nothing after it on any path (not in loops, constructors or modifiers)
-/
#guard_msgs in
verity_contract ReturnReturndataRejectsStatementAfter where
  storage
    seen : Uint256 := slot 0

  fallback local_obligations [returndata_forwarding := assumed "forwarded verbatim"] := do
    returnReturndata
    setStorage seen 1

-- ... nor after the enclosing `if`, ...
/--
error: `returnReturndata` ends the call: it is only allowed as the last statement of a Unit function body, directly or under if/else, with nothing after it on any path (not in loops, constructors or modifiers)
-/
#guard_msgs in
verity_contract ReturnReturndataRejectsStatementAfterIf where
  storage
    seen : Uint256 := slot 0

  function reentrancy_trusted forward (c : Uint256)
    local_obligations [returndata_forwarding := assumed "forwarded verbatim"]
    : Unit := do
    if c == 0 then
      returnReturndata
    setStorage seen 1

-- ... and it is never accepted inside a loop.
/--
error: `returnReturndata` ends the call: it is only allowed as the last statement of a Unit function body, directly or under if/else, with nothing after it on any path (not in loops, constructors or modifiers)
-/
#guard_msgs in
verity_contract ReturnReturndataRejectsLoop where
  storage

  function reentrancy_trusted forward (n : Uint256)
    local_obligations [returndata_forwarding := assumed "forwarded verbatim"]
    : Unit := do
    forEach "i" n (do
      returnReturndata)

-- ... nor inside a modifier (its statements run before the body, so never in tail position).
/--
error: `returnReturndata` ends the call: it is only allowed as the last statement of a Unit function body, directly or under if/else, with nothing after it on any path (not in loops, constructors or modifiers)
-/
#guard_msgs in
verity_contract ReturnReturndataRejectsModifier where
  storage

  modifier forwardEarly := do
    returnReturndata

  function reentrancy_trusted forward ()
    with forwardEarly
    local_obligations [returndata_forwarding := assumed "forwarded verbatim"]
    : Unit := do
    pure ()

-- The function must return Unit: the forwarded bytes replace any declared return value.
/--
error: function 'forward' uses `returnReturndata`, which ends the call with the forwarded bytes: its return type must be Unit
-/
#guard_msgs in
verity_contract ReturnReturndataRejectsNonUnit where
  storage

  function reentrancy_trusted forward (c : Uint256)
    local_obligations [returndata_forwarding := assumed "forwarded verbatim"]
    : Uint256 := do
    if c == 0 then
      returnReturndata
    return c

-- A function using `returnReturndata` has no internal-helper form: calling it is rejected.
/--
error: helper call 'forward' uses a parameter or return type that direct macro helper lowering does not support yet, or uses returnReturndata; only static non-fallback/non-receive helpers without returnReturndata can be lowered to internal specs
-/
#guard_msgs in
verity_contract ReturnReturndataNotAnInternalHelper where
  storage

  function reentrancy_trusted forward ()
    local_obligations [returndata_forwarding := assumed "forwarded verbatim"]
    : Unit := do
    returnReturndata

  function reentrancy_trusted relay ()
    local_obligations [returndata_forwarding := assumed "forwarded verbatim"]
    : Unit := do
    forward()

end Contracts.Smoke

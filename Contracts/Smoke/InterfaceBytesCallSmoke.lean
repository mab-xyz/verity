import Contracts.Common

namespace Contracts.Smoke

open Verity hiding pure bind
open Verity.EVM.Uint256

-- ABI-frame typed-interface calls (#1982 progress): a `Bytes` argument is a forwarded
-- `Bytes` parameter or a payload built in place with `abiEncodeCall`, and a `(Bool, Bytes)`
-- return binds the flag and the returned bytes (`bytesLength`, `bytesWord`, `revertBytes`).
-- The compiled calldata is checked against Solidity's `abi.encodeCall` /
-- `abi.encodeWithSelector` in `test/InterfaceBytesCallSmoke.t.sol`.
verity_contract InterfaceBytesCallSmoke where
  storage

  constants
    -- Selectors held by constants: a word, and a left-aligned `bytes4` in a `Bytes32`.
    TRANSFER : Uint256 := 0xa9059cbb
    PAIR_SWAP : Bytes32 := 0x022c0d9f00000000000000000000000000000000000000000000000000000000

  interfaces
    interface IVenues where
      function counterparty(Uint8, Bytes) view returns (Address)
      function tokens(Uint8, Bytes) view returns (Tuple [Address, Address])
    end
    interface ISafe where
      function execTransactionFromModuleReturnData(Address, Uint256, Bytes, Uint8) returns (Tuple [Bool, Bytes])
      function notify(Bytes)
    end

  -- A forwarded `Bytes` parameter, on a view method with one static return.
  function reentrancy_trusted who (venues : IVenues, kind : Uint8, p : Bytes) : Address := do
    let c ← venues.counterparty kind p
    return c

  -- A view method with two static returns, destructured.
  function reentrancy_trusted tokensOf (venues : IVenues, kind : Uint8, p : Bytes) :
      Tuple [Address, Address] := do
    let (tIn, tOut) ← venues.tokens kind p
    return (tIn, tOut)

  -- A forwarded `Bytes` parameter among words; the `(Bool, Bytes)` return.
  function reentrancy_trusted forward (safe : ISafe, dest : Address, val : Uint256, data : Bytes,
      op : Uint8) : Tuple [Bool, Uint256, Uint256, Uint256] := do
    let (ok, ret) ← safe.execTransactionFromModuleReturnData dest val data op
    return (ok, bytesLength ret, bytesWord ret 0, bytesWord ret 1)

  -- A payload of static words built in place; a failed inner call reverts with its data.
  function reentrancy_trusted transferVia (safe : ISafe, token : Address, recipient : Address,
      amt : Uint256) : Uint256 := do
    let (ok, ret) ← safe.execTransactionFromModuleReturnData token 0
      (abiEncodeCall 0xa9059cbb [recipient, amt]) 0
    if !ok then
      revertBytes ret
    return bytesLength ret

  -- A payload built in place around a forwarded `Bytes` parameter.
  function reentrancy_trusted venueSwapVia (safe : ISafe, venues : Address, kind : Uint8,
      p : Bytes, amt : Uint256) : Uint256 := do
    let (ok, ret) ← safe.execTransactionFromModuleReturnData venues 0
      (abiEncodeCall 0x8c973081 [kind, p, amt]) 0
    if !ok then
      revertBytes ret
    return bytesWord ret 0

  -- ETH with no data: an empty `Bytes` argument (Solidity's `""`).
  function reentrancy_trusted payVia (safe : ISafe, recipient : Address, amt : Uint256) :
      Uint256 := do
    let (ok, ret) ← safe.execTransactionFromModuleReturnData recipient amt emptyBytes 0
    if !ok then
      revertBytes ret
    return bytesLength ret

  -- Uniswap V2 `pair.swap(out0, out1, to, "")`: an empty `Bytes` item, a `Bytes32` selector.
  function reentrancy_trusted pairSwapVia (safe : ISafe, pair : Address, out0 : Uint256,
      out1 : Uint256, account : Address) : Uint256 := do
    let (ok, ret) ← safe.execTransactionFromModuleReturnData pair 0
      (abiEncodeCall PAIR_SWAP [out0, out1, account, emptyBytes]) 0
    if !ok then
      revertBytes ret
    return bytesLength ret

  -- A selector held by a `Uint256` constant.
  function reentrancy_trusted transferViaConstant (safe : ISafe, token : Address,
      recipient : Address, amt : Uint256) : Uint256 := do
    let (ok, ret) ← safe.execTransactionFromModuleReturnData token 0
      (abiEncodeCall TRANSFER [recipient, amt]) 0
    if !ok then
      revertBytes ret
    return bytesLength ret

  -- A method without returns.
  function reentrancy_trusted notifyVia (safe : ISafe, data : Bytes) : Unit := do
    safe.notify data

/-! ### ABI-frame methods of `linked_contracts` bindings

An ABI-frame call is routed before any linked hop: the bound body is not run (it takes
argument values and journals nothing, while the compiled call sends head/tail bytes); the
context answers the call, which journals `abiCallBytes`. -/

verity_contract BytesVenueCallee where
  storage

  function view counterparty (kind : Uint8, p : Bytes) : Address := do
    return zeroAddress

verity_contract LinkedBytesCaller where
  storage

  interfaces
    interface IBytesVenue where
      function counterparty(Uint8, Bytes) view returns (Address)
    end

  linked_contracts
    venue : IBytesVenue := BytesVenueCallee

  function reentrancy_trusted who (venue : IBytesVenue, kind : Uint8, p : Bytes) : Address := do
    let c ← venue.counterparty kind p
    return c

verity_contract DeferredBytesCaller where
  storage

  interfaces
    interface IBytesVenue where
      function counterparty(Uint8, Bytes) view returns (Address)
    end

  linked_contracts
    venue : IBytesVenue := deferred

  function reentrancy_trusted who (venue : IBytesVenue, kind : Uint8, p : Bytes) : Address := do
    let c ← venue.counterparty kind p
    return c

/-! ### `abiCallBytes` is Solidity's encoding

Reference bytes from Foundry (`cast calldata`):
`cast calldata "transfer(address,uint256)" 0x…aa 5`,
`cast calldata "swap(uint8,bytes,uint256)" 2 0x0102…21 7` (and `0x`),
`cast calldata "swap(uint256,uint256,address,bytes)" 1 2 0x…cc 0x`, and
`cast calldata "execTransactionFromModuleReturnData(address,uint256,bytes,uint8)"` of
`0x…bb 0 <transfer calldata> 0`, `0x…bb 0 <swap calldata> 0` and `0x…c0 9 0x 0`. -/

private def hexNibble (c : Char) : Nat :=
  if c.isDigit then c.toNat - '0'.toNat else c.toLower.toNat - 'a'.toNat + 10

/-- The bytes of a `0x…` hex string. -/
private def hexBytes (s : String) : List Nat :=
  let cs := s.toList.drop 2
  (List.range (cs.length / 2)).map fun i =>
    hexNibble (cs.getD (2 * i) '0') * 16 + hexNibble (cs.getD (2 * i + 1) '0')

private def transferCalldataHex : String :=
  "0xa9059cbb00000000000000000000000000000000000000000000000000000000000000aa" ++
  "0000000000000000000000000000000000000000000000000000000000000005"

#guard abiCallBytes 0xa9059cbb [.word 0xaa, .word 5] == hexBytes transferCalldataHex

#guard abiCallBytes 0x8c973081
    [.word 2, .bytes (byteArrayOfValues (List.range' 1 33)), .word 7] ==
  hexBytes ("0x8c973081" ++
    "0000000000000000000000000000000000000000000000000000000000000002" ++
    "0000000000000000000000000000000000000000000000000000000000000060" ++
    "0000000000000000000000000000000000000000000000000000000000000007" ++
    "0000000000000000000000000000000000000000000000000000000000000021" ++
    "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20" ++
    "2100000000000000000000000000000000000000000000000000000000000000")

#guard abiCallBytes 0x8c973081 [.word 2, .bytes ByteArray.empty, .word 7] ==
  hexBytes ("0x8c973081" ++
    "0000000000000000000000000000000000000000000000000000000000000002" ++
    "0000000000000000000000000000000000000000000000000000000000000060" ++
    "0000000000000000000000000000000000000000000000000000000000000007" ++
    "0000000000000000000000000000000000000000000000000000000000000000")

#guard abiCallBytes 0x5229073f
    [.word 0xbb, .word 0, .bytes (abiEncodeCall 0xa9059cbb [.word 0xaa, .word 5]), .word 0] ==
  hexBytes ("0x5229073f" ++
    "00000000000000000000000000000000000000000000000000000000000000bb" ++
    "0000000000000000000000000000000000000000000000000000000000000000" ++
    "0000000000000000000000000000000000000000000000000000000000000080" ++
    "0000000000000000000000000000000000000000000000000000000000000000" ++
    "0000000000000000000000000000000000000000000000000000000000000044" ++
    "a9059cbb00000000000000000000000000000000000000000000000000000000" ++
    "000000aa00000000000000000000000000000000000000000000000000000000" ++
    "0000000500000000000000000000000000000000000000000000000000000000")

private def pairSwapCalldataHex : String :=
  "0x022c0d9f" ++
  "0000000000000000000000000000000000000000000000000000000000000001" ++
  "0000000000000000000000000000000000000000000000000000000000000002" ++
  "00000000000000000000000000000000000000000000000000000000000000cc" ++
  "0000000000000000000000000000000000000000000000000000000000000080" ++
  "0000000000000000000000000000000000000000000000000000000000000000"

-- An empty `bytes` item: head = tail offset, tail = a zero length word, no data.
#guard abiCallBytes 0x022c0d9f [.word 1, .word 2, .word 0xcc, .bytes emptyBytes] ==
  hexBytes pairSwapCalldataHex

#guard abiCallBytes 0x5229073f
    [.word 0xbb, .word 0,
      .bytes (abiEncodeCall 0x022c0d9f [.word 1, .word 2, .word 0xcc, .bytes emptyBytes]),
      .word 0] ==
  hexBytes ("0x5229073f" ++
    "00000000000000000000000000000000000000000000000000000000000000bb" ++
    "0000000000000000000000000000000000000000000000000000000000000000" ++
    "0000000000000000000000000000000000000000000000000000000000000080" ++
    "0000000000000000000000000000000000000000000000000000000000000000" ++
    "00000000000000000000000000000000000000000000000000000000000000a4" ++
    (pairSwapCalldataHex.drop 2).toString ++
    "00000000000000000000000000000000000000000000000000000000")

-- An empty `bytes` argument (ETH with no data).
#guard abiCallBytes 0x5229073f [.word 0xc0, .word 9, .bytes emptyBytes, .word 0] ==
  hexBytes ("0x5229073f" ++
    "00000000000000000000000000000000000000000000000000000000000000c0" ++
    "0000000000000000000000000000000000000000000000000000000000000009" ++
    "0000000000000000000000000000000000000000000000000000000000000080" ++
    "0000000000000000000000000000000000000000000000000000000000000000" ++
    "0000000000000000000000000000000000000000000000000000000000000000")

-- The `Bytes32` constant selector is its high four bytes.
#guard abiSelectorOfWord InterfaceBytesCallSmoke.PAIR_SWAP.val = 0x022c0d9f
#guard abiSelectorOfWord InterfaceBytesCallSmoke.TRANSFER.val = 0xa9059cbb

/-! ### Executables: one journal entry with the ABI bytes, answered by the adversary -/

open Compiler.CompilationModel.DenoteExternalCalls (AdversaryModel)

/-- An adversary answering every call with the ABI words of `abi.encode(flag, data)`. -/
private def boolBytesAdversary (flag : Bool) (data : List Nat) : AdversaryModel :=
  { AdversaryModel.stub with
    result := fun _ _ =>
      .success ([if flag then 1 else 0, 64, data.length] ++ abiBytesDataWords data) }

/-- An adversary answering every call with `words`. -/
private def rawAdversary (words : List Nat) : AdversaryModel :=
  { AdversaryModel.stub with result := fun _ _ => .success words }

private def forwardRun (adv : AdversaryModel) :=
  InterfaceBytesCallSmoke.forward (ExecutableCallContext.ofAdversary adv)
    (Verity.wordToAddress 0x5afe) (Verity.wordToAddress 0xbb) 7 (byteArrayOfValues [1, 2, 3]) 3
    Verity.defaultState

#guard
  match forwardRun (boolBytesAdversary true (List.range' 1 33)) with
  | .success (ok, len, w0, w1) s =>
      ok && len == 33 && w0.val == abiReadWord (List.range' 1 33) 0 &&
        w1.val == 33 * 2 ^ 248 &&
        s.calls.map (·.calldata) ==
          [abiCallBytes 0x5229073f [.word 0xbb, .word 7, .bytes (byteArrayOfValues [1, 2, 3]),
            .word 3]]
  | .revert _ _ => false

-- Malformed returndata (a flag word that is not 0/1, a length past the end) reverts.
#guard
  match forwardRun (rawAdversary [2, 64, 0]), forwardRun (rawAdversary [1, 64, 33, 0]) with
  | .revert _ _, .revert _ _ => true
  | _, _ => false

-- A failed inner call (`ok = false`) reverts through `revertBytes`.
#guard
  match InterfaceBytesCallSmoke.transferVia
      (ExecutableCallContext.ofAdversary (boolBytesAdversary false [0xde, 0xad]))
      (Verity.wordToAddress 0x5afe) (Verity.wordToAddress 0x70) (Verity.wordToAddress 0xaa) 5
      Verity.defaultState with
  | .revert msg _ => msg == "revertBytes"
  | .success _ _ => false

-- The nested payload is journaled as Solidity's `abi.encodeWithSelector` bytes.
#guard
  match InterfaceBytesCallSmoke.venueSwapVia
      (ExecutableCallContext.ofAdversary (boolBytesAdversary true (abiWordBytes 777)))
      (Verity.wordToAddress 0x5afe) (Verity.wordToAddress 0x7e) 2
      (byteArrayOfValues (List.range' 1 33)) 9 Verity.defaultState with
  | .success w s =>
      w == 777 &&
        s.calls.map (·.calldata) ==
          [abiCallBytes 0x5229073f [.word 0x7e, .word 0,
            .bytes (byteArrayOfValues (hexBytes ("0x8c973081" ++
              "0000000000000000000000000000000000000000000000000000000000000002" ++
              "0000000000000000000000000000000000000000000000000000000000000060" ++
              "0000000000000000000000000000000000000000000000000000000000000009" ++
              "0000000000000000000000000000000000000000000000000000000000000021" ++
              "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20" ++
              "2100000000000000000000000000000000000000000000000000000000000000"))),
            .word 0]]
  | .revert _ _ => false

-- The executable journals the same bytes for the built payload with an empty item.
#guard
  match InterfaceBytesCallSmoke.pairSwapVia
      (ExecutableCallContext.ofAdversary (boolBytesAdversary true []))
      (Verity.wordToAddress 0x5afe) (Verity.wordToAddress 0xbb) 1 2 (Verity.wordToAddress 0xcc)
      Verity.defaultState with
  | .success _ s =>
      s.calls.map (·.calldata) ==
        [abiCallBytes 0x5229073f [.word 0xbb, .word 0,
          .bytes (byteArrayOfValues (hexBytes pairSwapCalldataHex)), .word 0]]
  | .revert _ _ => false

-- A named `linked_contracts` binding to an ABI-frame method: the context answers (not the
-- bound body, which would return the zero address), and the journal holds the ABI bytes.
private def wordAdversary (word : Nat) : AdversaryModel :=
  { AdversaryModel.stub with result := fun _ _ => .success [word] }

private def linkedWhoCalldata : List Nat :=
  abiCallBytes 0xbf27bce2 [.word 4, .bytes (byteArrayOfValues [1, 2, 3])]

#guard
  match LinkedBytesCaller.who (ExecutableCallContext.ofAdversary (wordAdversary 0xabc))
      (Verity.wordToAddress 0x7e) 4 (byteArrayOfValues [1, 2, 3]) Verity.defaultState with
  | .success c s =>
      c == Verity.wordToAddress 0xabc && s.calls.map (·.calldata) == [linkedWhoCalldata]
  | .revert _ _ => false

-- The same through a `deferred` binding.
#guard
  match DeferredBytesCaller.who (ExecutableCallContext.ofAdversary (wordAdversary 0xabc))
      (Verity.wordToAddress 0x7e) 4 (byteArrayOfValues [1, 2, 3]) Verity.defaultState with
  | .success c s =>
      c == Verity.wordToAddress 0xabc && s.calls.map (·.calldata) == [linkedWhoCalldata]
  | .revert _ _ => false

end Contracts.Smoke

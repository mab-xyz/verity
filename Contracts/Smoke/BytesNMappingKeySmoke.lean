import Contracts.Common

/-!
# Fixed-bytes (`bytes1`..`bytes31`) mapping keys

`mapping(bytes4 => uint256)` and a `bytes4`-keyed struct mapping. Solidity
hashes a `bytesN` key left-aligned in the 32-byte word
(`keccak256(abi.encode(key, slot))`); the compiled code loads a `bytesN`
parameter as that word, and the executable plane keys the entry by the same
word (`StorageKey.toWord`). `test/BytesNMappingKeySmoke.t.sol` checks the
compiled slots against Solidity's.
-/

namespace Contracts.Smoke

open Contracts
open Verity hiding pure bind
open Verity.EVM.Uint256

verity_contract BytesNMappingKeySmoke where
  storage
    valueOf : Bytes4 → Uint256 := slot 3
    entries : MappingStruct(Bytes4,[
      target @word 0,
      position @word 1
    ]) := slot 4
    nested : Bytes4 → Address → Uint256 := slot 5

  function setValue (key : Bytes4, value : Uint256) : Unit := do
    setMappingN valueOf [key] value

  function getValue (key : Bytes4) : Uint256 := do
    let value ← getMappingN valueOf [key]
    return value

  function setEntry (key : Bytes4, target : Uint256, position : Uint256) : Unit := do
    setStructMember "entries" key "target" target
    setStructMember "entries" key "position" position

  function getEntry (key : Bytes4) : Tuple [Uint256, Uint256] := do
    let (target, position) := structMembers "entries" key ["target", "position"]
    return (target, position)

  function setNested (key : Bytes4, owner : Address, value : Uint256) : Unit := do
    setMappingN nested [key, owner] value

  function getNested (key : Bytes4, owner : Address) : Uint256 := do
    let value ← getMappingN nested [key, owner]
    return value

/-! ## Slot layout agrees with Solidity (interpretation only) -/

/-- The key word is the `bytes4` value left-aligned in 32 bytes. -/
example : StorageKey.toWord (0x12345678 : Bytes4) =
    0x1234567800000000000000000000000000000000000000000000000000000000 := by
  rw [StorageKey.toWord_bytesN]
  simp only [Verity.Core.BytesN.toUint256, Verity.Core.Uint256.val_ofNat]
  decide

/-! Plain `rfl` would make the kernel unfold the left-aligning product
`key.val * 2 ^ 224` by unary recursion; rewriting with
`StorageKey.toWord_bytesN` keeps the key word symbolic. -/

theorem value_slot_is_solidity (key : Bytes4) :
    mappingChainSlot BytesNMappingKeySmoke.valueOf.slot [↑key] =
      Compiler.Proofs.solidityMappingSlot 3 (Verity.Core.BytesN.toUint256 key).val :=
  (mappingChainSlot_single 3 key).trans
    (congrArg (Compiler.Proofs.abstractMappingSlot 3) (StorageKey.toWord_bytesN key))

theorem entry_position_slot_is_solidity (key : Bytes4) :
    structSlot BytesNMappingKeySmoke.entries.slot (StorageKey.toWord key) 1 =
      (Compiler.Proofs.solidityMappingSlot 4 (Verity.Core.BytesN.toUint256 key).val + 1) %
        Compiler.Constants.evmModulus := by
  rw [StorageKey.toWord_bytesN]; rfl

/-! ## The executable plane -/

/-- `getValue` reads back what `setValue` wrote under the same key. -/
theorem getValue_after_setValue (s : ContractState) (key : Bytes4) (value : Uint256) :
    (Verity.bind (BytesNMappingKeySmoke.setValue key value)
      fun _ => BytesNMappingKeySmoke.getValue key).run s =
    ContractResult.success value
      (s.writeMapChain 3 [StorageKey.toWord key] 0 value) := by
  simp [BytesNMappingKeySmoke.setValue, BytesNMappingKeySmoke.getValue,
    BytesNMappingKeySmoke.valueOf, Contract.run, Bind.bind, Pure.pure,
    Verity.bind, Verity.pure, setMappingN, getMappingN]

/-- Distinct `bytes4` keys never alias. -/
theorem getValue_other_after_setValue (s : ContractState) (key key' : Bytes4)
    (value : Uint256) (h : key' ≠ key) :
    (Verity.bind (BytesNMappingKeySmoke.setValue key value)
      fun _ => BytesNMappingKeySmoke.getValue key').run s =
    ContractResult.success (s.readMapChain 3 [StorageKey.toWord key'] 0)
      (s.writeMapChain 3 [StorageKey.toWord key] 0 value) := by
  have hne : StorageKey.toWord key' ≠ StorageKey.toWord key :=
    fun heq => h (StorageKey.toWord_bytesN_injective (by decide) heq)
  simp [BytesNMappingKeySmoke.setValue, BytesNMappingKeySmoke.getValue,
    BytesNMappingKeySmoke.valueOf, Contract.run, Bind.bind, Pure.pure,
    Verity.bind, Verity.pure, setMappingN, getMappingN, -StorageKey.toWord_bytesN, hne]

/-! ## Kernel evaluation of the generated bodies -/

private def keyA : Bytes4 := 0x12345678
private def keyB : Bytes4 := 0x12345679
private def owner : Address := (0xabc : Address)

private def bytesNRun : ContractResult (Uint256 × Uint256 × Uint256 × Uint256 × Uint256) :=
  (do
    BytesNMappingKeySmoke.setValue keyA 1000
    BytesNMappingKeySmoke.setEntry keyA 7 3
    BytesNMappingKeySmoke.setNested keyB owner 42
    let a ← BytesNMappingKeySmoke.getValue keyA
    let b ← BytesNMappingKeySmoke.getValue keyB
    let (t, p) ← BytesNMappingKeySmoke.getEntry keyA
    let n ← BytesNMappingKeySmoke.getNested keyB owner
    return (a, b, t + p, n, (← BytesNMappingKeySmoke.getNested keyA owner)) :
      Contract _).run Verity.defaultState

example : bytesNRun.getValue? =
    some ((1000 : Uint256), (0 : Uint256), (10 : Uint256), (42 : Uint256), (0 : Uint256)) := by
  decide +kernel

end Contracts.Smoke

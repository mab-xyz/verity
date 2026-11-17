import Contracts.Smoke.MemoryHashSmoke
import Contracts.ProofKit

/-!
`Contracts.ProofKit` on `MemoryHashSmoke`: `hashBytes data` returns `keccak256(data)` for every
`data` (proved, where `MemoryHashSmoke` checks one input with `native_decide`), and `hashWords a b`
returns `keccak256(abi.encode(a, b))`.
-/

namespace Contracts.Smoke.ProofKitSmoke

open Verity Contracts Contracts.ProofKit

theorem hashBytes_is_keccak (data : ByteArray) (s : ContractState)
    (hsize : data.size + 32 < 2 ^ 256) :
    ∃ s', MemoryHashSmoke.hashBytes data s =
      .success (Verity.Core.Uint256.ofNat (keccakBytes data.data.toList)) s' := by
  unfold MemoryHashSmoke.hashBytes
  obtain ⟨u, s1, h1⟩ : ∃ u s1, Contracts.copyBytes data 0 s = .success u s1 := ⟨_, _, copyBytes_run _ _ _⟩
  rw [bind_step h1, bind_step (keccak256Live_eq _ _ _),
    keccak_after_copyBytes h1 (by simpa using hsize)]
  exact ⟨_, rfl⟩

theorem hashWords_is_keccak (a b : Uint256) (s : ContractState) :
    ∃ s', MemoryHashSmoke.hashWords a b s =
      .success (Verity.Core.Uint256.ofNat (keccakBytes (toBE 32 a.val ++ toBE 32 b.val))) s' := by
  unfold MemoryHashSmoke.hashWords
  obtain ⟨u0, s1, h0⟩ : ∃ u s1, Contracts.mstore 0 a s = .success u s1 := ⟨_, _, mstore_eq _ _ _⟩
  obtain ⟨u1, s2, h1⟩ : ∃ u s2, Contracts.mstore 32 b s1 = .success u s2 := ⟨_, _, mstore_eq _ _ _⟩
  rw [bind_step h0, bind_step h1, bind_step (keccak256Live_eq _ _ _)]
  have hk : Compiler.Keccak.MemorySlice.keccak (fun a => (s2.memory a).val) 0 64 =
      keccakBytes (toBE 32 a.val ++ toBE 32 b.val) := by
    apply keccak_eq_keccakBytes
    rw [mstore_ok h1, mstore_ok h0, bytesBE_of_words _ _ _ [a.val, b.val] rfl]
    · simp
    · intro i hi
      simp at hi
      have h32 : (32 : Uint256).val = 32 := rfl
      have h0' : (0 : Uint256).val = 0 := rfl
      interval_cases i <;> simp [h32, h0']
  exact ⟨s2, by rw [← hk]; rfl⟩

end Contracts.Smoke.ProofKitSmoke

import Contracts.Common

namespace Contracts.Smoke

open Verity hiding pure bind
open Verity.EVM.Uint256

-- `block.coinbase` read through `blockCoinbase`, and a builder tip sent to it with the
-- generic ETH-aware call module (`test/CoinbaseSmoke.t.sol`).
verity_contract CoinbaseSmoke where
  storage

  function who () : Address := do
    let beneficiary ← blockCoinbase
    return beneficiary

  function reentrancy_trusted payCoinbase (amount : Uint256) : Unit := do
    let beneficiary ← blockCoinbase
    ecmDo Compiler.Modules.Calls.callWithValueModule [addressToWord beneficiary, amount, 0, 0]

/-- The executable semantics of `who` returns the state's `blockCoinbase`. -/
theorem who_returns_blockCoinbase (state : Verity.ContractState) :
    (CoinbaseSmoke.who.run state).getValue? = some state.blockCoinbase := by
  rfl

example :
    (CoinbaseSmoke.who.run { Verity.defaultState with blockCoinbase := 0xC0FFEE }).getValue? =
      some 0xC0FFEE := by
  decide

/-- The macro lowers `blockCoinbase` to the compilation-model leaf `Expr.blockCoinbase`. -/
example :
    CoinbaseSmoke.who_modelBody =
      [Compiler.CompilationModel.Stmt.letVar "beneficiary"
          Compiler.CompilationModel.Expr.blockCoinbase,
        Compiler.CompilationModel.Stmt.return
          (Compiler.CompilationModel.Expr.localVar "beneficiary")] := by
  rfl

end Contracts.Smoke

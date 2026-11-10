<p align="center">
  <img src="verity.svg" alt="Verity" width="200" />
</p>

<h1 align="center">Verity</h1>

A formally verified smart contract compiler for Ethereum, written in
[Lean 4](https://lean-lang.org/). Write a contract in an embedded DSL (or
import it from Solidity), prove properties about it, and compile it to EVM
bytecode through a compiler whose layers are themselves proved.
Documentation: [veritylang.com](https://veritylang.com) · Paper:
[verity.pdf](https://lfglabs.dev/papers/verity.pdf) · MIT licensed.

## About this fork (`mab-xyz/verity`, branch `ours`)

`ours` is upstream [`lfglabs-dev/verity`](https://github.com/lfglabs-dev/verity)
`main` plus the fixes below. Each fix is on its own `fix/*` branch, merged here
with `--no-ff`, and sent upstream as a separate PR, one at a time. All of them
come from compiling every example in `Contracts/` to Yul and running the
compiled bytecode on a local anvil chain.

| Fix | Branch | Upstream | What it changes |
|---|---|---|---|
| Yul builtin identifiers | `fix/reject-yul-builtin-identifiers` | [lfglabs-dev/verity#2669](https://github.com/lfglabs-dev/verity/pull/2669) | Parameters and locals named after Yul keywords or EVM builtins (`gas`, `balance`, …) are rejected at compile time. Before, they produced Yul that solc refused. Unblocks the three `ProxyUpgradeability*Smoke` contracts, `ModifiesSmoke` and `EffectCompositionSmoke`. |
| Discard binders | `fix/discard-binders-outside-reserved-prefix` | queued (after #2669) | `let _ ← call` and `let (_, x) ← …` no longer generate `__`-prefixed binders, which the compiler's own reserved-prefix check rejected. Also repairs the outdated `TypedInterfaceCallSmoke` / `ExternalCallInBodySmoke` fixtures. |
| `mulDiv512Up` overflow | `fix/muldiv512-up-overflow-revert` | queued | The ceil helper reverts when the rounded-up quotient is `2^256`, as `evalMulDiv512Up` specifies. Before, it silently returned `0`. Regression test: `test/MulDiv512Smoke.t.sol`. |
| Linker | `fix/linker-creation-code-and-one-line-functions` | queued | One-line library functions no longer swallow the next definition. Library functions called from creation code are linked into it too. |
| Checked-arithmetic panic ABI | `fix/signed-checked-arithmetic-panic-abi` | queued | Signed (`Int256`) and narrow checked arithmetic revert with Solidity's `Panic(uint256)` (0x11 overflow, 0x12 division by zero), as unsigned arithmetic already did, instead of `Error("Panic(0x11): …")`. Regression test: `test/Int256CheckedSmoke.t.sol`, which checks exact parity with Solidity. |
| `selfCall` ABI encoding | `fix/selfcall-abi-encoding` | queued | `tryCall (selfCall f(args))` ABI-encodes `f`'s selector and arguments and CALLs this contract with all available gas. Before, it was a 0-gas CALL with empty calldata, so the catch branch always ran. Regression test: `test/TryCatchSmoke.t.sol`, which checks the values the Lean file proves. |
| `return ()` in `Unit` functions | `fix/unit-return-early-exit` | queued | `return ()` exits a `Unit` function early (EVM `stop()` externally, `leave` in an internal helper) instead of being rejected as an empty tuple return. Regression test: `test/UnitReturnSmoke.t.sol`. |
| Whole tuple/struct parameters | `fix/reject-whole-tuple-param-value` | queued | A tuple or struct parameter is never emitted as a bare Yul name: as a value it is rejected with a hint to use its components, and passed whole to a typed interface call it is ABI-encoded as its words inline. Unblocks `TupleSmoke`, `Uint8Smoke`, `OverloadSignatureEncodingSmoke`, `ReturnCallTupleParamSmoke`, `ReturnCallNestedStructParamSmoke`. |
| ECM result variables | `fix/ecm-result-vars-bound` | queued | The compiler rejects an external call module whose declared result variables are not bound by a top-level `let` in its Yul. This found and fixed `Hashing.abiEncodeStaticArray`, whose result was scoped inside a block and never compiled through solc. |
| `lake build` builds everything | `fix/lake-default-builds-every-module` | queued | A bare `lake build` used to build only `Verity`, never `Contracts/` or `Compiler/`, and 39 modules were built by nothing at all. All libraries are now default targets, and `make check` runs `scripts/check_lake_default_coverage.py`, which fails if any module falls outside what `lake build` builds. |
| Struct returns | `fix/struct-return-values` | queued | A function returning a struct (or a static tuple or fixed array) compiles: the flattened words are its ABI encoding, and the internal copy gets one return slot per word. Before, every struct return was rejected. Regression test: `test/NamedStructReturnSmoke.t.sol`, byte-identical to Solidity. |
| Composite interface returns | `fix/interface-composite-return-local` | queued (after struct returns) | `let r ← pool.f` where `f` returns a tuple, struct or fixed array binds every ABI word; before, only the first word was decoded. `return r` re-encodes all of them. Regression test: `test/InterfaceCompositeReturnSmoke.t.sol`. |
| `ecmDo` dynamic arguments | `fix/ecmdo-dynamic-args` | queued | `ecmDo` passes a bytes/string/array parameter as `data_offset, length`, like `ecmCall`, `ecmBind` and the Lean model; before, it passed one word. Regression test: `test/DirectDynamicECMArgSmoke.t.sol`. |

Related upstream PR, not yet part of this branch:
[lfglabs-dev/EVMYulLean#12](https://github.com/lfglabs-dev/EVMYulLean/pull/12)
makes an out-of-bounds Yul `RETURNDATACOPY` halt, as on the EVM. Branch
`fix/evmyul-returndatacopy-halt` pins it and updates the proofs (full build
green, no new axioms), but is not merged: `generate_evmyullean_fork_audit.py
--check` rejects any semantic-change commit in the EvmYul fork.

Known issues not yet fixed here:
- Revert payloads are not observable in the proof semantics, so a wrong revert ABI (as in #12) cannot break a theorem. A plan exists; no code yet.
- Low-level `call` / `staticcall` / `delegatecall` have a placeholder meaning in the EDSL (the sum of their arguments) and none in the source semantics, so theorems about their result say nothing about the chain. A plan exists; no code yet.
- `mulmod` is missing from the static gas model.
- Some example specs still do not compile, and CI does not compile every example to Yul or run solc on it.

Sync with upstream:
`git fetch https://github.com/lfglabs-dev/verity main && git merge FETCH_HEAD`,
then re-run the gates in `AGENTS.md`.

## Guarantees

- **Layer 1** (DSL → `CompilationModel`): per-contract bridge theorems.
- **Layer 2** (`CompilationModel` → IR): a generic whole-contract theorem covers the supported fragment with zero axioms.
- **Layer 3** (IR → Yul): every statement form is proved equivalent. The dispatch bridge is an explicit theorem hypothesis, not an axiom.

The compiler proof stack carries 0 axioms and no `sorry`. Yul → bytecode is
done by pinned `solc` and is trusted. Verification is scoped: the proved
fragment and everything trusted are listed in the trust documents below.

## Quick start

```sh
lake build     # check every proof
make check     # repository checks run in CI (no Lean build)
make test-foundry
```

## Where things are

| Path | Contents |
| --- | --- |
| `Verity/` | The DSL (`verity_contract`), its semantics and proof library |
| `Compiler/` | The compiler and its correctness proofs |
| `Compiler/SolidityImport/` | Solidity → `CompilationModel` importer ([docs](docs/SOLIDITY_IMPORT.md)) |
| `Contracts/` | Example and smoke contracts with their proofs |
| `docs/` | Trust boundary, axioms, verification status, design notes |
| `scripts/`, `test/`, `artifacts/` | CI checks, Foundry tests, generated reports |

## What to review

1. [docs/TRUST_ASSUMPTIONS.md](docs/TRUST_ASSUMPTIONS.md): what is proved and what is trusted.
2. [docs/AXIOMS.md](docs/AXIOMS.md): every axiom, with its justification.
3. [docs/VERIFICATION_STATUS.md](docs/VERIFICATION_STATUS.md): theorem and test inventory, regenerated by CI.
4. [docs/SOLIDITY_IMPORT.md](docs/SOLIDITY_IMPORT.md): the Solidity importer and its differential validation.

Contributions: see [CONTRIBUTING.md](CONTRIBUTING.md).

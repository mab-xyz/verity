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
with `--no-ff`, and sent upstream as a separate PR. The maintainer also opens
mirror PRs of these branches upstream (same head commit), so their CI runs. All of them
come from compiling every example in `Contracts/` to Yul and running the
compiled bytecode on a local anvil chain.

| Fix | Branch | Upstream | What it changes |
|---|---|---|---|
| Yul builtin identifiers | `fix/reject-yul-builtin-identifiers` | merged as [lfglabs-dev/verity#2674](https://github.com/lfglabs-dev/verity/pull/2674) (mirror of #2669) | Parameters and locals named after Yul keywords or EVM builtins (`gas`, `balance`, …) are rejected at compile time. Before, they produced Yul that solc refused. Unblocks the three `ProxyUpgradeability*Smoke` contracts, `ModifiesSmoke` and `EffectCompositionSmoke`. |
| Discard binders | `fix/discard-binders-outside-reserved-prefix` | [lfglabs-dev/verity#2695](https://github.com/lfglabs-dev/verity/pull/2695) | `let _ ← call` and `let (_, x) ← …` no longer generate `__`-prefixed binders, which the compiler's own reserved-prefix check rejected. Also repairs the outdated `TypedInterfaceCallSmoke` / `ExternalCallInBodySmoke` fixtures. |
| `mulDiv512Up` overflow | `fix/muldiv512-up-overflow-revert` | mirrored by the maintainer as [lfglabs-dev/verity#2744](https://github.com/lfglabs-dev/verity/pull/2744) (open) | The ceil helper reverts when the rounded-up quotient is `2^256`, as `evalMulDiv512Up` specifies. Before, it silently returned `0`. Regression test: `test/MulDiv512Smoke.t.sol`. |
| Linker | `fix/linker-creation-code-and-one-line-functions` | mirrored by the maintainer as [lfglabs-dev/verity#2742](https://github.com/lfglabs-dev/verity/pull/2742) (open) | One-line library functions no longer swallow the next definition. Library functions called from creation code are linked into it too. |
| Checked-arithmetic panic ABI | `fix/signed-checked-arithmetic-panic-abi` | mirrored by the maintainer as [lfglabs-dev/verity#2747](https://github.com/lfglabs-dev/verity/pull/2747) (open) | Signed (`Int256`) and narrow checked arithmetic revert with Solidity's `Panic(uint256)` (0x11 overflow, 0x12 division by zero), as unsigned arithmetic already did, instead of `Error("Panic(0x11): …")`. Regression test: `test/Int256CheckedSmoke.t.sol`, which checks exact parity with Solidity. |
| `selfCall` ABI encoding | `fix/selfcall-abi-encoding` | mirrored by the maintainer as [lfglabs-dev/verity#2748](https://github.com/lfglabs-dev/verity/pull/2748) (open) | `tryCall (selfCall f(args))` ABI-encodes `f`'s selector and arguments and CALLs this contract with all available gas. Before, it was a 0-gas CALL with empty calldata, so the catch branch always ran. Regression test: `test/TryCatchSmoke.t.sol`, which checks the values the Lean file proves. |
| `return ()` in `Unit` functions | `fix/unit-return-early-exit` | mirrored by the maintainer as [lfglabs-dev/verity#2746](https://github.com/lfglabs-dev/verity/pull/2746) (open) | `return ()` exits a `Unit` function early (EVM `stop()` externally, `leave` in an internal helper) instead of being rejected as an empty tuple return. Regression test: `test/UnitReturnSmoke.t.sol`. |
| Whole tuple/struct parameters | `fix/reject-whole-tuple-param-value` | queued | A tuple or struct parameter is never emitted as a bare Yul name: as a value it is rejected with a hint to use its components, and passed whole to a typed interface call it is ABI-encoded as its words inline. Unblocks `TupleSmoke`, `Uint8Smoke`, `OverloadSignatureEncodingSmoke`, `ReturnCallTupleParamSmoke`, `ReturnCallNestedStructParamSmoke`. |
| ECM result variables | `fix/ecm-result-vars-bound` | mirrored by the maintainer as [lfglabs-dev/verity#2741](https://github.com/lfglabs-dev/verity/pull/2741) (open) | The compiler rejects an external call module whose declared result variables are not bound by a top-level `let` in its Yul. This found and fixed `Hashing.abiEncodeStaticArray`, whose result was scoped inside a block and never compiled through solc. |
| `lake build` builds everything | `fix/lake-default-builds-every-module` | mirrored by the maintainer as [lfglabs-dev/verity#2754](https://github.com/lfglabs-dev/verity/pull/2754) (open) | A bare `lake build` used to build only `Verity`, never `Contracts/` or `Compiler/`, and 39 modules were built by nothing at all. All libraries are now default targets, and `make check` runs `scripts/check_lake_default_coverage.py`, which fails if any module falls outside what `lake build` builds. |
| Struct returns | `fix/struct-return-values` | queued | A function returning a struct (or a static tuple or fixed array) compiles: the flattened words are its ABI encoding, and the internal copy gets one return slot per word. Before, every struct return was rejected. Regression test: `test/NamedStructReturnSmoke.t.sol`, byte-identical to Solidity. |
| Composite interface returns | `fix/interface-composite-return-local` | queued (after struct returns) | `let r ← pool.f` where `f` returns a tuple, struct or fixed array binds every ABI word; before, only the first word was decoded. `return r` re-encodes all of them. Regression test: `test/InterfaceCompositeReturnSmoke.t.sol`. |
| `ecmDo` dynamic arguments | `fix/ecmdo-dynamic-args` | mirrored by the maintainer as [lfglabs-dev/verity#2749](https://github.com/lfglabs-dev/verity/pull/2749) (open) | `ecmDo` passes a bytes/string/array parameter as `data_offset, length`, like `ecmCall`, `ecmBind` and the Lean model; before, it passed one word. Regression test: `test/DirectDynamicECMArgSmoke.t.sol`. |
| `RETURNDATACOPY` past the buffer halts | `fix/evmyul-returndatacopy-halt` | mirrored by the maintainer as [lfglabs-dev/verity#2753](https://github.com/lfglabs-dev/verity/pull/2753) (open) | EvmYul's Yul semantics zero-padded an out-of-bounds `RETURNDATACOPY`, so proofs admitted runs a real EVM aborts (EIP-211). The pin moves to the merged fix (upstream `eb0b6dd`); the affected proofs carry an in-bounds hypothesis. The fork audit now admits a semantic EvmYul change only as an EVM-conformance fix with an EIP and tests. |
| Whole fixed-array / struct values | `fix/whole-composite-values` | mirrored by the maintainer as [lfglabs-dev/verity#2743](https://github.com/lfglabs-dev/verity/pull/2743) (open) | `return arr` for a fixed-array or struct parameter, and `let s ← helper …` for a helper returning one, keep every ABI word; before, they produced Yul solc rejects (one word returned, or one variable bound to several values). `let x := arr` is rejected like the tuple case. Regression test: `test/WholeCompositeValueSmoke.t.sol`, byte-identical to Solidity. |
| Real memory, hashing and CREATE2 in the EDSL | `fix/edsl-memory-hash-semantics` | mirrored by the maintainer as [lfglabs-dev/verity#2751](https://github.com/lfglabs-dev/verity/pull/2751) (open) | In the Lean semantics `keccak256` was `offset + size`, `mload` returned its offset, `calldatacopy` did nothing and CREATE2 returned an oracle word, so theorems about hashing or deployment said nothing about the chain. They now hash and copy real memory (the hash is proved equal to the proof IR's) and CREATE2 returns the EIP-1014 address. New `copyBytes`/`bytesLength` for `bytes` parameters. Checked against Solidity's `keccak256`, the EIP-1014 vector and `vm.computeCreate2Address`. |
| Free memory above stack-spilled locals | `fix/spill-area-above-free-pointer` | mirrored by the maintainer as [lfglabs-dev/verity#2745](https://github.com/lfglabs-dev/verity/pull/2745) (open) | Functions with more than 12 live locals spill them to fixed memory slots from 0x1000, but the free-memory pointer still started at 0x80, so copying a `bytes` argument longer than ~3.9 KB (e.g. pool creation code for CREATE2) overwrote spilled locals. A spilling code section now starts its free memory above its highest spill slot. Checked with a 5000-byte payload on the bytecode (fails before the fix). |
| Loops iterate in the EDSL | `fix/foreach-executable-iterates` | mirrored by the maintainer as [lfglabs-dev/verity#2750](https://github.com/lfglabs-dev/verity/pull/2750) (open) | In the Lean semantics every `forEach`/`forEachSetBit` ran its body once with index 0, while the bytecode loops `n` times, so theorems about functions with loops were about another program (a Babylonian `isqrt` reverted for every n > 3, making any "after the first mint" theorem of an AMM pool vacuous). Loops now run once per index the compiled loop visits, in the same order, threading reassigned `let mut` locals. Theorems `isqrt 1000000 = 1000` etc. fail with the old semantics; the bytecode gives the same values (Foundry, fuzzed). |
| View calls answered by the adversary | `fix/view-call-helpers-adversary` | mirrored by the maintainer as [lfglabs-dev/verity#2752](https://github.com/lfglabs-dev/verity/pull/2752) (open) | A public executable passed the adversary only to helpers that open a reentrancy window; a function or helper whose external calls are view-only (token `balanceOf`, a factory lookup, an ECM) answered them with a fixed stub, so a theorem about a public entry point (e.g. an AMM `mint`) held only for the stub's answers, with nothing in its statement saying so. Every executable that consults the adversary, directly or through a helper, now takes the call context; linked hops are unchanged. Test: an entry point that stores a balance read through a view helper stores the adversary's answer (it stored the stub word before). |
| Bare `lake build` relinks the executables | `fix/lake-default-builds-compiler` | queued | `verity-compiler`, `difftest-interpreter`, `compiler-main-test` and `gas-report`, which the Makefile, scripts and CI run from `.lake/build/bin/`, are default targets. Before, a bare `lake build` rebuilt the `.olean`s but left these binaries stale, and a stale `verity-compiler` segfaulted on every `--module` once a `ContractState` field was added (exit 139 on `Contracts.Counter`). `scripts/check_lake_default_coverage.py` (in `make check`) fails when such an executable is not a default target. |

## Features (`feat/*`)

Features this fork adds on top of upstream, for ports of contracts to Verity (DefilangFirewall, TinyDiamond, ...). Each is on its own `feat/*` branch, merged here with `--no-ff`; not sent upstream yet.

| Feature | Branch | What it adds |
|---|---|---|
| `bytes` in typed-interface calls | `feat/interface-bytes-calls` | A typed-interface method may take `Bytes` arguments and return `Tuple [Bool, Bytes]` (part of upstream #1982). An argument is a direct `Bytes` parameter, `emptyBytes`, or `abiEncodeCall sel [items]` (items: words, `Bytes` parameters or `emptyBytes`; `sel` a literal or a literal `Uint256`/`Bytes32` constant), encoded with Solidity's head/tail layout. The returned bytes are checked as solc does (malformed → `revert(0,0)`) and read with `bytesLength`, `bytesWord r k` (literal `k`) and `revertBytes r` (bubbles them byte-exactly). New module `Calls.abiCallModule`, axiom `external_call_abi_interface` like every typed call. Executable plane: one journal entry per call whose `calldata` is `abiCallBytes sel args` (the ABI bytes, selector included; theorems `abiCallSite_journal`, `externalCallAbiTo_journal`, `externalCallAbiBoolBytesTo_journal`); the adversary answers the return. Limits: no single `Bytes` return; the executable `revertBytes` reverts with the fixed message `"revertBytes"`. Regression test: `test/InterfaceBytesCallSmoke.t.sol` (calldata compared with Solidity's `abi.encode*`; fails on a mutated padding or tail offset in the Yul). |
| `block.coinbase` | `feat/coinbase` | `blockCoinbase : Address` in contract code, compiled to Yul `coinbase()`, threaded like `txOrigin` through `ContractState`, `Expr.blockCoinbase`, the source and IR semantics and the native EVMYulLean bridge (no new axioms; `TxContextNormalized` now also requires `blockCoinbase < 2^160`). Regression test: `test/CoinbaseSmoke.t.sol` (fails when `coinbase()` is replaced by `origin()` in the Yul). |
| `fallback payable` | `feat/fallback-payable` | `fallback payable := …` in a `verity_contract`, Solidity's `fallback() external payable` (EIP-1967/EIP-2535 proxies forward value): the fallback compiles without the `callvalue` guard. Plain `fallback` keeps it. Regression test: `test/PayableFallbackSmoke.t.sol` (fails when the guard is put back into the payable fallback's Yul). From mab-xyz/verity#5. |
| `copyBytes`/`bytesLength` on a struct member | `feat/copybytes-struct-member` | `copyBytes s.field dest` and `bytesLength s.field` accept a `Bytes` member of a dynamically encoded struct parameter (read through the checked dynamic-member helpers, like `arrayLength s.field`), so it can be hashed or forwarded. Regression test: `test/StructBytesMemberCopySmoke.t.sol` (length, first word and keccak of the copied region against Solidity; two Yul mutants, wrong member word and a copy cut to 32 bytes, are caught). From mab-xyz/verity#4. |

The end-to-end proof that `abiCallModule`'s Yul sends the bytes its journal entry records, retiring its axiom, is planned in `plan-abi-call-yul-proof.md`.

EvmYul is pinned to upstream `lfglabs-dev/EVMYulLean@eb0b6dd`, the merge of
[lfglabs-dev/EVMYulLean#12](https://github.com/lfglabs-dev/EVMYulLean/pull/12).

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

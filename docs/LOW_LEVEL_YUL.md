# Low-Level Yul Surface

Verity keeps two low-level escape routes separate:

- First-class typed primitives, such as `Stmt.mstore` and
  `Stmt.calldatacopy`, are kept when they have stable Verity semantics, trust
  reporting, and proof value.
- One-off statements that only expose a single Yul instruction should be helper
  constructors returning `UnsafeYulFragment`, used through `Stmt.unsafeYul`.

Raw Yul is the explicit escape hatch. An `UnsafeYulFragment` carries the EVMYul
AST payload, low-level mechanics, local obligations, scope effects, and
termination metadata at the same boundary. This keeps ad-hoc assembly visible
in trust reports without making every Yul instruction look like a modeled
Verity statement.

When lowered, each fragment is surrounded by comment-only provenance markers.
The checked-arithmetic peephole treats that marked region as opaque, so raw Yul
cannot be mistaken for compiler-generated checked arithmetic or have repeated
operand evaluation changed by the rewrite.

For example, raw memory reverts now use the fragment helper:

```lean
Stmt.unsafeYul
  (UnsafeYulFragment.rawRevert
    (Compiler.Yul.YulExpr.ident "offset")
    (Compiler.Yul.YulExpr.ident "size")
    { name := "raw_revert_memory_slice_refinement"
      obligation := "Caller-provided raw revert memory slice must refine the intended failure payload."
      proofStatus := .assumed })
```

Raw memory reverts should use `UnsafeYulFragment.rawRevert`. Typed primitives such as
`mstore`, `calldatacopy`, and similar common operations should remain
first-class only when Verity commits to their semantics and they are useful in
proofs or audits.

## Returndata Forwarding

A proxy fallback (EIP-1967, EIP-2535) ends with the callee's returndata,
verbatim, as its own revert or success payload. Two first-class statements
cover both exits:

| `verity_contract` | `Stmt` | Yul |
|---|---|---|
| `revertReturndata` | `Stmt.revertReturndata` | `returndatacopy(0, 0, returndatasize())`, `revert(0, returndatasize())` |
| `returnReturndata` | `Stmt.returnReturndata` | `returndatacopy(0, 0, returndatasize())`, `return(0, returndatasize())` |

```lean
function reentrancy_trusted forward (callee : Address, flag : Uint256, length : Uint256)
  local_obligations [returndata_forwarding := assumed "..."]
  : Unit := do
  mstore 0 flag
  mstore 32 length
  let ok := call ALL_GAS (addressToWord callee) 0 0 64 0 0
  if ok == 0 then
    revertReturndata
  else
    returnReturndata
```

(`Contracts/Smoke/ReturndataForwardSmoke.lean`; `test/ReturndataForwardSmoke.t.sol`
checks the forwarded bytes on the compiled bytecode.)

Both are low-level mechanics: outside an `unsafe` block the function needs a
`local_obligations` entry, trust reports list them, and
`--deny-low-level-mechanics` rejects them. A `nonreentrant` lock is released
before the `return` of `returnReturndata`, as before any other successful exit.

`returnReturndata` ends the whole call, so `verity_contract` accepts it only in
tail position of a `Unit` function body: the last statement of its path,
directly or under `if`/`else`, with nothing after the enclosing statements up to
the end of the function. It is rejected anywhere else (after another
statement, inside a loop, in a constructor or modifier), in non-`Unit`
functions, and in internal functions; a function that uses it gets no
internal-helper form, so calling it from another function is rejected.
Modifiers are precondition-only (`docs/MODIFIERS_AND_INHERITANCE.md`): their
statements are inserted before the body and none run after it, so a function
`with` a modifier keeps the tail guarantee; a `returnReturndata` inside a
modifier is rejected.

In the executable EDSL both statements are no-ops (`Contracts.revertReturndata`,
`Contracts.returnReturndata`): the `Contract` monad has no frame-ending success
with a payload. Because `returnReturndata` is in tail position, nothing runs
after it in the EDSL either, so the executable post-state equals the
bytecode's on every path; only the returned bytes are not modeled (as the
revert payload of `revertReturndata` is not). The proof interpreters prove
`revertReturndata` and do not model `returnReturndata`; see
`docs/INTERPRETER_FEATURE_MATRIX.md`.

## Yul Temporary Slot Reuse and Scratch-Memory Spilling (`--max-stack-locals`)

The spill pass is a **trusted, tested-only** component (see
[TRUST_ASSUMPTIONS.md](TRUST_ASSUMPTIONS.md#12-yul-stack-spill-pass-tempreuse)): no theorem
states that its output means the same as its input. It exists to keep blocks with many
`let` bindings within the EVM's 16-slot `DUP`/`SWAP` reach under `solc --strict-assembly`.
The CLI (`verity-compiler`, `writeContract`) and the Solidity import model drivers
(`Compiler.emitYulSpilled`) use separate entry points in `Compiler/Yul/TempReuse.lean`:

- **Static memory gate per code section (`reuseAndSpillTempsStaticObject`, used by the CLI and on
  `deployCode` in `emitYulSpilled`)**: a section is rewritten only if every memory access in it,
  functions included, has a literal address and a literal length ending at or below `0x1000`
  (`4096`); it does not use `msize`; and every call is a memory-free builtin (including
  `loadimmutable` and `clz`) or a function defined in the same section
  (`sectionMemoryStaticBelow`). An unknown builtin, a computed address or length (free-pointer
  allocations, ABI encodings written from address 0 with a runtime size, `calldatacopy` of a
  dynamic argument), and a call to a linked library function all fail the gate. A section that
  fails the gate is emitted **unchanged** (no dead-variable reuse either), and the free-memory
  pointer is never moved.
- **Per-dispatch-case gate (`reuseAndSpillTempsDispatchedObject`, used on `runtimeCode` by
  `Compiler.emitYulSpilled`)**: when `runtimeCode` does not pass `sectionMemoryStaticBelow` as a
  whole, it is rewritten per case only if it matches the exact
  `[funcDefs..., mstore(64, 128), buildSwitch]` shape emitted by `CodegenCommon.runtimeCode`,
  every helper `funcDef` stays statically within `[0, 64)`, and `noSelectorDefault` does not
  assign `__has_selector`. Each selector case and each whole default (`fallback`/`receive`) case
  must unconditionally terminate (`stmtsAlwaysTerminate`) and pass either
  `stmtsMemoryStaticBelow 0x1000` (leaving `mem[64]` untouched) or `caseMemoryFreePtrSafe 128`
  (prepending `mstore(64, highWater)` at case entry only, never rewriting any `mstore(64, ...)`
  in the case body, bounding static accesses to `[0, 128)` so moving the heap from `128` to
  `highWater` cannot change static-vs-heap aliasing, requiring static reads to be disjoint from
  `[64, 96)` unless all 32 bytes `[64, 96)` were overwritten on every path, restricting
  free-pointer locals to checked allocations `next ≤ 2^64 - 1 ∧ next ≥ base` outside loops whose
  cumulative ceiling from `2^32` stays `≤ 2^64 - 1` and heap addresses `p + offset` with `< 2^64`
  addend and length, rejecting `break`/`continue`/`leave` non-call statements, and forbidding
  pointer values in expressions). Any other case or
  section shape is left **unchanged**; if it remains too deep, `solc` rejects it with
  `StackTooDeep` instead of aliasing runtime memory. Gas is not preserved: a spilling section or
  case expands memory to at least its highest spill word (about 4.1 KB, or higher when heap
  allocations start at `highWater`) and adds `mstore`/`mload`s, so `gas()` values and out-of-gas
  margins differ from the unspilled code.
- **Fast path**: inside a gated section, a block with at most `maxStackLocals` `let` bindings
  (default `12`) is returned unchanged. (`reuseBlockTemps_eq_self_of_le` in
  `Compiler/Proofs/YulGeneration/TempReuseSoundness.lean` states this for the single-block
  function `reuseBlockTemps`, which no compile path calls; it is not a theorem about the
  pass.)
- **Short-lived dead-slot reuse**: a `let` whose value is used within the next 2 `let`
  bindings may reuse a dead stack variable of the same block via `t := rhs`.
- **Scratch-memory spilling**: other `let`s past the stack budget spill to 32-byte words from
  `0x1000` via `mstore(slot, rhs)` / `mload(slot)`. A block's new words start above every word
  its (already rewritten) nested blocks use, so a nested block never overwrites a live word of
  an enclosing block; sibling blocks may share words.
- **Never spilled**: function bodies (and blocks inside them), because a word would be shared by
  a caller and its callee or by recursive frames; and `for` initialisers, whose variables stay
  live in the condition, body and post block. They only reuse dead stack variables, and a
  `for` initialiser never reuses its own variables, which are live after the initialiser.
- **Not proven**: slot selection, liveness (`findDeadStackVar`, `findFreeSpillSlot`), the
  nested-block rule, function and loop handling, and the gate itself are covered by
  `Compiler/MainTest.lean` cases, the Foundry tests `test/SpillStaticMemorySmoke.t.sol` (a
  section that spills on the CLI path), `test/SpillReturnArraySmoke.t.sol` and
  `test/SpillFreeMemorySmoke.t.sol` (sections that must not spill), and differential tests only.
  `reuseDeadLetStep_eval_eq` and `spillLetStep_eval_eq` are single-step lemmas over a toy
  word-keyed state; the `computedSpillBase` theorems in `Compiler/Codegen/Profile.lean` are
  about a spill base that no compile path uses.
- **CLI control**: Pass `--max-stack-locals <n>` (default: `12`) to adjust the
  per-block `let`-binding threshold before temporary reuse and spilling kick in.

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "forge-std/Test.sol";
import "./yul/YulTestBase.sol";

/// A `bytes4`-keyed mapping compiled by Verity stores its entries at Solidity's
/// slots: `keccak256(abi.encode(bytes4 key, slot))` (key left-aligned in the word).
contract BytesNMappingKeySmokeTest is Test, YulTestBase {
    address internal smoke;

    function setUp() public {
        smoke = deployCompiledVerityModule(
            "Contracts.Smoke.BytesNMappingKeySmoke", "BytesNMappingKeySmoke", _smokeYulDir()
        );
    }

    function _slot(bytes4 key, uint256 base) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, base));
    }

    function testFuzzValueSlotIsSolidity(bytes4 key, bytes4 other, uint256 value) public {
        vm.assume(key != other);
        (bool ok,) = smoke.call(abi.encodeWithSignature("setValue(bytes4,uint256)", key, value));
        assertTrue(ok);
        assertEq(uint256(vm.load(smoke, _slot(key, 3))), value);
        bytes memory out;
        (ok, out) = smoke.call(abi.encodeWithSignature("getValue(bytes4)", key));
        assertTrue(ok);
        assertEq(abi.decode(out, (uint256)), value);
        (ok, out) = smoke.call(abi.encodeWithSignature("getValue(bytes4)", other));
        assertTrue(ok);
        assertEq(abi.decode(out, (uint256)), 0);
    }

    function testFuzzStructSlotIsSolidity(bytes4 key, uint256 target, uint256 position) public {
        (bool ok,) =
            smoke.call(abi.encodeWithSignature("setEntry(bytes4,uint256,uint256)", key, target, position));
        assertTrue(ok);
        bytes32 base = _slot(key, 4);
        assertEq(uint256(vm.load(smoke, base)), target);
        assertEq(uint256(vm.load(smoke, bytes32(uint256(base) + 1))), position);
    }

    bytes4 internal constant SELECTOR = 0x12345678;

    function _value(bytes4 key) internal returns (uint256) {
        (bool ok, bytes memory out) = smoke.call(abi.encodeWithSignature("getValue(bytes4)", key));
        assertTrue(ok);
        return abi.decode(out, (uint256));
    }

    function _assertValueAt(bytes4 key, uint256 value) internal {
        assertEq(uint256(vm.load(smoke, _slot(key, 3))), value);
        assertEq(_value(key), value);
    }

    /// A `Bytes4` constant key is the left-aligned word, not the right-aligned literal.
    function testFuzzConstantKeyIsSolidity(uint256 value) public {
        vm.assume(value != 0);
        (bool ok,) = smoke.call(abi.encodeWithSignature("setValueAtSelector(uint256)", value));
        assertTrue(ok);
        _assertValueAt(SELECTOR, value);
        assertEq(uint256(vm.load(smoke, keccak256(abi.encode(uint256(0x12345678), uint256(3))))), 0);
    }

    function testFuzzStructConstantKeyIsSolidity(uint256 target) public {
        vm.assume(target != 0);
        (bool ok,) = smoke.call(abi.encodeWithSignature("setEntryAtSelector(uint256)", target));
        assertTrue(ok);
        assertEq(uint256(vm.load(smoke, _slot(SELECTOR, 4))), target);
        assertEq(uint256(vm.load(smoke, keccak256(abi.encode(uint256(0x12345678), uint256(4))))), 0);
    }

    function testFuzzLocalKeyIsSolidity(bytes4 key, uint256 value) public {
        (bool ok,) = smoke.call(abi.encodeWithSignature("setValueViaLocal(bytes4,uint256)", key, value));
        assertTrue(ok);
        _assertValueAt(key, value);
    }

    function testFuzzHelperResultKeyIsSolidity(uint256 value) public {
        (bool ok,) = smoke.call(abi.encodeWithSignature("setValueViaHelper(uint256)", value));
        assertTrue(ok);
        _assertValueAt(SELECTOR, value);
    }

    /// `narrowBytes 4 word` keeps the high four bytes, like Solidity's `bytes4(bytes32(word))`.
    function testFuzzNarrowedKeyIsSolidity(uint256 word, uint256 value) public {
        (bool ok,) = smoke.call(abi.encodeWithSignature("setValueNarrowed(uint256,uint256)", word, value));
        assertTrue(ok);
        _assertValueAt(bytes4(bytes32(word)), value);
    }

    function testFuzzNestedSlotIsSolidity(bytes4 key, address owner, uint256 value) public {
        (bool ok,) =
            smoke.call(abi.encodeWithSignature("setNested(bytes4,address,uint256)", key, owner, value));
        assertTrue(ok);
        bytes32 inner = keccak256(abi.encode(owner, _slot(key, 5)));
        assertEq(uint256(vm.load(smoke, inner)), value);
    }
}

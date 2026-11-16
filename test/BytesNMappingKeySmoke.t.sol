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

    function testFuzzNestedSlotIsSolidity(bytes4 key, address owner, uint256 value) public {
        (bool ok,) =
            smoke.call(abi.encodeWithSignature("setNested(bytes4,address,uint256)", key, owner, value));
        assertTrue(ok);
        bytes32 inner = keccak256(abi.encode(owner, _slot(key, 5)));
        assertEq(uint256(vm.load(smoke, inner)), value);
    }
}

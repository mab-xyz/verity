// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "./yul/YulTestBase.sol";

/**
 * @title PropertyBytesNMappingKeySmokeTest
 * @notice Auto-generated baseline property stubs from `verity_contract` declarations.
 * @dev Source: Contracts/Smoke/BytesNMappingKeySmoke.lean
 */
contract PropertyBytesNMappingKeySmokeTest is YulTestBase {
    address target;
    address alice = address(0x1111);

    function setUp() public {
        target = deployYul("BytesNMappingKeySmoke");
        require(target != address(0), "Deploy failed");
    }

    // Property 1: setValue has no unexpected revert
    function testAuto_SetValue_NoUnexpectedRevert() public {
        vm.prank(alice);
        (bool ok,) = target.call(abi.encodeWithSignature("setValue(bytes4,uint256)", bytes4(uint32(0x01)), uint256(1)));
        require(ok, "setValue reverted unexpectedly");
    }
    // Property 2: getValue reads the configured mapping value
    function testAuto_GetValue_ReadsConfiguredMapping() public {
        uint256 expected = uint256(1);
        vm.store(target, _mappingSlot(bytes32(bytes4(uint32(0x01))), 3), bytes32(uint256(expected)));
        vm.prank(alice);
        (bool ok, bytes memory ret) = target.call(abi.encodeWithSignature("getValue(bytes4)", bytes4(uint32(0x01))));
        require(ok, "getValue reverted unexpectedly");
        assertEq(ret.length, 32, "getValue ABI return length mismatch (expected 32 bytes)");
        uint256 actual = abi.decode(ret, (uint256));
        assertEq(actual, expected, "getValue should decode the configured mapping value");
    }
    // Property 3: setEntry has no unexpected revert
    function testAuto_SetEntry_NoUnexpectedRevert() public {
        vm.prank(alice);
        (bool ok,) = target.call(abi.encodeWithSignature("setEntry(bytes4,uint256,uint256)", bytes4(uint32(0x01)), uint256(1), uint256(1)));
        require(ok, "setEntry reverted unexpectedly");
    }
    // Property 4: TODO decode and assert `getEntry` result
    function testTODO_GetEntry_DecodeAndAssert() public {
        vm.prank(alice);
        (bool ok, bytes memory ret) = target.call(abi.encodeWithSignature("getEntry(bytes4)", bytes4(uint32(0x01))));
        require(ok, "getEntry reverted unexpectedly");
        require(ret.length >= 64, "getEntry ABI tuple return payload unexpectedly short");
        // TODO(#1011): decode `ret` and assert the concrete postcondition from Lean theorem.
        ret;
    }
    // Property 5: setNested has no unexpected revert
    function testAuto_SetNested_NoUnexpectedRevert() public {
        vm.prank(alice);
        (bool ok,) = target.call(abi.encodeWithSignature("setNested(bytes4,address,uint256)", bytes4(uint32(0x01)), alice, uint256(1)));
        require(ok, "setNested reverted unexpectedly");
    }
    // Property 6: getNested reads the configured mapping value
    function testAuto_GetNested_ReadsConfiguredMapping() public {
        uint256 expected = uint256(1);
        vm.store(target, keccak256(abi.encode(bytes32(uint256(uint160(alice))), _mappingSlot(bytes32(bytes4(uint32(0x01))), 5))), bytes32(uint256(expected)));
        vm.prank(alice);
        (bool ok, bytes memory ret) = target.call(abi.encodeWithSignature("getNested(bytes4,address)", bytes4(uint32(0x01)), alice));
        require(ok, "getNested reverted unexpectedly");
        assertEq(ret.length, 32, "getNested ABI return length mismatch (expected 32 bytes)");
        uint256 actual = abi.decode(ret, (uint256));
        assertEq(actual, expected, "getNested should decode the configured mapping value");
    }
    // Property 7: setValueAtSelector has no unexpected revert
    function testAuto_SetValueAtSelector_NoUnexpectedRevert() public {
        vm.prank(alice);
        (bool ok,) = target.call(abi.encodeWithSignature("setValueAtSelector(uint256)", uint256(1)));
        require(ok, "setValueAtSelector reverted unexpectedly");
    }
    // Property 8: setEntryAtSelector has no unexpected revert
    function testAuto_SetEntryAtSelector_NoUnexpectedRevert() public {
        vm.prank(alice);
        (bool ok,) = target.call(abi.encodeWithSignature("setEntryAtSelector(uint256)", uint256(1)));
        require(ok, "setEntryAtSelector reverted unexpectedly");
    }
    // Property 9: setValueViaLocal has no unexpected revert
    function testAuto_SetValueViaLocal_NoUnexpectedRevert() public {
        vm.prank(alice);
        (bool ok,) = target.call(abi.encodeWithSignature("setValueViaLocal(bytes4,uint256)", bytes4(uint32(0x01)), uint256(1)));
        require(ok, "setValueViaLocal reverted unexpectedly");
    }
    // Property 10: TODO decode and assert `selectorOf` result
    function testTODO_SelectorOf_DecodeAndAssert() public {
        vm.prank(alice);
        (bool ok, bytes memory ret) = target.call(abi.encodeWithSignature("selectorOf()"));
        require(ok, "selectorOf reverted unexpectedly");
        assertEq(ret.length, 32, "selectorOf ABI return length mismatch (expected 32 bytes)");
        // TODO(#1011): decode `ret` and assert the concrete postcondition from Lean theorem.
        ret;
    }
    // Property 11: setValueViaHelper has no unexpected revert
    function testAuto_SetValueViaHelper_NoUnexpectedRevert() public {
        vm.prank(alice);
        (bool ok,) = target.call(abi.encodeWithSignature("setValueViaHelper(uint256)", uint256(1)));
        require(ok, "setValueViaHelper reverted unexpectedly");
    }
    // Property 12: setValueNarrowed has no unexpected revert
    function testAuto_SetValueNarrowed_NoUnexpectedRevert() public {
        vm.prank(alice);
        (bool ok,) = target.call(abi.encodeWithSignature("setValueNarrowed(uint256,uint256)", uint256(1), uint256(1)));
        require(ok, "setValueNarrowed reverted unexpectedly");
    }
}

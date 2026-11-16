// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "forge-std/Test.sol";
import "./yul/YulTestBase.sol";

/// Callee whose returndata is chosen by the caller: calldata is the words `flag, length`;
/// the payload is `length` bytes `0xa1, 0xa2, ...`, returned when `flag == 0` and used as
/// revert data otherwise.
contract ReturndataForwardEcho {
    fallback() external {
        assembly {
            let flag := calldataload(0)
            let n := calldataload(32)
            for { let i := 0 } lt(i, n) { i := add(i, 1) } { mstore8(i, add(0xa1, i)) }
            if flag { revert(0, n) }
            return(0, n)
        }
    }
}

/// Solidity reference for the Verity `forward`: call, then forward the returndata verbatim.
contract ReturndataForwardReference {
    function forward(address callee, uint256 flag, uint256 length) external {
        assembly {
            mstore(0, flag)
            mstore(32, length)
            let ok := call(gas(), callee, 0, 0, 64, 0, 0)
            returndatacopy(0, 0, returndatasize())
            if iszero(ok) { revert(0, returndatasize()) }
            return(0, returndatasize())
        }
    }

    function forwardIfSuccess(address callee, uint256 flag, uint256 length) external {
        assembly {
            mstore(0, flag)
            mstore(32, length)
            if call(gas(), callee, 0, 0, 64, 0, 0) {
                returndatacopy(0, 0, returndatasize())
                return(0, returndatasize())
            }
        }
    }

    function forwardAlways(address callee, uint256 flag, uint256 length) external {
        assembly {
            mstore(0, flag)
            mstore(32, length)
            pop(call(gas(), callee, 0, 0, 64, 0, 0))
            returndatacopy(0, 0, returndatasize())
            return(0, returndatasize())
        }
    }
}

contract ReturndataForwardSmokeTest is Test, YulTestBase {
    address internal forwarder;
    address internal echo;
    ReturndataForwardReference internal referenceContract;

    function setUp() public {
        forwarder = deployCompiledVerityModule(
            "Contracts.Smoke.ReturndataForwardSmoke",
            "ReturndataForwardSmoke",
            _smokeYulDir()
        );
        referenceContract = new ReturndataForwardReference();
        echo = address(new ReturndataForwardEcho());
    }

    function _payload(uint256 length) internal pure returns (bytes memory payload) {
        payload = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            payload[i] = bytes1(uint8(0xa1 + i));
        }
    }

    function _assertCall(
        string memory signature,
        bool calleeReverts,
        uint256 length,
        bool expectSuccess,
        bytes memory expectData
    ) internal {
        bytes memory callData = abi.encodeWithSignature(signature, echo, calleeReverts ? 1 : 0, length);
        (bool yulSuccess, bytes memory yulData) = forwarder.call(callData);
        (bool refSuccess, bytes memory refData) = address(referenceContract).call(callData);

        assertEq(yulSuccess, expectSuccess, "success flag");
        assertEq(yulData, expectData, "forwarded returndata");
        assertEq(yulSuccess, refSuccess, "success parity");
        assertEq(yulData, refData, "returndata parity");
    }

    function _assertForwards(bool reverts, uint256 length) internal {
        _assertCall("forward(address,uint256,uint256)", reverts, length, !reverts, _payload(length));
    }

    function testReturnsReturndataVerbatim() public {
        _assertForwards(false, 0);
        _assertForwards(false, 1);
        _assertForwards(false, 31);
        _assertForwards(false, 33);
        _assertForwards(false, 95);
    }

    /// `returnReturndata` in one branch; the failing path falls through to an empty success.
    function testTailOfOneBranch() public {
        _assertCall("forwardIfSuccess(address,uint256,uint256)", false, 33, true, _payload(33));
        _assertCall("forwardIfSuccess(address,uint256,uint256)", true, 37, true, "");
    }

    /// Plain tail `returnReturndata`: even a callee revert payload becomes success data.
    function testPlainTail() public {
        _assertCall("forwardAlways(address,uint256,uint256)", false, 31, true, _payload(31));
        _assertCall("forwardAlways(address,uint256,uint256)", true, 37, true, _payload(37));
    }

    /// With a (precondition-only) modifier: its storage write persists, the payload is forwarded.
    function testWithModifier() public {
        (bool ok, bytes memory data) = forwarder.call(
            abi.encodeWithSignature("forwardCounted(address,uint256,uint256)", echo, 1, 37));
        assertTrue(ok, "forwardCounted reverted");
        assertEq(data, _payload(37), "forwarded returndata");
        (bool readOk, bytes memory count) = forwarder.call(abi.encodeWithSignature("callCount()"));
        assertTrue(readOk, "callCount reverted");
        assertEq(abi.decode(count, (uint256)), 1, "modifier ran once before the forward");
    }

    function testRevertsWithReturndataVerbatim() public {
        _assertForwards(true, 0);
        _assertForwards(true, 1);
        _assertForwards(true, 37);
    }
}

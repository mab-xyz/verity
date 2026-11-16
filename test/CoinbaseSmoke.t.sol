// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "forge-std/Test.sol";
import "./yul/YulTestBase.sol";

/// `blockCoinbase` compiles to `coinbase()`: the compiled contract reads `block.coinbase`
/// and can pay a builder tip to it.
contract CoinbaseSmokeTest is Test, YulTestBase {
    address internal smoke;

    function setUp() public {
        smoke = deployCompiledVerityModule("Contracts.Smoke.CoinbaseSmoke", "CoinbaseSmoke", _smokeYulDir());
    }

    function _who() internal returns (address) {
        (bool ok, bytes memory data) = smoke.call(abi.encodeWithSignature("who()"));
        assertTrue(ok, "who() reverted");
        return abi.decode(data, (address));
    }

    function testWhoReturnsBlockCoinbase() public {
        address builder = address(0xC0FFEE);
        vm.coinbase(builder);
        // tx.origin, msg.sender and address(this) all differ from the coinbase.
        assertTrue(builder != tx.origin && builder != address(this) && builder != smoke);
        assertEq(_who(), builder);
    }

    function testWhoTracksCoinbaseChanges(address builder) public {
        vm.coinbase(builder);
        assertEq(_who(), builder);
    }

    function testPayCoinbaseSendsTip() public {
        address builder = address(0xB0B);
        vm.coinbase(builder);
        vm.deal(smoke, 3 ether);
        uint256 before = builder.balance;
        (bool ok,) = smoke.call(abi.encodeWithSignature("payCoinbase(uint256)", 1 ether));
        assertTrue(ok, "payCoinbase reverted");
        assertEq(builder.balance - before, 1 ether);
        assertEq(smoke.balance, 2 ether);
    }

    function testPayCoinbaseRevertsWithoutFunds() public {
        vm.coinbase(address(0xB0B));
        (bool ok,) = smoke.call(abi.encodeWithSignature("payCoinbase(uint256)", 1 ether));
        assertFalse(ok);
    }
}

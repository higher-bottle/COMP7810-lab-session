// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {MockUSDC} from "../../src/MockUSDC.sol";
import {SimpleStablecoin} from "../../src/SimpleStablecoin.sol";
import {Vault} from "../../src/Vault.sol";

/// @title Ex2 + Ex4 — hands-on tasks: turn red into green
/// @notice Every `assertTrue(false, "TODO ...")` below is a placeholder. Write the real
///         assertion, watch the test go green, and that exercise is done.
///
///         Acceptance: make exercise (it should be red until you are finished)
///         Do not open test/Stablecoin.t.sol — it contains the answers. Write yours
///         first, and only look once you are stuck.
contract LoopTasksTest is Test {
    MockUSDC internal usdc;
    SimpleStablecoin internal stable;
    Vault internal vault;

    address internal admin = address(this);
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        usdc = new MockUSDC();
        stable = new SimpleStablecoin(admin);
        vault = new Vault(usdc, stable);
        stable.grantRole(stable.MINTER_ROLE(), address(vault));
    }

    // ==================================================================
    // Ex2 · the decimals trap: a 6-decimal stablecoin meets 18-decimal intuition
    // ==================================================================

    /// @dev For any legitimate amount x, totalSupply() must grow by exactly x after
    ///      deposit(x). Hint: use vm.assume to rule out x == 0, and faucet alice enough
    ///      usdc first.
    function test_Ex2_DepositIncreasesSupplyByExactly(uint96 raw) public {
        // Keep fuzzed deposits non-zero and within the funded test range.
        uint256 amount = uint256(raw) % 1_000_000e6;
        vm.assume(amount != 0);

        usdc.faucet(alice, amount);
        vm.prank(alice);
        usdc.approve(address(vault), amount);

        uint256 supplyBefore = stable.totalSupply();
        vm.prank(alice);
        vault.deposit(amount);

        assertEq(stable.totalSupply() - supplyBefore, amount);
    }

    /// @dev Run deposit with 1000e18 instead of 1000e6, see what happens, then assert what
    ///      you observed. MockUSDC has 6 decimals — 1000e18 is 10^15 USDC.
    ///      There is no expected answer here; the point is that you run it yourself and
    ///      read the numbers.
    function test_Ex2_DecimalsTrap() public {
        // 1000e18 is interpreted as 10^15 tokens by a 6-decimal token.
        uint256 amount = 1000e18;
        usdc.faucet(alice, amount);
        vm.prank(alice);
        usdc.approve(address(vault), amount);

        vm.prank(alice);
        vault.deposit(amount);

        assertEq(usdc.balanceOf(alice), 0);
        assertEq(vault.totalCollateral(), amount);
        assertEq(stable.balanceOf(alice), amount);
        assertEq(stable.totalSupply(), amount);
    }

    // ==================================================================
    // Ex4 · permissions and pausing: where the guard is, who holds the key
    // ==================================================================

    /// @dev The attacker has no MINTER_ROLE, so calling mint directly must revert. Use
    ///      vm.expectRevert + abi.encodeWithSelector to pin down the exact error.
    function test_Ex4_Mint_RevertsForNonMinter() public {
        // Match the exact AccessControl error and missing role.
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                stable.MINTER_ROLE()
            )
        );
        vm.prank(attacker);
        stable.mint(attacker, 1e6);
    }

    /// @dev After pause(), an ordinary transfer must revert
    function test_Ex4_Pause_BlocksTransfers() public {
        stable.mint(alice, 1e6);
        stable.pause();

        // Pausing blocks balance changes routed through _update().
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(alice);
        stable.transfer(attacker, 1);
    }

    /// @dev What pause() freezes is _update, so redemption is frozen along with everything
    ///      else — why is that bad news in a real crisis?
    ///      (This is STUDENT-QUESTIONS.md B1 and B2.)
    function test_Ex4_Pause_BlocksRedeem() public {
        uint256 amount = 1e6;
        usdc.faucet(alice, amount);
        vm.prank(alice);
        usdc.approve(address(vault), amount);
        vm.prank(alice);
        vault.deposit(amount);

        // Redemption burns sUSD, so the shared pause check blocks it too.
        stable.pause();
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(alice);
        vault.redeem(amount);
    }

    /// @dev An attacker cannot burn someone else's balance
    function test_Ex4_AttackerCannotBurnOthersBalance() public {
        stable.mint(alice, 1e6);

        // The attacker cannot pass burn()'s MINTER_ROLE check.
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                stable.MINTER_ROLE()
            )
        );
        vm.prank(attacker);
        stable.burn(alice, 1e6);
    }

    /// @dev ...but the vault can, because it holds MINTER_ROLE and burn() answers to that
    ///      same role. This test proves the backdoor exists; it does not justify it.
    function test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance() public {
        stable.mint(alice, 1e6);

        // The vault can burn Alice's tokens because it holds MINTER_ROLE.
        vm.prank(address(vault));
        stable.burn(alice, 1e6);

        assertEq(stable.balanceOf(alice), 0);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20, IERC20Meta} from "src/IERC20.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {BasePairTest} from "./BasePairTest.t.sol";
import {ISettlerActions} from "src/ISettlerActions.sol";
import {ActionDataBuilder} from "../utils/ActionDataBuilder.sol";
import {BaseSettler as Settler} from "src/chains/Base.sol";
import {SettlerBase} from "src/SettlerBase.sol";

import {AllowanceHolder} from "src/allowanceholder/AllowanceHolder.sol";
import {IAllowanceHolder} from "src/allowanceholder/IAllowanceHolder.sol";

contract Shim {
    // forgefmt: disable-next-line
    function chainId() external returns (uint256) { // this is non-view (mutable) on purpose
        return block.chainid;
    }
}

contract VelodromePairTest is BasePairTest {
    function testName() internal pure override returns (string memory) {
        return "USDT-USDC";
    }

    Settler internal settler;
    IAllowanceHolder internal allowanceHolder;
    uint256 private _amount;

    function setUp() public override {
        // the pool specified below doesn't have very much liquidity, so we only swap a small amount
        IERC20Meta sellToken = IERC20Meta(address(fromToken()));
        _amount = 10 ** sellToken.decimals() * 100;

        super.setUp();
        safeApproveIfBelow(fromToken(), FROM, address(PERMIT2), amount());

        allowanceHolder = IAllowanceHolder(0x0000000000001fF3684f28c67538d4D072C22734);

        uint256 forkChainId = (new Shim()).chainId();
        vm.chainId(31337);
        settler = new Settler(bytes20(0));
        vm.etch(address(allowanceHolder), address(new AllowanceHolder()).code);
        vm.chainId(forkChainId);
    }

    function fromToken() internal pure override returns (IERC20) {
        return IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7); // USDT
    }

    function toToken() internal pure override returns (IERC20) {
        return IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
    }

    function velodromePool() internal pure returns (address) {
        return 0x63A65a174Cc725824188940255aD41c371F28F28; // actually solidlyv2 (velodrome does not exist on mainnet)
    }

    function amount() internal view override returns (uint256) {
        return _amount;
    }

    function testSettler_velodrome() public skipIf(velodromePool() == address(0)) {
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(fromToken()), amount: amount()}),
            nonce: 1,
            deadline: block.timestamp + 30 seconds
        });
        bytes memory sig = getPermitTransferSignature(permit, address(settler), FROM_PRIVATE_KEY, permit2Domain);
        uint24 swapInfo = (2 << 8) | (0 << 1) | (0);
        // fees = 2 bp; internally, solidly uses ppm
        bytes[] memory actions = ActionDataBuilder.build(
            abi.encodeCall(ISettlerActions.TRANSFER_FROM, (velodromePool(), permit, sig)),
            abi.encodeCall(ISettlerActions.VELODROME, (FROM, 0, velodromePool(), swapInfo, 0))
        );

        Settler _settler = settler;

        // USDT is obnoxious about throwing errors, so let's check here before we run into something inscrutable
        assertGe(fromToken().balanceOf(FROM), amount());
        assertGe(fromToken().allowance(FROM, address(PERMIT2)), amount());

        uint256 beforeBalance = toToken().balanceOf(FROM);
        vm.startPrank(FROM, FROM);
        snapStartName("settler_velodrome");
        _settler.execute(
            SettlerBase.AllowedSlippage({recipient: address(0), buyToken: IERC20(address(0)), minAmountOut: 0}), actions
        );
        snapEnd();
        uint256 afterBalance = toToken().balanceOf(FROM);

        assertGt(afterBalance, beforeBalance);
    }
}
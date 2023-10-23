// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {SafeTransferLib} from "../utils/SafeTransferLib.sol";
import {FullMath} from "../utils/FullMath.sol";

interface IPSM {
    // @dev Get the fee for selling DAI to USDC in PSM
    // @return tout toll out [wad]
    function tout() external view returns (uint256);

    // @dev Get the address of the underlying vault powering PSM
    // @return address of gemJoin contract
    function gemJoin() external view returns (address);

    // @dev Sell USDC for DAI
    // @param usr The address of the account trading USDC for DAI.
    // @param gemAmt The amount of USDC to sell in USDC base units
    function sellGem(address usr, uint256 gemAmt) external;

    // @dev Buy USDC for DAI
    // @param usr The address of the account trading DAI for USDC
    // @param gemAmt The amount of USDC to buy in USDC base units
    function buyGem(address usr, uint256 gemAmt) external;
}

abstract contract MakerPSM {
    using FullMath for uint256;
    using SafeTransferLib for ERC20;

    // Maker units https://github.com/makerdao/dss/blob/master/DEVELOPING.md
    // wad: fixed point decimal with 18 decimals (for basic quantities, e.g. balances)
    uint256 internal constant WAD = 10 ** 18;

    ERC20 internal immutable DAI;

    constructor(address dai) {
        DAI = ERC20(dai);
    }

    function makerPsmSellGem(address recipient, uint256 bips, IPSM psm, ERC20 gemToken) internal {
        uint256 sellAmount = gemToken.balanceOf(address(this)).mulDiv(bips, 10_000);
        gemToken.safeApproveIfBelow(psm.gemJoin(), sellAmount);
        psm.sellGem(recipient, sellAmount);
    }

    function makerPsmBuyGem(address recipient, uint256 bips, IPSM psm, ERC20 gemToken) internal {
        uint256 sellAmount = DAI.balanceOf(address(this)).mulDiv(bips, 10_000);
        uint256 feeDivisor = WAD + psm.tout(); // eg. 1.001 * 10 ** 18 with 0.1% fee [tout is in wad];
        uint256 buyAmount = sellAmount.mulDiv(10 ** uint256(gemToken.decimals()), feeDivisor);

        DAI.safeApproveIfBelow(address(psm), sellAmount);
        psm.buyGem(recipient, buyAmount);
    }
}

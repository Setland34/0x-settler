// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {SettlerBase} from "../SettlerBase.sol";
import {Settler} from "../Settler.sol";
import {SettlerMetaTxn} from "../SettlerMetaTxn.sol";

import {FreeMemory} from "../utils/FreeMemory.sol";

import {IERC20Meta} from "../IERC20.sol";
import {ISettlerActions} from "../ISettlerActions.sol";
import {UnknownForkId} from "../core/SettlerErrors.sol";

import {uniswapV3MainnetFactory, uniswapV3InitHash, IUniswapV3Callback} from "../core/univ3forks/UniswapV3.sol";

// Solidity inheritance is stupid
import {AbstractContext} from "../Context.sol";
import {Permit2PaymentBase} from "../core/Permit2Payment.sol";
import {Permit2PaymentAbstract} from "../core/Permit2PaymentAbstract.sol";

abstract contract PolygonMixin is FreeMemory, SettlerBase {
    constructor() {
        assert(block.chainid == 137 || block.chainid == 31337);
    }

    function _dispatch(uint256 i, bytes4 action, bytes calldata data)
        internal
        virtual
        override
        DANGEROUS_freeMemory
        returns (bool)
    {
        return super._dispatch(i, action, data);
    }

    function _uniV3ForkInfo(uint8 forkId)
        internal
        pure
        override
        returns (address factory, bytes32 initHash, bytes4 callbackSelector)
    {
        if (forkId == 0) {
            factory = uniswapV3MainnetFactory;
            initHash = uniswapV3InitHash;
            callbackSelector = IUniswapV3Callback.uniswapV3SwapCallback.selector;
        } else {
            revert UnknownForkId(forkId);
        }
    }
}

/// @custom:security-contact security@0x.org
contract PolygonSettler is Settler, PolygonMixin {
    function _dispatchVIP(bytes4 action, bytes calldata data) internal override DANGEROUS_freeMemory returns (bool) {
        return super._dispatchVIP(action, data);
    }

    // Solidity inheritance is stupid
    function _isRestrictedTarget(address target)
        internal
        pure
        override(Settler, Permit2PaymentBase, Permit2PaymentAbstract)
        returns (bool)
    {
        return super._isRestrictedTarget(target);
    }

    function _dispatch(uint256 i, bytes4 action, bytes calldata data)
        internal
        override(SettlerBase, PolygonMixin)
        returns (bool)
    {
        return super._dispatch(i, action, data);
    }

    function _msgSender() internal view override(Settler, Permit2PaymentBase, AbstractContext) returns (address) {
        return super._msgSender();
    }
}

/// @custom:security-contact security@0x.org
contract PolygonSettlerMetaTxn is SettlerMetaTxn, PolygonMixin {
    function _dispatchVIP(bytes4 action, bytes calldata data, bytes calldata sig)
        internal
        override
        DANGEROUS_freeMemory
        returns (bool)
    {
        return super._dispatchVIP(action, data, sig);
    }

    // Solidity inheritance is stupid
    function _dispatch(uint256 i, bytes4 action, bytes calldata data)
        internal
        override(SettlerBase, PolygonMixin)
        returns (bool)
    {
        return super._dispatch(i, action, data);
    }

    function _msgSender()
        internal
        view
        override(SettlerMetaTxn, Permit2PaymentBase, AbstractContext)
        returns (address)
    {
        return super._msgSender();
    }
}
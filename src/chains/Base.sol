// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {SettlerBase} from "../SettlerBase.sol";
import {Settler} from "../Settler.sol";
import {SettlerMetaTxn} from "../SettlerMetaTxn.sol";

import {ActionInvalid} from "../core/SettlerErrors.sol";

import {IERC20Meta} from "../IERC20.sol";
import {ISettlerActions} from "../ISettlerActions.sol";
import {ActionInvalid} from "../core/SettlerErrors.sol";

// Solidity inheritance is stupid
import {AbstractContext} from "../Context.sol";
import {Permit2PaymentBase} from "../core/Permit2Payment.sol";
import {Permit2PaymentAbstract} from "../core/Permit2PaymentAbstract.sol";

abstract contract BaseMixin is SettlerBase {
    constructor() {
        assert(block.chainid == 8453 || block.chainid == 31337);
    }

    function _dispatch(uint256 i, bytes4 action, bytes calldata data)
        internal
        virtual
        override
        DANGEROUS_freeMemory
        returns (bool)
    {
        if (super._dispatch(i, action, data)) {
            return true;
        } else {
            revert ActionInvalid(i, action, data);
        }
    }
}

/// @custom:security-contact security@0x.org
contract BaseSettler is Settler, BaseMixin {
    constructor(address uniFactory) Settler(uniFactory) {}

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
        override(SettlerBase, BaseMixin)
        returns (bool)
    {
        return super._dispatch(i, action, data);
    }

    function _msgSender() internal view override(Settler, Permit2PaymentBase, AbstractContext) returns (address) {
        return super._msgSender();
    }
}

/// @custom:security-contact security@0x.org
contract BaseSettlerMetaTxn is SettlerMetaTxn, BaseMixin {
    constructor(address uniFactory) SettlerMetaTxn(uniFactory) {}

    // Solidity inheritance is stupid
    function _dispatch(uint256 i, bytes4 action, bytes calldata data)
        internal
        override(SettlerBase, BaseMixin)
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

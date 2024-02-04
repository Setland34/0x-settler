// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IAllowanceHolder} from "./IAllowanceHolder.sol";
import {IERC20} from "./IERC20.sol";
import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {CheckCall} from "./utils/CheckCall.sol";
import {FreeMemory} from "./utils/FreeMemory.sol";

/// @notice Thrown when validating the target, avoiding executing against an ERC20 directly
error ConfusedDeputy();

library TransientStorage {
    type TSlot is bytes32;

    function set(TSlot ts, uint256 nv) internal {
        assembly ("memory-safe") {
            sstore(ts, nv) // will be `tstore` after Dencun (EIP-1153)
        }
    }

    function get(TSlot ts) internal view returns (uint256 cv) {
        assembly ("memory-safe") {
            cv := sload(ts) // will be `tload` after Dencun (EIP-1153)
        }
    }
}

abstract contract TransientStorageMock {
    using TransientStorage for TransientStorage.TSlot;

    bytes32 private _sentinel;

    constructor() {
        uint256 _sentinelSlot;
        assembly ("memory-safe") {
            _sentinelSlot := _sentinel.slot
        }
        assert(_sentinelSlot == 0);
    }

    /// @dev The key for this ephemeral allowance is keccak256(abi.encodePacked(operator, owner, token)).
    function _ephemeralAllowance(address operator, address owner, address token)
        internal
        pure
        returns (TransientStorage.TSlot r)
    {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(0x28, token)
            mstore(0x14, owner)
            mstore(0x00, operator)
            // allowance slot is keccak256(abi.encodePacked(operator, owner, token))
            r := keccak256(0x0c, 0x3c)
            // restore dirtied free pointer
            mstore(0x40, ptr)
        }
    }
}

contract AllowanceHolder is TransientStorageMock, FreeMemory {
    using SafeTransferLib for IERC20;
    using CheckCall for address payable;
    using TransientStorage for TransientStorage.TSlot;

    function _rejectIfERC20(address payable maybeERC20, bytes calldata data) private view DANGEROUS_freeMemory {
        // We could just choose a random address for this check, but to make
        // confused deputy attacks harder for tokens that might be badly behaved
        // (e.g. tokens with blacklists), we choose to copy the first argument
        // out of `data` and mask it as an address. If there isn't enough
        // `data`, we use 0xdead instead.
        address target;
        if (data.length > 0x10) {
            target = address(uint160(bytes20(data[0x10:])));
        }
        if (target == address(0)) {
            target = address(0xdead);
        }
        bytes memory testData = abi.encodeCall(IERC20(maybeERC20).balanceOf, target);
        // 500k gas seems like a pretty healthy upper bound for the amount of
        // gas that `balanceOf` could reasonably consume in a well-behaved
        // ERC20.
        if (maybeERC20.checkCall(testData, 500_000, 0x20)) revert ConfusedDeputy();
    }

    function _msgSender() private view returns (address sender) {
        sender = msg.sender;
        if (sender == address(this)) {
            assembly ("memory-safe") {
                sender := shr(0x60, calldataload(sub(calldatasize(), 0x14)))
            }
        }
    }

    function exec(address operator, address token, uint256 amount, address payable target, bytes calldata data)
        internal
        returns (bytes memory result)
    {
        // This contract has no special privileges, except for the allowances it
        // holds. In order to prevent abusing those allowances, we prohibit
        // sending arbitrary calldata (doing `target.call(data)`) to any
        // contract that might be an ERC20.
        _rejectIfERC20(target, data);

        address sender = _msgSender();
        TransientStorage.TSlot allowance = _ephemeralAllowance(operator, sender, token);
        allowance.set(amount);

        // For gas efficiency we're omitting a bunch of checks here. Notably,
        // we're omitting the check that `address(this)` has sufficient value to
        // send (we know it does; makes us more ERC-4337 friendly), and we're
        // omitting the check that `target` contains code (we already checked in
        // `_rejectIfERC20`).
        assembly ("memory-safe") {
            result := mload(0x40)
            calldatacopy(result, data.offset, data.length)
            // ERC-2771 style msgSender forwarding https://eips.ethereum.org/EIPS/eip-2771
            mstore(add(result, data.length), shl(0x60, sender))
            let success := call(gas(), target, callvalue(), result, add(data.length, 0x14), 0x00, 0x00)
            let ptr := add(result, 0x20)
            returndatacopy(ptr, 0x00, returndatasize())
            switch success
            case 0 { revert(ptr, returndatasize()) }
            default {
                mstore(result, returndatasize())
                mstore(0x40, add(ptr, returndatasize()))
            }
        }

        // EIP-3074 seems unlikely; ERC-4337 unfriendly
        if (sender != tx.origin) {
            allowance.set(0);
        }
    }

    function transferFrom(address token, address owner, address recipient, uint256 amount) internal {
        // msg.sender is the assumed and later validated operator
        TransientStorage.TSlot allowance = _ephemeralAllowance(msg.sender, owner, token);
        // validation of the ephemeral allowance for operator, owner, token via uint underflow
        allowance.set(allowance.get() - amount);
        IERC20(token).safeTransferFrom(owner, recipient, amount);
    }

    fallback() external payable {
        uint256 selector;
        assembly ("memory-safe") {
            selector := shr(0xe0, calldataload(0x00))
        }
        if (selector == uint256(uint32(IAllowanceHolder.transferFrom.selector))) {
            address token;
            address owner;
            address recipient;
            uint256 amount;
            assembly ("memory-safe") {
                let err := callvalue()
                token := calldataload(0x04)
                err := or(err, shr(0xa0, token))
                owner := calldataload(0x24)
                err := or(err, shr(0xa0, owner))
                recipient := calldataload(0x44)
                err := or(err, shr(0xa0, recipient))
                if err { revert(0x00, 0x00) }
                amount := calldataload(0x64)
            }

            transferFrom(token, owner, recipient, amount);

            // return true;
            assembly ("memory-safe") {
                mstore(0x00, 0x01)
                return(0x00, 0x20)
            }
        } else if (selector == uint256(uint32(IAllowanceHolder.exec.selector))) {
            address operator;
            address token;
            uint256 amount;
            address payable target;
            bytes calldata data;
            assembly ("memory-safe") {
                operator := calldataload(0x04)
                let err := shr(0xa0, operator)
                token := calldataload(0x24)
                err := or(err, shr(0xa0, token))
                amount := calldataload(0x44)
                target := calldataload(0x64)
                err := or(err, shr(0xa0, target))
                if err { revert(0x00, 0x00) }
                // we perform no validation that `data` is reasonable
                data.offset := add(0x04, calldataload(0x84))
                data.length := calldataload(data.offset)
                data.offset := add(0x20, data.offset)
            }

            bytes memory result = exec(operator, token, amount, target, data);

            // return result;
            assembly ("memory-safe") {
                let returndata := sub(result, 0x20)
                mstore(returndata, 0x20)
                return(returndata, add(0x40, mload(result)))
            }
        } else if (selector == uint256(uint32(IERC20.balanceOf.selector))) {
            // balanceOf(address) reverts with a single byte of returndata,
            // making it more gas efficient to pass the `_rejectERC20` check
            assembly ("memory-safe") {
                revert(0x00, 0x01)
            }
        } else {
            // emulate standard Solidity behavior
            assembly ("memory-safe") {
                revert(0x00, 0x00)
            }
        }
    }

    // This is here as a deploy-time check that AllowanceHolder doesn't have any
    // state. If it did, it would interfere with TransientStorageMock. This can
    // be removed once *actual* EIP-1153 is adopted.
    bytes32 private _sentinel;

    constructor() {
        uint256 _sentinelSlot;
        assembly ("memory-safe") {
            _sentinelSlot := _sentinel.slot
        }
        assert(_sentinelSlot == 1);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {UnsafeMath} from "./utils/UnsafeMath.sol";
import {CallWithGas} from "./utils/CallWithGas.sol";

library UnsafeArray {
    function unsafeGet(ISignatureTransfer.TokenPermissions[] calldata a, uint256 i)
        internal
        pure
        returns (ISignatureTransfer.TokenPermissions calldata r)
    {
        assembly ("memory-safe") {
            r := add(a.offset, shl(6, i))
        }
    }

    function unsafeGet(AllowanceHolder.TransferDetails[] calldata a, uint256 i)
        internal
        pure
        returns (AllowanceHolder.TransferDetails calldata r)
    {
        assembly ("memory-safe") {
            r := add(a.offset, mul(0x60, i))
        }
    }
}

contract AllowanceHolder {
    using SafeTransferLib for ERC20;
    using CallWithGas for address payable;
    using UnsafeMath for uint256;
    using UnsafeArray for ISignatureTransfer.TokenPermissions[];
    using UnsafeArray for TransferDetails[];

    bytes32 internal constant _MOCK_TRANSIENT_START_SLOT =
        0x588fe8b62ed655cf29d31d5107e62b4fbc51f24e11339fa0f890fb831d2d43bc;

    constructor() {
        assert(_MOCK_TRANSIENT_START_SLOT == bytes32(uint256(keccak256("mock transient start slot")) - 65536));
    }

    struct MockTransientStorage {
        address operator;
        bytes32 witness;
        mapping(address => uint256) allowed;
    }

    function _getTransientStorage() private pure returns (MockTransientStorage storage result) {
        assembly ("memory-safe") {
            result.slot := _MOCK_TRANSIENT_START_SLOT
        }
    }

    error ConfusedDeputy();

    function execute(
        address operator,
        bytes32 witness,
        ISignatureTransfer.TokenPermissions[] calldata permits,
        address payable target,
        bytes calldata data
    ) public payable returns (bytes memory result) {
        require(msg.sender == tx.origin); // caller is an EOA; effectively a reentrancy guard; EIP-3074 seems unlikely
        {
            bytes memory testData;
            // We could just choose a random address for this check, but to make
            // confused deputy attacks harder for tokens that might be badly
            // behaved (e.g. tokens with blacklists), we choose to copy the
            // first argument out of `data` and mask it as an address.
            assembly ("memory-safe") {
                testData := mload(0x40)
                mstore(0x40, add(testData, 0x44))
                mstore(testData, 0x24) // length
                mstore(
                    add(testData, 0x20),
                    // balanceOf(address) selector
                    0x70a0823100000000000000000000000000000000000000000000000000000000
                )
                switch lt(data.length, 0x24)
                case 0 {
                    // copy what might be an address out of `data`
                    calldatacopy(add(testData, 0x30), add(data.offset, 0x10), 0x14)
                }
                default {
                    // `data` is too short; guess we have to choose a random address anyways
                    mstore(add(testData, 0x24), 0xdead)
                }
            }
            // 500k gas seems like a pretty healthy upper bound for the amount
            // of gas that `balanceOf` could reasonably consume in a
            // well-behaved ERC20. 0x7724e bytes of returndata would cause this
            // context to consume over 500k gas in memory costs, again something
            // a well-behaved ERC20 never ought to do.
            (bool success, bytes memory returnData) = target.functionStaticCallWithGas(testData, 500_000, 0x7724e);
            if (success && returnData.length >= 32) {
                revert ConfusedDeputy();
            }
            // clear the memory we just allocated
            assembly ("memory-safe") {
                mstore(0x40, testData)
            }
        }

        MockTransientStorage storage tstor = _getTransientStorage();
        tstor.operator = operator;
        tstor.witness = witness;
        for (uint256 i; i < permits.length; i = i.unsafeInc()) {
            ISignatureTransfer.TokenPermissions calldata permit = permits.unsafeGet(i);
            tstor.allowed[permit.token] = permit.amount;
        }

        {
            bool success;
            (success, result) = target.call{value: msg.value}(data);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(result, 0x20), mload(result))
                }
            }
        }

        // this isn't required after *actual* EIP-1153 is adopted. this is only needed for the mock
        tstor.operator = address(0);
        tstor.witness = bytes32(0);
        for (uint256 i; i < permits.length; i = i.unsafeInc()) {
            tstor.allowed[permits.unsafeGet(i).token] = 0;
        }
    }

    struct TransferDetails {
        address token;
        address recipient;
        uint256 amount;
    }

    function _checkAmountsAndTransfer(TransferDetails[] calldata transferDetails, MockTransientStorage storage tstor)
        private
    {
        for (uint256 i; i < transferDetails.length; i = i.unsafeInc()) {
            TransferDetails calldata transferDetail = transferDetails.unsafeGet(i);
            tstor.allowed[transferDetail.token] -= transferDetail.amount; // reverts on underflow
        }
        for (uint256 i; i < transferDetails.length; i = i.unsafeInc()) {
            TransferDetails calldata transferDetail = transferDetails.unsafeGet(i);
            ERC20(transferDetail.token).safeTransferFrom(tx.origin, transferDetail.recipient, transferDetail.amount);
        }
    }

    function transferFrom(TransferDetails[] calldata transferDetails) public {
        MockTransientStorage storage tstor = _getTransientStorage();
        require(msg.sender == tstor.operator);
        require(tstor.witness == bytes32(0));
        _checkAmountsAndTransfer(transferDetails, tstor);
    }

    function transferFrom(TransferDetails[] calldata transferDetails, bytes32 witness) public {
        MockTransientStorage storage tstor = _getTransientStorage();
        require(msg.sender == tstor.operator);
        require(witness == tstor.witness);
        tstor.operator = address(0);
        _checkAmountsAndTransfer(transferDetails, tstor);
    }
}

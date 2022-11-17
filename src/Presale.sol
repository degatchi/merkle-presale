pragma solidity ^0.8.13;

import {MerkleProof} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

error SaleOngoing(uint256 current, uint256 ends);
error SaleNotStarted(uint256 current, uint256 start);
error SaleEnded(uint256 current, uint256 ends);
error InvalidProof();
error AlreadyInitialised();
error NotInitialised();
error AlreadyClaimed();
error ClaimsNotOpen();
error PaymentCalcUnderflow();
error NotPaymentToken();
error ModularError(uint120 by, uint120 remainder);

interface IERC20 {
    function balanceOf(address) external returns (uint256);
    function transfer(address, uint256) external;
    function transferFrom(address, address, uint256) external;
}

interface IPresale {
    event Initialised();
    event ClaimRootSet(bytes32 indexed root);
    event BuyOrder(
        address indexed buyer,
        address indexed paymentToken,
        uint256 indexed payment,
        uint256 tokens
    );
    event Claim(
        address indexed buyer,
        uint256 indexed filledTokens,
        uint256 unusedUsdc,
        uint256 unusedUsdt,
        uint256 unusedDai
    );
}

// --------------------------------------------------------------------------------------
//
// Presale | SPDX-License-Identifier: MIT
// Authored by, DeGatchi (https://github.com/DeGatchi).
//
// --------------------------------------------------------------------------------------
contract Presale is IPresale, Ownable {
    /// Whether the contract's variables have been set.
    bool public initialised;

    /// Tokens being used as payment.
    address public immutable dai;
    address public immutable usdt;
    address public immutable usdc;
    /// Token being sold.
    IERC20 public immutable token;
    
    /// When the sale begins.
    uint40 public start;
    /// How long the sale goes for.
    uint40 public duration;
    /// Total amount of tokens for sale.
    uint120 public supply;
    /// Total amount of tokens ordered.
    uint120 public supplyOrdered;
    /// Price per token ($0.5)
    uint256 public price;

    /// Root used to set the claim statistics.
    bytes32 public claimRoot;

    struct Receipt {
        uint120 dai; // Total DAI used as payment (18 decimals).
        uint120 usdt; // Total USDT used as payment (6 decimals).
        uint120 usdc; // Total USDC used as payment (6 decimals).
        uint120 tokens; // Total presale tokens ordered.
        bool claimed; // Whether the order has been claimed.
    }

    /// A record of EOAs and their corresponding order receipts.
    mapping(address => Receipt) public receipt;

    /// Enable use when contract has initialised.
    modifier onlyInit() {
        if (!initialised) revert NotInitialised();
        _;
    }

    /// Enable use when the sale has finished.
    modifier onlyEnd() {
        if (block.timestamp < start + duration)
            revert SaleOngoing(block.timestamp, start + duration);
        _;
    }

    /// @notice Sets up the contract addresses as immutable for gas saving.
    /// @param _dai ERC20 USDC token being used as payment (has 18 decimals).
    /// @param _usdt ERC20 USDC token being used as payment (has 6 decimals).
    /// @param _usdc ERC20 USDC token being used as payment (has 6 decimals).
    /// @param _token ERC20 token being sold for `_usdc`.
    constructor(
        address _dai,
        address _usdt,
        address _usdc,
        address _token
    ) {
        dai = _dai;
        usdt = _usdt;
        usdc = _usdc;
        token = IERC20(_token);
    }

    /// @notice Sets up the sale.
    /// @dev Requires the initialiser to send `_supply` of `_token` to this address.
    /// @param _start Timestamp of when the sale begins.
    /// @param _duration How long the sale goes for.
    /// @param _supply The amount of `_token` being sold.
    /// @param _price The `_usdc` payment value of each `_token`.
    function initialise(
        uint40 _start,
        uint40 _duration,
        uint120 _supply,
        uint256 _price
    ) external onlyOwner {
        if (initialised) revert AlreadyInitialised();

        token.transferFrom(msg.sender, address(this), _supply);

        initialised = true;

        start = _start;
        duration = _duration;
        supply = _supply;
        price = _price;

        emit Initialised();
    }

    /// @notice Allows owner to update the claim root to enable `claim()`.
    /// @dev Used to update the `claimRoot` to enable claiming.
    /// @param _newRoot Merkle root used after sale has ended to allow buyers to claim their tokens.
    function setClaimRoot(bytes32 _newRoot) public onlyOwner onlyEnd {
        if (block.timestamp < start)
            revert SaleNotStarted(block.timestamp, start);
        claimRoot = _newRoot;
        emit ClaimRootSet(_newRoot);
    }

    /// @notice Allows users to create an order to purchase presale tokens w/ USDC.
    /// @dev The buy event is used for the backend bot to determine the orders.
    /// @param _tokens Amount of presale tokens to purchase (where 1 = 1 token).
    /// @param _paymentToken Token paying with.
    function createBuyOrder(uint120 _tokens, address _paymentToken)
        external
        onlyInit
    {
        // Make sure the sale is ongoing.
        uint40 _start = start;
        if (block.timestamp < _start) revert SaleNotStarted(block.timestamp, _start);
        if (block.timestamp >= _start + duration) revert SaleEnded(block.timestamp, _start + duration);

        // Make sure they're buying a whole number of tokens.
        if (_tokens % 1e18 != 0) revert ModularError(1e18, _tokens % 1e18);

        // Calculate and record payment.
        uint256 _payment = (_tokens * price) / 1e18;
        Receipt storage _receipt = receipt[msg.sender];
        if (_paymentToken == dai) {
            _payment = (_tokens * (price * 1e12)) / 1e18;
            _receipt.dai += uint120(_payment);
        } else if (_paymentToken == usdt) {
            _receipt.usdt += uint120(_payment);
        } else if (_paymentToken == usdc) {
            _receipt.usdc += uint120(_payment);
        } else revert NotPaymentToken();

        // Failsale sanity check.
        if (_payment == 0) revert PaymentCalcUnderflow();

        // Send payment to this contract.
        IERC20(_paymentToken).transferFrom(msg.sender, address(this), _payment);

        // Record tokens bought.
        _receipt.tokens += _tokens;
        supplyOrdered += _tokens;

        // Record order for backend calculation.
        emit BuyOrder(msg.sender, _paymentToken, _payment, _tokens);
    }

    /// @notice When sale ends, users can redeem their allocation w/ the filler bot's output.
    /// @dev Set owner as the treasury claimer to receive all used USDC + unsold tokens.
    ///      E.g, 90/100 tokens sold for 45 usdc paid; owner claims 10 tokens + 45 USDC.
    /// @param _claimer The EOA claiming on behalf for by the caller.
    /// @param _filledTokens Total presale tokens being sent to `_claimer`.
    /// @param _unusedUsdc Total USDC tokens, that weren't used to buy `token`, being sent to `_claimer`.
    /// @param _unusedUsdt Total USDT tokens, that weren't used to buy `token`, being sent to `_claimer`.
    /// @param _unusedDai Total DAI tokens, that weren't used to buy `token`, being sent to `_claimer`.
    /// @param _proof Merkle tree verification path.
    function claim(
        address _claimer,
        uint120 _filledTokens,
        uint120 _unusedUsdc,
        uint120 _unusedUsdt,
        uint120 _unusedDai,
        bytes32[] memory _proof
    ) external onlyInit onlyEnd {
        if (claimRoot == bytes32(0)) revert ClaimsNotOpen();

        Receipt storage _receipt = receipt[_claimer];
        if (_receipt.claimed) revert AlreadyClaimed();

        bytes32 node = keccak256(
            abi.encode(
                _claimer,
                _filledTokens,
                _unusedUsdc,
                _unusedUsdt,
                _unusedDai
            )
        );
        if (!MerkleProof.verify(_proof, claimRoot, node)) revert InvalidProof();

        _receipt.claimed = true;

        if (_filledTokens > 0) token.transfer(_claimer, _filledTokens);
        if (_unusedUsdc > 0) IERC20(usdc).transfer(_claimer, _unusedUsdc);
        if (_unusedUsdt > 0) IERC20(usdt).transfer(_claimer, _unusedUsdt);
        if (_unusedDai > 0) IERC20(dai).transfer(_claimer, _unusedDai);

        emit Claim(
            _claimer,
            _filledTokens,
            _unusedUsdc,
            _unusedUsdt,
            _unusedDai
        );
    }
}

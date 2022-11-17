# Tokenomics Contracts

## Presale

**Use in conjunction with my [Merkle Generator](https://github.com/DeGatchi/merkle-generator)**

### Workflow

1. User calls `createBuyOrder()` and deposits either DAI, USDT or USDC as payment for the buy order. `createBuyOrder()` emits the `BuyOrder` event.
2. When the sale finishes, the backend gathers all of the `BuyOrder` events and starts filling in the orders (see `Backend Workflow` for more).
3. Once the orders are filled, a merkle tree is generated and the root is set in the contract with `setClaimRoot()`. This is how user's claim their orders, whether filled/partially filled or unfilled.
4. The user puts in their parameters to claim + their `proof` into the `claim()` function - this transfers the filled presale token and the potentially unused payment tokens from an unfilled order.

### Backend Workflow

Algorithm:

- Creates two maps (`address -> confirmed amount`, `address -> residual amount`) where the second map is identical to (`address -> deposit amount`) at the beginning.
- For loop to add 5,000 USDC to confirmed amount if address in whitelist, likewise subtract 5,000 USDC from the second map for those addresses.
- At every loop: Check how much has been filled by summing the values of the first map, if it exceeds the raise cap, then don’t allow the loop to proceed and instead distribute evenly across all remainder addresses the (raise cap - raised so far) amount.
- Identify the smallest value in the second map, this is then distributed to all addresses with residual amount > 0, provided it doesn’t overflow the raise cap, and this amount is subtracted from the residual amount of all those addresses and added to their confirmed amount.

### Tests

Run test w/ `forge test --match-contract PresaleTest -vvv`.

```
Running 19 tests for test/Presale.t.sol:PresaleTest
[PASS] testBuyOrder_above_1e18() (gas: 202370)
[PASS] testBuyOrder_after_sale() (gas: 141567)
[PASS] testBuyOrder_before_sale() (gas: 139583)
[PASS] testBuyOrder_below_1e18() (gas: 139689)
[PASS] testBuyOrder_dai() (gas: 298565)
[PASS] testBuyOrder_exactly_1e18() (gas: 195878)
[PASS] testBuyOrder_fuzz(uint120) (runs: 256, μ: 204971, ~: 204971)
[PASS] testBuyOrder_precision_abuse() (gas: 139586)
[PASS] testBuyOrder_wrong_payment_token() (gas: 108736)
[PASS] testClaim_already_claimed() (gas: 259186)
[PASS] testClaim_by_another_user() (gas: 247779)
[PASS] testClaim_by_protocol() (gas: 333276)
[PASS] testClaim_by_sender() (gas: 247935)
[PASS] testClaim_dai() (gas: 343930)
[PASS] testClaim_invalid_proof() (gas: 236682)
[PASS] testClaim_root_not_set() (gas: 209091)
[PASS] testClaim_wrong_node_params() (gas: 234916)
[PASS] testSetRoot() (gas: 37638)
[PASS] testStartPresale() (gas: 102212)
Test result: ok. 19 passed; 0 failed; finished in 8.12s
```

## Deployments

**Testnet**

- Presale: [0xC9fe7168c388aBbC2A785BaD6e8Ba9aaba44F0E7](https://goerli.etherscan.io/address/0xC9fe7168c388aBbC2A785BaD6e8Ba9aaba44F0E7#code)
- STFXToken: [0x4b31F8eaE29F30cAaDF94EF22C5Fe9F8691f5F17](https://goerli.etherscan.io/address/0x4b31F8eaE29F30cAaDF94EF22C5Fe9F8691f5F17#code)
- MockUSDC: [0x6ab8A066998baB709953A933fd7f7BDa0fA6c913](https://goerli.etherscan.io/address/0x6ab8A066998baB709953A933fd7f7BDa0fA6c913#code)
- MockERC20: [0xBcaf3cAb324a1241E456D372AB9aDE8554AF91EC](https://goerli.etherscan.io/address/0xBcaf3cAb324a1241E456D372AB9aDE8554AF91EC#code)

## Disclaimer

These are experimental programs, use at your own risk. STFX and the developers behind these programs are not liable for any loses.

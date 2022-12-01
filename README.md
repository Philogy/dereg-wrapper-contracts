# DeReg - General purpose Circuit Breaker (GCB v1)
- supports delayed settlement of ERC20 and ERC721 token transfers as well as the
  native EVM asset (e.g. ETH on mainnet)
- can be used to protect issuance of assets as well

## Testing TODO
1. Global delay
2. ERC721 withdrawals
3. Native (ETH) withdrawals
4. Reentrancy protection
5. Method `pullERC20` returns correct amount for fee-on-transfer tokens
6. ERC777 Tokens cannot reenter pull methods to double deposit
7. Settlement guarantees (withdrawal cannot be delayed once settled)
8. Proof based settlement execution
9. Execute settlement after freeze

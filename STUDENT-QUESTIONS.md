# STUDENT-QUESTIONS.md — Discussion questions (submit with your repo)

Answer directly under each question. 150–300 words each — **reasoning over length**.

---

## A. Permission design

**A1.** The vault holds `MINTER_ROLE`, so it can `burn` any user's balance. Explain why that is a risk, then write out how you would change `Vault` and `SimpleStablecoin` to remove it.

> The risk is that `MINTER_ROLE` also gives its holders authority to destroy tokens from any account without the token holder’s approval. The Vault needs the role so that `deposit()` can mint sUSD, but it also can call `burn(alice, amount)` without anyone's approval. If an administrator replaces or reconfigures the Vault, it could therefore destroy arbitrary users' balances. It makes the token harder to integrate because users must trust every minter not to use `burn` against them.
> 
> I would separate issuance authority from redemption consent. In `SimpleStablecoin`, `mint(address,uint256)` would remain restricted to `MINTER_ROLE`, but `burn(address,uint256)` will only burns `msg.sender`'s tokens. In `Vault.redeem`, the user would first approve the vault to spend the requested sUSD. The vault would then call `stable.transferFrom(msg.sender, address(this), amount)`, burn the tokens now owned by the vault with `stable.burn(amount)`, and transfer the same amount of collateral to the user. All operations occur in one transaction, so any failure reverts the whole redemption. The vault retains only the power to mint against received collateral; it cannot reduce a user's balance unless that user explicitly grants an allowance for redemption.

<br><br><br>

**A2.** In this contract `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` all go to the same address. How would you split them in production, and who holds each?

> In production, I would not give all three roles to one address.
> 
> **I would give `DEFAULT_ADMIN_ROLE` to a multisignature wallet.** A multisignature wallet requires several trusted people to approve an action, so one person cannot change the roles alone. Because changing roles is very powerful, these actions could also have a time delay, this would give users time to notice a dangerous change.
> 
> **I would give `MINTER_ROLE` only to the vault contract.** The vault should mint sUSD only after it receives the same amount of collateral. A normal wallet should not have this role because its owner could mint unbacked tokens.
> 
> **I would give `PAUSER_ROLE` to a small security team using another multisignature wallet.** This team needs to act quickly if the contract is attacked. However, it should only be able to pause the system, not mint tokens or change permissions.
> 
> This separation reduces the damage caused by a stolen key. An attacker who obtains one role would not automatically control every part of the stablecoin.

<br><br><br>

---

## B. Pausing and redemption

**B1.** `_update` is the single entry point for every balance change, so `pause()` freezes transfers, minting and redemption together. If you wanted "pause transfers but **allow redemption**", how would you change it? Give the approach — full code not required.

> Currently, `whenNotPaused` is attached to `_update()`. Because transfers, minting, and burning all use `_update()`, calling `pause()` blocks all three operations. Redemption is also blocked because `Vault.redeem()` calls `stable.burn()` which also uses `_update()`.
> 
> To pause transfers but allow redemption, I would remove the `whenNotPaused` modifier from `_update()` and **check only whether the operation is a normal transfer**.
>
> In an ERC-20 token, a normal transfer has both `from` and `to` as **non-zero addresses**. Therefore, I would identify the operations through the following conditions:
> - if `from != address(0)` and `to != address(0)`, then **normal transfer**;
> - if `from == address(0)`, then **minting**;
> - if `to == address(0)`, then **burning**.
>
> Because redemption burns sUSD, it has `to == address(0)` and would still be allowed. In simple terms, the emergency pause would stop people trading or moving sUSD, but it would not trap users who want to exit the system and recover the collateral backing their tokens.


<br><br><br>

**B2.** In 2008, when a money-market fund "broke the buck", redemptions were frozen for days. In 2023 USDC depegged to $0.87 after a reserve bank failed, but redemptions were **not** shut. Compare the two responses — what does closing the redemption channel, or leaving it open, do to a stablecoin?


> Freezing redemptions protects the remaining asset pool from an immediate run and gives operators time to value illiquid assets, arrange financing, or resolve operational failures. That resembles the 2008 money-market response: investors could not immediately exit at the promised value, so **losses and liquidity pressure were contained inside the fund**. However, **a stablecoin with no redemption path loses its price anchor**. People can only sell sUSD to other traders, who may be unwilling to pay \$1 during a crisis, and the price of the stable coin will fall far from \$1. Uncertainty about when and at what value redemption resumes can deepen the depeg and create unequal outcomes between early sellers and trapped holders.
> 
> Leaving redemption open, as with USDC during the 2023 banking shock, preserves the economic loop: when sUSD trades below one dollar, an arbitrageur can buy it cheaply and redeem it for one dollar of collateral. Burning the redeemed coins reduces supply and tends to pull the market price back toward the peg. It also demonstrates that the **issuer is honoring its liability**. The cost is **rapid collateral outflow and possible failure if reserves are unavailable, impaired, or settled only during banking hours**.
> 
> Therefore the choices address different risks. 
> - Closing redemption is a liquidity-control measure, but it converts a concern about reserves into a direct loss of convertibility and confidence. 
> - Leaving it open supports the peg but tests reserve quality immediately. 

<br><br><br>

---

## C. Depeg analysis

**C1.** Under what conditions does this coin depeg? Distinguish at least two classes of cause, and say how each one shows up in the invariant `totalCollateral() >= totalSupply()`.

> 1. **Balance-sheet Insolvency**: sUSD supply exceeds collateral that the vault can actually deliver. In this lab, 
>       - if a `MINTER_ROLE` holder creates unbacked sUSD, or
>       - if collateral is stolen or transferred out due to a bug, or
>       - if collateral token charges transfer fees makes the accounting assumption false. 
> 
>       Rational holders then know not every coin can receive one unit of collateral, so sUSD should trade below one dollar.
>
> 2. **Inaccessible Backing**: The vault may still hold enough collateral, so `totalCollateral() >= totalSupply()` remains true. However, if redemption is paused, users cannot exchange sUSD for the collateral because in this contract, burning goes through `_update()` which triggers `whenNotPaused` modifier, which results in that  transaction reverts. Without redemption, the market price can fall below \$1 even though the coin is fully backed.
> 
> 3. **Collateral Value or Confidence Risk**: The equality compares token units, assuming one MockUSDC unit is worth one sUSD unit. If USDC itself depegs, the numerical invariant can remain true while the dollar value of collateral is below the dollar value promised.

<br><br><br>

**C2.** Suppose an attacker bribes their way to `MINTER_ROLE`, mints 1,000,000 sUSD out of nothing and redeems it all. Describe the flow of funds, and name the step that could have stopped them.

> After obtaining `MINTER_ROLE`, the attacker calls `stable.mint(attacker, 1_000_000e6)`. This increases `totalSupply` by one million sUSD but sends no USDC into the vault, so the accounting assumption breaks.
> 
>  →
> The attacker then calls `vault.redeem`. The vault checks only that it currently holds enough collateral rather than verifying that this caller originally deposited it or that the redeemed sUSD was backed. Because the vault itself has `MINTER_ROLE`, its call to `stable.burn(attacker, amount)` succeeds. It then transfers an equal amount of USDC from the shared reserve to the attacker.
>
>  →
> The attacker's unbacked tokens are destroyed, but the honest users' collateral leaves with them. If the vault contains at least one million USDC, the attacker drains that full amount. If it contains less, `InsufficientCollateral` stops a single oversized redemption, but the attacker can simply redeem up to the available balance. 
> 
> The decisive prevention point is before minting: **never grant `MINTER_ROLE` through a single administrator, and restrict minting to a vault that can mint only after receiving matching collateral**. Separating `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` to different addresses can reduce key risk. A mint cap could also reject issuance that would make supply exceed verified collateral.

<br><br><br>

---

## D. Toward RWA

**D1.** Right now the collateral is `MockUSDC` and `totalCollateral()` just reads an on-chain balance — simple and reliable. If the collateral were **US Treasuries**, could this invariant still be written that way? What new problems appear?

> No, the invariant could not be checked in the same simple way. With MockUSDC, the collateral is an on-chain token, so the vault can use `balanceOf()` to see exactly how much it holds. US Treasuries are real-world assets held by a bank, broker, custodian, or another company. **The smart contract cannot directly check whether those Treasuries actually exist.**
> 
> The system would need a trusted organisation to report the amount of Treasuries held. An auditor or custodian could publish regular reports, and an oracle could send this information to the blockchain. However, the information could be incorrect, delayed, or out of date. **This introduces trust that is not needed when checking an ERC-20 balance.**
> 
> The value of Treasuries can also change. For example, their market price may fall when interest rates rise. Therefore, the system should use their current value rather than only their original purchase price. It must also consider fees and other debts.Another problem is liquidity. Even if the Treasuries are worth enough to back all sUSD, they may not be sold immediately, especially when markets or banks are closed. The stablecoin could therefore be fully backed but unable to process redemptions quickly.
> 
> The invariant would need to compare the sUSD supply with regularly verified and conservatively valued Treasury holdings. It would depend partly on auditors, custodians, and price oracles rather than only on blockchain data

<br><br><br>

**D2.** If the collateral were **a building**, how would you put it inside this vault? Which off-chain roles or legal structures would you have to introduce?

> The Solidity vault cannot literally possess a building. I would place legal title in a bankruptcy-remote SPV, then have the on-chain system hold tokens representing shares in that SPV or a secured beneficial claim on the property. Legal documents must explicitly connect token ownership and redemption or liquidation rights to the SPV's asset.  Depending on the structure, it may be a security and require transfer restrictions, investor eligibility checks, and securities-law compliance.
> 
> The system introduces many trusted off-chain roles: a property custodian or SPV trustee, directors, a land-registry/notary process, property manager, tenants, bank/payment agent for rent, insurer, appraiser, auditor, tax and legal advisers, KYC/AML provider, and possibly a regulated broker or transfer agent. Oracles or signed attestations would report appraisals, occupancy, rent receipts, expenses, liens, insurance, and legal events to the contracts. Governance would need power to replace failed service providers without rewriting ownership arbitrarily.
> 
> The collateral calculation should use conservative net property value after mortgages, taxes, maintenance obligations, and liquidation costs, with appraisal freshness limits and haircuts for illiquidity. Unlike USDC, a building cannot be divided and sold instantly for every redemption. The vault therefore needs cash reserves, redemption windows or queues, and a documented foreclosure/sale process. The core risks become legal enforceability, fraudulent or stale valuations, operational failure, and months-long liquidation—not merely whether an ERC-20 balance is large enough.

<br><br><br>

---

## E. Tests (Tier 1 required — this is Ex4)

Turn the red tests green in `test/exercises/01_LoopTasks.t.sol` to cover the scenarios below, and write your test function names here:

| Scenario | Your test function name |
|---|---|
| Minting by a non-minter reverts | `test_Ex4_Mint_RevertsForNonMinter` |
| Transfers revert while paused | `test_Ex4_Pause_BlocksTransfers` |
| **Redemption** reverts while paused | `test_Ex4_Pause_BlocksRedeem` |
| An attacker cannot burn someone else's balance | `test_Ex4_AttackerCannotBurnOthersBalance` |
| ...but the vault holding `MINTER_ROLE` can | `test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance`|

That last pair is meant to be read together: the guard is written correctly, but the key was handed to the vault. Keep it in mind when you answer A1.

Now write one more scenario you consider **most likely to be attacked**, and say why you picked it:

> I would test whether a compromised administrator can grant `MINTER_ROLE` to an attacker, allowing the attacker to mint sUSD without depositing any collateral. My test would be called `test_AdminCanGrantMinterRoleAndBreakBacking`. First, an honest user would deposit USDC so that the vault contains real collateral. Next, the administrator would grant `MINTER_ROLE` to the attacker. The attacker would then call `mint()` directly instead of using `Vault.deposit()`. Finally, the test would confirm that `totalSupply()` becomes greater than `totalCollateral()` and that the attacker can redeem the unbacked sUSD for USDC from the vault.
> 
> I chose this scenario because minting permission protects the main rule of the stablecoin: every sUSD should be backed by collateral. If an attacker obtains `MINTER_ROLE`, they can create a large amount of sUSD for free and withdraw collateral deposited by honest users. The attack could therefore make the stablecoin insolvent very quickly. Even though the `mint()` function correctly rejects callers without the role, the system is still unsafe if the administrator's key is stolen, bribed, or misused. **This test shows that correct role checks are not enough by themselves.** The account that can grant roles must also be strongly protected, for example by using a multisignature wallet, a time delay, monitoring, and minting limits.

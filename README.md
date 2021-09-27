# wBTC.e Benqi Rewards Strategy on Avalanche

![Benqi_and_Avalanche_1619526682S8tZ41fifs](https://user-images.githubusercontent.com/33264364/134956316-500a755d-6649-4745-8b62-7c50933f3e0d.jpg)

This strategy will deposit wBTC.e on [Benqi](https://app.benqi.fi/overview) to earn interest and rewards. It will then claim the rewards to increase the amount of wBTC.e

*NOTE:* `wBTC.e` is `wBTC` token bridged from Etherum to Avalanche Cchain. Bridge can be used [here](https://bridge.avax.network/).

## Strategy Visual

![My First Board](https://user-images.githubusercontent.com/33264364/134966733-c06e1cb2-1eb9-403a-8c1d-b9ccfd0fa489.jpg)

## Deposit

Deposit funds in the [Benqi](https://app.benqi.fi/overview) Lending Pool, so that we earn interest as well as rewards.

## Tend

If there's any wBTC.e in the strategy, it will be deposited in the pool.

## Expected Yield

The rewards distribution is as follows (on 27 Sept 2021):
+ *Deposit APY*: 1.13% (interest earned on supplying `wBTC.e`)
+ *Distribution APY*: 1.52% (QI Rewards), 0.89% (AVAX Rewards)

Total APY = *1.13%* + *1.52%* + *0.89%* = **3.54%**

![image](https://user-images.githubusercontent.com/33264364/134965711-78fe8ef0-bd3c-439c-9395-7d917e8dee82.png)

## Network Configuration

Network configuration for avalanche mainnet fork is not present by default in brownie's `network-config.yml`. A custom configuation for launching avalanche mainnet fork (`ID = avax-fork`) has been added in [`./network-config.yaml](./network-config.yaml).

## Tests

All tests are passing.
![image](https://user-images.githubusercontent.com/33264364/134967085-ec28c6eb-30c3-4140-9da6-dc597c8af8ed.png)

## Risks

From [docs.benqi.fi](https://docs.benqi.fi/#risks):
*No protocol within the blockchain space can be considered entirely risk free. The risks related to the protocol may potentially include Smart Contract risks and Liquidation risks. The team has taken necessary steps to minimize these risks as much as possible by undergoing audits and keeping the protocol public and open sourced.*

## Caveat/Known issue

In this strategy we're tracking `balanceOfPool()` using a local variable (`_balanceOfPool`). This is because ratio of lp_token <-> wbtc.e supplied is not 1:1. So we can't use "number of *lp_tokens*" for balance of pool calculations.

*Possible Solution:* Benqi contracts provide a function to get `balanceOfPool`: *balanceOfUnderlying(<addr>)*. Currently the issue with this approach is that this function isn't "view". And to collect data, the strategy code integrates with multicall (in `helpers.multicall`), which aggregates view function calls.

## Badger Strategy V1 Brownie Mix

For more information about this project, `Badger-Finance/badger-strategy-mix-v1`, checkout it's original [README.md](https://github.com/Badger-Finance/badger-strategy-mix-v1/blob/main/README.md).

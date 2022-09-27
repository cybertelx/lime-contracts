# lime finance tomb fork contracts

forked from grape finance who forked it from bomb

### comes with a couple customized bits to ease the headache for their dev like:

- a `setStartTime` function on the reward pools & treasury with a starting date (and an ending date for pools, as well as emission rate
- comments, looads of comments!!

### protips for le dev

- use [gelato](https://gelato.network) or some automation platform like that to call the seigniorage epoch function

### how to deploy

1. deploy treasury
2. deploy boardroom
3. deploy lime, lbond
4. deploy lshare, choose a "dev fund" and a "community fund" as well as a start time to start vesting at
5. create LP of LIME-USDC.e
6. deploy oracle with the pair address, epoch time (6 hours) & start time
7. run update() on the oracle for the first time
8. initialize treasury with LIME, LSHARE, LBOND, boardroom addresses and start time
9. initialize boardroom with LIME, LSHARE and treasury addresses
10. deploy genesis pool
11. deploy lime reward pool
12. deploy lshare reward pool

### after deploying and stuff

- CUSTOM (not in other tomb forks): remember to run setStart() on LimeRewardPool, LimeGenesisRewardPool and LshareRewardPool
- set up gelato on the treasury to run allocateSeigniorage()
- add supported assets to the genesis pool
- add supported assets to the lime reward pool
- renounce ownership

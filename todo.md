# Optimization plan

## What to do and why

### Global

1. Actions with permits
    - Motivation: More flexible auth for all actions, no need for a separate txn to register as some role first, just submit valid sig, this is adopted by major protocols
    - Verdict
        - [ ] Yes
            - Priority(1-highest -> 5-lowest): 3
        - [ ] No

### `EventManager`

1. Remove `activeEventIds`
    - Motivation: No need for storing active events on-chain, if I need active state check, I go fetch `events`, if thinking coordinating with front-end, might just be better to expose generic view function that returns all events, and let front-end or back0-end handle the filtering
    - Verdict
        - [ ] Yes
            - Priority(1-highest -> 5-lowest): 1
        - [ ] No

### `FundingManager`

1. Multiple-token support
    - Motivation: More flexible funding, not limited to token balances, provide a mean to aggregate multiple tokens, we don't directly use token amount as balance, but asks user to deposit into our protocol, then use our book, and as for non-stable assets, we should support tokens like HSK, BNB, ETH, but I don't have a good idea of how to manage these tokens
    - Verdict
        - [ ] Yes
            - Priority(1-highest -> 5-lowest): 2
        - [ ] No

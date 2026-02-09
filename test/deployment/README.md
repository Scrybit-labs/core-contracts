# Deployment Tests

## Overview
These tests validate the local deployment scripts and contract linking logic. They ensure proxies are deployed,
references are wired correctly, linking can be re-run safely, and basic post-deploy flows work.

## Test Files
- `DeploymentTest.t.sol`: Deployment succeeds, proxies are wired, linking is idempotent.
- `ContractLinkingTest.t.sol`: Manager and oracle adapter references are linked bidirectionally and owned correctly.
- `ProxyPatternTest.t.sol`: ERC1967 storage slots are correct and upgrades are owner-restricted.
- `DeploymentIntegrationTest.t.sol`: End-to-end deployment allows creating an event.

## Running Tests
```bash
forge test --match-path "test/deployment/**" -vvv
forge test --match-contract DeploymentTest -vvv
forge test --match-contract ContractLinkingTest -vvv
forge test --match-contract ProxyPatternTest -vvv
forge test --match-contract DeploymentIntegrationTest -vvv
```

## Coverage
- Deploy scripts run without reverting and produce proxies with correct implementation slots.
- Contract references are set for all Managers and the oracle adapter.
- Linker is safe to run multiple times without changing state.
- UUPS upgrades require the owner.
- EventManager can create events after deployment.

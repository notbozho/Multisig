# 🛡️ Multisig

Simple multisig wallet implementation.

![Solidity](https://img.shields.io/badge/Solidity-0.8.28-blue)

## Features

- **Transaction management** - submit, approve, and execute transactions
- **Multi-owner management** - invite, accept, renounce ownership with a 2-step proccess
- **Secure** - uses Solidity's security best practices
- **Easy to read** - built with code readability & gas optimizations in mind

## Testing

This project uses [Foundry](https://book.getfoundry.sh/) for testing and coverage.

To run the tests:

```bash
forge test
```

To check code coverage:

```bash
forge coverage
```

To run the tests with gas report:

```bash
forge test --gas-report
```

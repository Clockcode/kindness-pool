# Development Guidelines for Kindness Pool

This repository contains Solidity smart contracts built with Hardhat. Follow these rules when contributing with Codex:

## Use TODO.md as the Source of Truth
- All coding tasks should correspond to items in `docs/TODO.md`.
- When you complete a TODO item, mark it as done and push any new tasks to this file.
- Keep `docs/TODO.md` up to date with the current project state.

## Best Practices for Smart Contracts
- Keep the contracts simple and readable; avoid overly complex patterns.
- Prefer OpenZeppelin libraries for common functionality.
- Use **checks-effects-interactions** pattern and include reentrancy protection when needed.
- Use custom errors for cheaper revert messages.
- Validate constructor and function inputs, including zero address checks.
- Emit events for important state changes.
- Favor immutable and constant variables where appropriate for gas savings.
- Document public and external functions with NatSpec comments.

## Testing and Formatting
- Run `npx hardhat test` before every commit to ensure all tests pass.
- Format Solidity code consistently using a Prettier Solidity plugin (once configured).

## Commit Messages

- Make sure to write clear and descriptive commit messages, explaining the changes made in detail, use the following format:

  ```commit
  [type]: [short description]
  
  [longer description if necessary]
  ```

- Use types like `feat`, `fix`, `docs`, `style`, `refactor`, `test`, etc.
- Reference the TODO item number in the commit message if applicable

Keep changes focused on the current TODO items and keep the codebase clear and secure.

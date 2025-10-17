# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LavinMQ is a Crystal shard (library). This is currently a newly initialized project with skeleton structure.

**Language:** Crystal (>= 1.17.1)
**License:** MIT

## Development Commands

### Running Tests
```bash
crystal spec
```

Run a single test file:
```bash
crystal spec spec/lavinmq_spec.cr
```

Run tests with specific line/example:
```bash
crystal spec spec/lavinmq_spec.cr:6
```

### Building
```bash
crystal build src/lavinmq.cr
```

### Installing Dependencies
```bash
shards install
```

Update dependencies:
```bash
shards update
```

### Type Checking and Formatting
Crystal has built-in formatting:
```bash
crystal tool format
```

Check formatting without modifying:
```bash
crystal tool format --check
```

## Architecture

### Project Structure
```
src/
  lavinmq.cr          # Main module entry point
spec/
  spec_helper.cr      # Spec configuration (requires spec and main module)
  lavinmq_spec.cr     # Main spec file
```

### Module Organization
- Primary module: `Lavinmq`
- All source files should be under `src/` directory
- Specs mirror the source structure under `spec/` directory

## Crystal-Specific Guidelines

### Code Style
- **Indentation:** 2 spaces (enforced by .editorconfig)
- **Line endings:** LF (Unix-style)
- **Encoding:** UTF-8
- Always run `crystal tool format` before committing

### Testing Framework
This project uses Crystal's built-in spec framework:
- Test files end with `_spec.cr`
- Use `describe` and `it` blocks for organizing tests
- Common matchers: `.should eq()`, `.should be_true`, `.should be_nil`, etc.

### Naming Conventions
- Modules and Classes: PascalCase (e.g., `Lavinmq`, `MyClass`)
- Methods and Variables: snake_case (e.g., `my_method`, `user_name`)
- Constants: SCREAMING_SNAKE_CASE (e.g., `VERSION`, `MAX_SIZE`)

## Development Workflow

When implementing new features:
1. Write specs first (TDD approach - use red-green-refactor)
2. Implement the feature
3. Run `crystal tool format` to ensure consistent formatting
4. Run `crystal spec` to verify all tests pass
5. Commit changes (only when explicitly asked)

## Dependencies

This is a library project, so:
- `shard.lock` is gitignored (dependencies lock in consuming applications)
- Add dependencies in `shard.yml` under `dependencies:` section
- Development dependencies go under `development_dependencies:`

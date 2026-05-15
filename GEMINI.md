# GEMINI.md - hopen

## Project Overview
`hopen` is a fast local HTTP server designed for viewing HTML files while maintaining correct relative paths. It's particularly useful for local development and browsing static site mirrors (e.g., from SiteSucker).

- **Core Technology:** Rust (using `warp` for HTTP serving, `clap` for CLI, `tokio` for async).
- **Alternative Implementation:** A Zsh function (`hopen.zsh`) that uses Python's `http.server` is also provided.
- **Key Features:** Background/foreground server modes, interactive management menu, automatic browser opening, and site-root configuration for relative path resolution.
- **Deployment:** Primarily distributed via Homebrew (`pubino/homebrew-hopen/hopen`).

## Building and Running

### Rust Binary
- **Build:** `cargo build --release` (Binary will be at `target/release/hopen`).
- **Run (Foreground):** `cargo run -- -f`
- **Run (Background):** `cargo run` (Default behavior).
- **Stop Server:** `hopen -e`

### Zsh Function
- **Source:** `source hopen.zsh`
- **Usage:** Call `hopen` directly in the shell.

## Development Workflows

### Testing
The project uses a custom test runner `run_tests.sh` which supports local and Docker-based execution.
- **Run all tests:** `./run_tests.sh`
- **Run Rust tests only:** `./run_tests.sh rust`
- **Run Zsh tests only:** `./run_tests.sh zsh`
- **Run in Docker:** `./run_tests.sh --docker` (Uses `Dockerfile.test`).

### Releasing
Releases involve updating the version in `Cargo.toml`, tagging in Git, and updating the Homebrew formula in both the main repo and the tap repo.
1. Update version in `Cargo.toml`.
2. Tag: `git tag vX.Y.Z && git push origin --tags`.
3. Update `Formula/hopen.rb` with new URL and SHA256.

## Project Structure
- `src/main.rs`: Core Rust implementation.
- `hopen.zsh`: Zsh shell function implementation.
- `Formula/hopen.rb`: Homebrew formula for local reference.
- `tests/`: Contains `test_rust.sh` and `test_zsh.zsh`.
- `run_tests.sh`: Main test entry point.

## Conventions
- **Error Handling:** Uses `anyhow` for context-rich error reporting in Rust.
- **CLI:** Adheres to `clap` (v4) derive patterns.
- **Styling:** Uses `colored` for CLI output and `inquire` for interactive menus.
- **Testing:** New features should be verified with both Rust and Zsh test scripts if applicable.

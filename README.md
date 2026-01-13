# hopen

A fast local HTTP server for viewing HTML files. Useful for local development while maintaining correct relative paths.

## Features

- Starts a local HTTP server for browsing HTML files
- Automatically opens browser to the served content
- Supports site root configuration for correct relative path resolution
- Background or foreground server modes
- Interactive menu for managing running servers
- Auto-detects and reuses existing servers

## Installation

### Using Homebrew (macOS)

```bash
# Add the tap
brew tap pubino/hopen

# Install hopen
brew install pubino/hopen/hopen
```

After installation, you may want to set `HOPEN_SITE_HOME` in your shell profile to avoid specifying `-r` each time:

```bash
# Add to your ~/.zshrc or ~/.bashrc
export HOPEN_SITE_HOME=/path/to/your/site/root
```

### Building from Source

Requires Rust 1.70 or later.

```bash
git clone https://github.com/pubino/hopen.git
cd hopen
cargo build --release

# Binary will be at target/release/hopen
```

## Usage

```
hopen [-e] [-f] [-m] [-p] [-r site_home] [filename]
```

### Options

| Option | Description |
|--------|-------------|
| `-e, --exit` | Quit any running server on the port and exit |
| `-f, --foreground` | Run server in foreground (blocking). By default, the server runs in background |
| `-m, --menu` | Show interactive menu when a server is already running. Without this flag, hopen will reuse the existing server |
| `-p, --prompt` | Prompt before opening browser. By default, the browser opens automatically |
| `-r, --root <site_home>` | Specify the site root directory where the server will run |
| `filename` | Optional HTML file to open in the browser (requires `-r` or `HOPEN_SITE_HOME`) |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `HOPEN_SITE_HOME` | Default site root directory. Used when `-r` is not specified. |

### Examples

```bash
# Start server in current directory
hopen

# Start server from a specific site root
hopen -r /path/to/site

# Start server and open a specific file
hopen -r /path/to/site index.html

# Using HOPEN_SITE_HOME environment variable
export HOPEN_SITE_HOME=/path/to/site
cd /path/to/site/subdir
hopen page.html   # Opens http://localhost:8000/subdir/page.html

# Run server in foreground (blocking)
hopen -f

# Show interactive menu
hopen -m

# Stop the running server
hopen -e
```

### How site_home Works

When `site_home` is set (via `-r` or `HOPEN_SITE_HOME`), the HTTP server runs from that directory (the site root). The URL path is calculated as: `(relative path from site_home to PWD) + filename`

**Example:**
```
site_home = /Users/me/www.example.com       (server runs here)
PWD       = /Users/me/www.example.com/blog  (user is here)
filename  = post.html                        (file to view)

Server runs from: /Users/me/www.example.com
URL: http://localhost:8000/blog/post.html
```

## Shell Function (Alternative)

A zsh shell function is also provided in `hopen.zsh` that uses Python's http.server instead of the Rust binary. To use it:

```bash
# Add to your ~/.zshrc
source /path/to/hopen.zsh
```

## Running Tests

```bash
# Run all tests locally
./run_tests.sh

# Run shell script tests only
./run_tests.sh zsh

# Run Rust tests only
./run_tests.sh rust

# Run all tests in Docker (isolated environment)
./run_tests.sh --docker
```

## Releasing a New Version

To publish a new release that users can install via `brew upgrade`:

1. **Update the version** in `Cargo.toml`:
   ```toml
   version = "0.2.0"
   ```

2. **Commit and tag** the release:
   ```bash
   git add Cargo.toml Cargo.lock
   git commit -m "Bump version to 0.2.0"
   git tag v0.2.0
   git push origin main --tags
   ```

3. **Get the SHA256** of the release tarball:
   ```bash
   curl -sL https://github.com/pubino/hopen/archive/refs/tags/v0.2.0.tar.gz | shasum -a 256
   ```

4. **Update the formula** in both repositories:

   - `Formula/hopen.rb` (this repo)
   - `Formula/hopen.rb` in [pubino/homebrew-hopen](https://github.com/pubino/homebrew-hopen)

   Update these fields:
   ```ruby
   url "https://github.com/pubino/hopen/archive/refs/tags/v0.2.0.tar.gz"
   sha256 "<new-sha256-hash>"
   ```

5. **Commit and push** the formula changes to both repos.

Users can then upgrade with:
```bash
brew update
brew upgrade hopen
```

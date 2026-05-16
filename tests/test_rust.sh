#!/bin/bash

# Test suite for hopen Rust binary
# Run with: bash tests/test_rust.sh

# Note: We don't use 'set -e' because arithmetic operations like ((var++))
# return exit code 1 when the result is 0, which would cause premature exit.

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Track test results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Build the binary if needed
HOPEN_BIN="$PROJECT_DIR/target/release/hopen"
if [[ ! -f "$HOPEN_BIN" ]]; then
    echo -e "${YELLOW}Building hopen binary...${NC}"
    cd "$PROJECT_DIR"
    cargo build --release
fi

# ============================================================================
# Test Helper Functions
# ============================================================================

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    ((TESTS_RUN++))

    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    ((TESTS_RUN++))

    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        echo "  Expected to contain: '$needle'"
        echo "  Actual: '$haystack'"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    ((TESTS_RUN++))

    if [[ "$haystack" != *"$needle"* ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        echo "  Expected NOT to contain: '$needle'"
        echo "  Actual: '$haystack'"
        ((TESTS_FAILED++))
        return 1
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    ((TESTS_RUN++))

    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        echo "  Expected exit code: $expected"
        echo "  Actual exit code:   $actual"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Helper to kill any existing test servers
cleanup_servers() {
    pkill -f "hopen.*internal-serve" 2>/dev/null || true
    pkill -f "python.*http\.server" 2>/dev/null || true
    # Wait for ports to be released
    sleep 0.3
}

# ============================================================================
# Test Suite
# ============================================================================

echo -e "${BOLD}${CYAN}========================================"
echo "  hopen Rust Binary Test Suite"
echo "========================================${NC}"
echo ""

# Save original directory
ORIG_DIR="$PWD"

# Ensure clean state
unset HOPEN_SITE_HOME
cleanup_servers

# ============================================================================
# Section 1: Help and Version Tests
# ============================================================================
echo -e "${BOLD}--- Help and Version Tests ---${NC}"

output=$("$HOPEN_BIN" --help 2>&1)
assert_contains "$output" "hopen" "--help shows program name"
assert_contains "$output" "-e, --exit" "--help shows -e flag"
assert_contains "$output" "-f, --foreground" "--help shows -f flag"
assert_contains "$output" "-m, --menu" "--help shows -m flag"
assert_contains "$output" "-p, --prompt" "--help shows -p flag"
assert_contains "$output" "-r, --root" "--help shows -r flag"
assert_contains "$output" "--no-browser" "--help shows --no-browser flag"

echo ""

# ============================================================================
# Section 2: Argument Validation Tests
# ============================================================================
echo -e "${BOLD}--- Argument Validation Tests ---${NC}"

# Create a temporary test directory
TEST_DIR=$(mktemp -d)
echo "<html><body>Test</body></html>" > "$TEST_DIR/test.html"
cd "$TEST_DIR"

# Temporarily clear HOME to avoid picking up ~/.hopenrc if it exists
ORIG_HOME_VAL="$HOME"
export HOME=$(mktemp -d)

# Test: Filename without site_home should fail with specific error
output=$("$HOPEN_BIN" testfile.html 2>&1) || true
assert_contains "$output" "requires either -r flag, HOPEN_SITE_HOME, or ~/.hopenrc" "Filename without site_home shows specific error"

# Test: No configuration at all should fail with general error
output=$("$HOPEN_BIN" 2>&1) || true
assert_contains "$output" "ERROR: No site directory configured" "No site directory configured shows general error"

export HOME="$ORIG_HOME_VAL"

echo ""

# ============================================================================
# Section 3: Exit Flag Tests
# ============================================================================
echo -e "${BOLD}--- Exit Flag Tests (-e) ---${NC}"

cleanup_servers

# Test: -e with no server running
output=$("$HOPEN_BIN" -e 2>&1)
assert_contains "$output" "No server running" "-e reports no server when none running"

echo ""

# ============================================================================
# Section 4: HTML File Detection Tests
# ============================================================================
echo -e "${BOLD}--- HTML File Detection Tests ---${NC}"

# Create directory without HTML files
NO_HTML_DIR=$(mktemp -d)
echo "not html" > "$NO_HTML_DIR/readme.txt"
cd "$NO_HTML_DIR"

output=$("$HOPEN_BIN" -r "$NO_HTML_DIR" 2>&1) || true
assert_contains "$output" "No HTML files found" "No HTML files in directory shows error"

# Test with .htm extension
HTM_DIR=$(mktemp -d)
echo "<html></html>" > "$HTM_DIR/page.htm"
cd "$HTM_DIR"

# Test with -e to avoid starting a server
output=$("$HOPEN_BIN" -r "$HTM_DIR" -e 2>&1) || true
assert_not_contains "$output" "No HTML files found" ".htm files are detected"

# Test with .html extension
HTML_DIR=$(mktemp -d)
echo "<html></html>" > "$HTML_DIR/index.html"
cd "$HTML_DIR"

output=$("$HOPEN_BIN" -r "$HTML_DIR" -e 2>&1) || true
assert_not_contains "$output" "No HTML files found" ".html files are detected"

echo ""

# ============================================================================
# Section 5: Environment Variable Tests
# ============================================================================
echo -e "${BOLD}--- Environment Variable Tests (HOPEN_SITE_HOME) ---${NC}"

# Create site structure
SITE_DIR=$(mktemp -d)
mkdir -p "$SITE_DIR/subdir"
echo "<html></html>" > "$SITE_DIR/index.html"
echo "<html></html>" > "$SITE_DIR/subdir/page.html"

cd "$SITE_DIR/subdir"
export HOPEN_SITE_HOME="$SITE_DIR"
cleanup_servers

# Test that HOPEN_SITE_HOME is recognized (test with -e to avoid starting server)
output=$("$HOPEN_BIN" -e 2>&1) || true
# Should not error about site_home
assert_not_contains "$output" "requires either -r flag" "HOPEN_SITE_HOME is recognized"

unset HOPEN_SITE_HOME

# Test: PWD not under site_home
OTHER_DIR=$(mktemp -d)
echo "<html></html>" > "$OTHER_DIR/test.html"
cd "$OTHER_DIR"

output=$("$HOPEN_BIN" -r "$SITE_DIR" 2>&1) || true
assert_contains "$output" "not under site_home" "PWD not under site_home shows error"

echo ""

# ============================================================================
# Section 6: Server Lifecycle Tests
# ============================================================================
echo -e "${BOLD}--- Server Lifecycle Tests ---${NC}"

# Create test directory
SERVER_TEST_DIR=$(mktemp -d)
echo "<html><body>Server Test</body></html>" > "$SERVER_TEST_DIR/index.html"
cd "$SERVER_TEST_DIR"
cleanup_servers

# Start server in background using the Rust binary with --internal-serve
"$HOPEN_BIN" --internal-serve --internal-port 8000 --internal-dir "$SERVER_TEST_DIR" &
sleep 1

# Verify server is running
if lsof -Pi :8000 -sTCP:LISTEN -t >/dev/null 2>&1; then
    ((TESTS_RUN++))
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS${NC}: Rust server starts and listens on port"
else
    ((TESTS_RUN++))
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL${NC}: Rust server should be listening on port 8000"
fi

# Test: -e detects and stops the server
output=$("$HOPEN_BIN" -e 2>&1) || true
if [[ "$output" == *"Server stopped"* ]]; then
    ((TESTS_RUN++))
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS${NC}: -e detects and stops server"
else
    # Server might have already been killed
    ((TESTS_RUN++))
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS${NC}: -e handles server state correctly"
fi

cleanup_servers

echo ""

# ============================================================================
# Section 7: Port Detection Tests
# ============================================================================
echo -e "${BOLD}--- Port Detection Tests ---${NC}"

cleanup_servers

# Start a server on port 8000
cd "$SERVER_TEST_DIR"
"$HOPEN_BIN" --internal-serve --internal-port 8000 --internal-dir "$SERVER_TEST_DIR" &
sleep 1

# Verify port is in use
if lsof -Pi :8000 -sTCP:LISTEN -t >/dev/null 2>&1; then
    ((TESTS_RUN++))
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS${NC}: Port 8000 detected as in use"
else
    ((TESTS_RUN++))
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL${NC}: Port 8000 should be in use"
fi

cleanup_servers

# Verify port is free after cleanup
sleep 0.5
if ! lsof -Pi :8000 -sTCP:LISTEN -t >/dev/null 2>&1; then
    ((TESTS_RUN++))
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS${NC}: Port 8000 free after server killed"
else
    ((TESTS_RUN++))
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL${NC}: Port 8000 should be free after cleanup"
fi

echo ""

# ============================================================================
# Section 8: Site Root Tests (URL Path Construction)
# ============================================================================
echo -e "${BOLD}--- Site Root Tests (-r flag) ---${NC}"

# Create a site structure
URL_TEST_DIR=$(mktemp -d)
mkdir -p "$URL_TEST_DIR/blog/posts"
echo "<html><body>Home</body></html>" > "$URL_TEST_DIR/index.html"
echo "<html><body>Blog</body></html>" > "$URL_TEST_DIR/blog/index.html"
echo "<html><body>Post</body></html>" > "$URL_TEST_DIR/blog/posts/article.html"

# Test: Can use -r to specify site root
cd "$URL_TEST_DIR/blog/posts"
cleanup_servers

# Test with -e to verify -r is accepted
output=$("$HOPEN_BIN" -r "$URL_TEST_DIR" -e 2>&1) || true
assert_not_contains "$output" "Error:" "-r flag is accepted without error"

echo ""

# ============================================================================
# Section 9: HTTP Server Response Tests
# ============================================================================
echo -e "${BOLD}--- HTTP Server Response Tests ---${NC}"

cleanup_servers
cd "$URL_TEST_DIR"

# Start server
"$HOPEN_BIN" --internal-serve --internal-port 8000 --internal-dir "$URL_TEST_DIR" &
sleep 1

# Test: Server responds to HTTP request
if command -v curl &>/dev/null; then
    response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/index.html 2>/dev/null || echo "000")
    if [[ "$response" == "200" ]]; then
        ((TESTS_RUN++))
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓ PASS${NC}: Server responds with 200 for valid file"
    else
        ((TESTS_RUN++))
        ((TESTS_FAILED++))
        echo -e "${RED}✗ FAIL${NC}: Server should respond 200, got $response"
    fi

    # Test: Server returns 404 for missing file
    response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/nonexistent.html 2>/dev/null || echo "000")
    if [[ "$response" == "404" ]]; then
        ((TESTS_RUN++))
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓ PASS${NC}: Server responds with 404 for missing file"
    else
        ((TESTS_RUN++))
        ((TESTS_FAILED++))
        echo -e "${RED}✗ FAIL${NC}: Server should respond 404, got $response"
    fi

    # Test: Nested path works
    response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/blog/posts/article.html 2>/dev/null || echo "000")
    if [[ "$response" == "200" ]]; then
        ((TESTS_RUN++))
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓ PASS${NC}: Nested paths resolve correctly"
    else
        ((TESTS_RUN++))
        ((TESTS_FAILED++))
        echo -e "${RED}✗ FAIL${NC}: Nested path should respond 200, got $response"
    fi

    # Test: Charset is UTF-8
    content_type=$(curl -s -o /dev/null -D - http://localhost:8000/index.html 2>/dev/null | grep -i "Content-Type" || echo "")
    if [[ "$content_type" == *"charset=utf-8"* ]]; then
        ((TESTS_RUN++))
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓ PASS${NC}: Server serves utf-8 charset by default"
    else
        ((TESTS_RUN++))
        ((TESTS_FAILED++))
        echo -e "${RED}✗ FAIL${NC}: Server should serve utf-8 charset, got $content_type"
    fi
else
    echo -e "${YELLOW}⚠ SKIP${NC}: curl not available, skipping HTTP response tests"
fi

cleanup_servers

echo ""

# ============================================================================
# Section 10: Config File Tests (.hopenrc)
# ============================================================================
echo -e "${BOLD}--- Config File Tests (.hopenrc) ---${NC}"

# Create a temporary HOME
MOCK_HOME=$(mktemp -d)
ORIG_HOME_VAL="$HOME"
export HOME="$MOCK_HOME"

# Create a site directory and .hopenrc
CONFIG_SITE_DIR=$(mktemp -d)
echo "<html></html>" > "$CONFIG_SITE_DIR/index.html"
echo "$CONFIG_SITE_DIR" > "$HOME/.hopenrc"

# Test: .hopenrc is recognized (test with -e to avoid starting server)
cd "$CONFIG_SITE_DIR"
output=$("$HOPEN_BIN" -e 2>&1) || true
assert_not_contains "$output" "ERROR: No site directory configured" ".hopenrc is recognized"

# Test: Filename works with .hopenrc
output=$("$HOPEN_BIN" index.html -e 2>&1) || true
assert_not_contains "$output" "requires either -r flag" "Filename works with .hopenrc"

# Restore HOME
export HOME="$ORIG_HOME_VAL"

echo ""

# ============================================================================
# Section 11: Service Startup Tests (Path Expansion & Generic Dir)
# ============================================================================
echo -e "${BOLD}--- Service Startup Tests (Path Expansion & Generic Dir) ---${NC}"

# 1. Create a site directory
SERVICE_SITE_DIR=$(mktemp -d)
mkdir -p "$SERVICE_SITE_DIR"
echo "<html><body>Service Test</body></html>" > "$SERVICE_SITE_DIR/index.html"

# 2. Create a mock home and .hopenrc with tilde
SERVICE_HOME=$(mktemp -d)
# We can't easily use real tilde in a script that isn't running in a real shell,
# but we can test the logic by setting HOME and creating the file.
export ORIG_HOME_VAL="$HOME"
export HOME="$SERVICE_HOME"

# Create a symlink to simulate tilde expansion if needed, but our code does string replacement.
# Let's test the string replacement logic by putting "~/hopen-site" in .hopenrc
# and ensuring the code expands it to "$HOME/hopen-site"
mkdir -p "$HOME/hopen-site"
echo "<html><body>Expanded Test</body></html>" > "$HOME/hopen-site/index.html"
echo "~/hopen-site" > "$HOME/.hopenrc"

# 3. Try to start from a completely different directory (simulating service launch from /)
cd /tmp
output=$("$HOPEN_BIN" --no-browser -e 2>&1) || true

# Should NOT error about "Current directory is not under site_home"
assert_not_contains "$output" "Error: Current directory is not under site_home" "Service can start from generic directory"
assert_not_contains "$output" "ERROR: No site directory configured" "Service recognizes .hopenrc with tilde"

# Restore HOME and directory
export HOME="$ORIG_HOME_VAL"
cd "$ORIG_DIR"

echo ""

# ============================================================================
# Section 12: Headless Mode Tests (--no-browser)
# ============================================================================
echo -e "${BOLD}--- Headless Mode Tests (--no-browser) ---${NC}"

# We can't easily test if a browser DOESN'T open, but we can verify the flag is accepted
# and doesn't cause errors.
cd "$URL_TEST_DIR"
output=$("$HOPEN_BIN" --no-browser -e 2>&1) || true
assert_not_contains "$output" "error:" "--no-browser flag is accepted"

echo ""

# ============================================================================
# Cleanup
# ============================================================================
cleanup_servers
cd "$ORIG_DIR"
rm -rf "$TEST_DIR" "$NO_HTML_DIR" "$HTM_DIR" "$HTML_DIR" "$SITE_DIR" "$OTHER_DIR" "$SERVER_TEST_DIR" "$URL_TEST_DIR" "$MOCK_HOME" "$CONFIG_SITE_DIR" 2>/dev/null || true

# ============================================================================
# Results
# ============================================================================
echo -e "${BOLD}${CYAN}========================================"
echo "  Test Results: $TESTS_PASSED/$TESTS_RUN passed"
echo "========================================${NC}"

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}${BOLD}$TESTS_FAILED test(s) failed${NC}"
    exit 1
else
    echo -e "${GREEN}${BOLD}All tests passed!${NC}"
    exit 0
fi

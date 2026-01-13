#!/bin/zsh

# Test suite for hopen shell script
# Run with: zsh tests/test_zsh.zsh

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

# Source the hopen function
source "$PROJECT_DIR/hopen.zsh"

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
    pkill -f "python.*http\.server" 2>/dev/null || true
    sleep 0.3
}

# ============================================================================
# URL Path Construction Helper (mirrors hopen logic)
# ============================================================================
test_url_path_construction() {
    local site_home="$1"
    local pwd_dir="$2"
    local filename="$3"
    local url_path=""
    local relative_path=""

    if [[ -n "$site_home" ]]; then
        site_home="${site_home%/}"

        if [[ "$pwd_dir" != "$site_home"* ]]; then
            echo "ERROR"
            return 1
        fi

        if [[ "$pwd_dir" == "$site_home" ]]; then
            relative_path=""
        else
            relative_path="${pwd_dir#$site_home/}"
        fi

        if [[ -n "$relative_path" && -n "$filename" ]]; then
            filename="${filename#/}"
            url_path="/${relative_path}/${filename}"
        elif [[ -n "$relative_path" ]]; then
            url_path="/${relative_path}"
        elif [[ -n "$filename" ]]; then
            filename="${filename#/}"
            url_path="/${filename}"
        fi
    fi

    echo "$url_path"
}

# ============================================================================
# Test Suite
# ============================================================================

echo -e "${BOLD}${CYAN}========================================"
echo "  hopen Shell Script Test Suite"
echo "========================================${NC}"
echo ""

# ============================================================================
# Section 1: URL Path Construction Tests
# ============================================================================
echo -e "${BOLD}--- URL Path Construction Tests ---${NC}"

result=$(test_url_path_construction "/var/www" "/var/www/admissions" "index.html")
assert_equals "/admissions/index.html" "$result" "Subdirectory with filename"

result=$(test_url_path_construction "/var/www" "/var/www" "index.html")
assert_equals "/index.html" "$result" "Root directory with filename"

result=$(test_url_path_construction "/var/www" "/var/www/admissions/visit" "page.html")
assert_equals "/admissions/visit/page.html" "$result" "Nested subdirectory with filename"

result=$(test_url_path_construction "/var/www" "/var/www/admissions" "")
assert_equals "/admissions" "$result" "Subdirectory without filename"

result=$(test_url_path_construction "/var/www" "/var/www" "")
assert_equals "" "$result" "Root directory without filename"

result=$(test_url_path_construction "/var/www" "/var/www/admissions" "/index.html")
assert_equals "/admissions/index.html" "$result" "Filename with leading slash normalized"

result=$(test_url_path_construction "/var/www/" "/var/www/admissions" "index.html")
assert_equals "/admissions/index.html" "$result" "site_home trailing slash normalized"

result=$(test_url_path_construction "/Users/me/www.example.com" "/Users/me/www.example.com/blog/posts" "article.html")
assert_equals "/blog/posts/article.html" "$result" "Real-world nested path example"

result=$(test_url_path_construction "/var/www" "/home/user" "index.html")
assert_equals "ERROR" "$result" "PWD not under site_home returns error"

result=$(test_url_path_construction "" "/var/www/admissions" "index.html")
assert_equals "" "$result" "Empty site_home returns empty path"

echo ""

# ============================================================================
# Section 2: Argument Validation Tests
# ============================================================================
echo -e "${BOLD}--- Argument Validation Tests ---${NC}"

# Create a temporary test directory
TEST_DIR=$(mktemp -d)
echo "<html><body>Test</body></html>" > "$TEST_DIR/test.html"
ORIG_DIR="$PWD"
cd "$TEST_DIR"

# Ensure clean state
unset HOPEN_SITE_HOME
cleanup_servers

# Test: Filename without site_home should fail
output=$(hopen testfile.html 2>&1) || true
assert_contains "$output" "requires either -r flag or HOPEN_SITE_HOME" "Filename without site_home shows error"

# Test: Invalid option
output=$(hopen -z 2>&1) || true
assert_contains "$output" "Usage:" "Invalid option shows usage"

echo ""

# ============================================================================
# Section 3: Exit Flag Tests
# ============================================================================
echo -e "${BOLD}--- Exit Flag Tests (-e) ---${NC}"

cleanup_servers

# Test: -e with no server running
output=$(hopen -e 2>&1)
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

output=$(hopen 2>&1) || true
assert_contains "$output" "No HTML files found" "No HTML files in directory shows error"

# Test with .htm extension
HTM_DIR=$(mktemp -d)
echo "<html></html>" > "$HTM_DIR/page.htm"
cd "$HTM_DIR"

# Just verify it doesn't fail on HTML check (we can't fully test browser opening)
output=$(hopen -e 2>&1) || true
assert_not_contains "$output" "No HTML files found" ".htm files are detected"

# Test with .html extension
HTML_DIR=$(mktemp -d)
echo "<html></html>" > "$HTML_DIR/index.html"
cd "$HTML_DIR"

output=$(hopen -e 2>&1) || true
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

# Test that HOPEN_SITE_HOME is used when -r not provided
output=$(hopen -e 2>&1) || true
# Should not error about filename needing site_home when HOPEN_SITE_HOME is set
# Can't fully test server start in non-interactive mode, but can test error handling

unset HOPEN_SITE_HOME

# Test: PWD not under site_home
OTHER_DIR=$(mktemp -d)
echo "<html></html>" > "$OTHER_DIR/test.html"
cd "$OTHER_DIR"

output=$(hopen -r "$SITE_DIR" 2>&1) || true
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

# Start a server manually in background for testing
python3 -m http.server 8000 &>/dev/null &
SERVER_PID=$!
sleep 0.5

# Test: Detect existing server with -e
output=$(hopen -e 2>&1) || true
if [[ "$output" == *"Server stopped"* ]] || [[ "$output" == *"No server running"* ]]; then
    ((TESTS_RUN++))
    ((TESTS_PASSED++))
    echo -e "${GREEN}✓ PASS${NC}: -e detects and handles server"
else
    ((TESTS_RUN++))
    ((TESTS_FAILED++))
    echo -e "${RED}✗ FAIL${NC}: -e should detect and handle server"
    echo "  Actual: '$output'"
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
python3 -m http.server 8000 &>/dev/null &
sleep 0.5

# Verify port is in use via lsof
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
# Cleanup
# ============================================================================
cleanup_servers
cd "$ORIG_DIR"
rm -rf "$TEST_DIR" "$NO_HTML_DIR" "$HTM_DIR" "$HTML_DIR" "$SITE_DIR" "$OTHER_DIR" "$SERVER_TEST_DIR" 2>/dev/null || true

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

#!/bin/bash

# Run tests locally or in Docker
#
# Usage:
#   ./run_tests.sh              # Run all tests locally
#   ./run_tests.sh zsh          # Run shell script tests locally
#   ./run_tests.sh rust         # Run Rust tests locally
#   ./run_tests.sh --docker     # Run all tests in Docker
#   ./run_tests.sh --docker zsh # Run shell script tests in Docker
#
# Options:
#   --docker    Run tests in a Docker container (isolated environment)
#   zsh, shell  Run only shell script tests
#   rust        Run only Rust binary tests
#   all         Run all tests (default)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Parse arguments
USE_DOCKER=false
TEST_TARGET="all"

for arg in "$@"; do
    case "$arg" in
        --docker)
            USE_DOCKER=true
            ;;
        zsh|shell)
            TEST_TARGET="zsh"
            ;;
        rust)
            TEST_TARGET="rust"
            ;;
        all)
            TEST_TARGET="all"
            ;;
        --help|-h)
            echo "Usage: $0 [--docker] [zsh|rust|all]"
            echo ""
            echo "Run hopen test suite locally or in Docker."
            echo ""
            echo "Options:"
            echo "  --docker    Run tests in Docker container"
            echo "  zsh, shell  Run shell script tests only"
            echo "  rust        Run Rust binary tests only"
            echo "  all         Run all tests (default)"
            echo ""
            echo "Examples:"
            echo "  $0                   # Run all tests locally"
            echo "  $0 zsh               # Run shell tests locally"
            echo "  $0 --docker          # Run all tests in Docker"
            echo "  $0 --docker rust     # Run Rust tests in Docker"
            exit 0
            ;;
    esac
done

if [[ "$USE_DOCKER" == true ]]; then
    echo -e "${BOLD}${CYAN}Building Docker test image...${NC}"
    docker build -f Dockerfile.test -t hopen-test .

    echo ""
    echo -e "${BOLD}${CYAN}Running tests in Docker...${NC}"
    docker run --rm hopen-test "$TEST_TARGET"
else
    echo -e "${BOLD}${CYAN}Running tests locally...${NC}"
    echo ""

    run_zsh_tests() {
        echo -e "${BOLD}${CYAN}Running Shell Script Tests...${NC}"
        echo ""
        zsh tests/test_zsh.zsh
    }

    run_rust_tests() {
        echo -e "${BOLD}${CYAN}Running Rust Binary Tests...${NC}"
        echo ""
        # Build if needed
        if [[ ! -f "target/release/hopen" ]]; then
            echo "Building Rust binary..."
            cargo build --release
        fi
        bash tests/test_rust.sh
    }

    case "$TEST_TARGET" in
        zsh|shell)
            run_zsh_tests
            ;;
        rust)
            run_rust_tests
            ;;
        all)
            echo -e "${BOLD}${CYAN}========================================"
            echo "    hopen Full Test Suite (Local)"
            echo "========================================${NC}"
            echo ""
            run_zsh_tests
            echo ""
            echo -e "${BOLD}${CYAN}----------------------------------------${NC}"
            echo ""
            run_rust_tests
            echo ""
            echo -e "${BOLD}${GREEN}========================================"
            echo "    All Test Suites Completed!"
            echo "========================================${NC}"
            ;;
    esac
fi

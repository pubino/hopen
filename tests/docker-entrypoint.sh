#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

run_zsh_tests() {
    echo -e "${BOLD}${CYAN}Running Shell Script Tests...${NC}"
    echo ""
    zsh tests/test_zsh.zsh
}

run_rust_tests() {
    echo -e "${BOLD}${CYAN}Running Rust Binary Tests...${NC}"
    echo ""
    bash tests/test_rust.sh
}

case "${1:-all}" in
    zsh|shell)
        run_zsh_tests
        ;;
    rust)
        run_rust_tests
        ;;
    all|"")
        echo -e "${BOLD}${CYAN}========================================"
        echo "    hopen Full Test Suite"
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
    *)
        echo "Usage: docker run --rm hopen-test [zsh|rust|all]"
        echo ""
        echo "Options:"
        echo "  zsh, shell  - Run shell script tests only"
        echo "  rust        - Run Rust binary tests only"
        echo "  all         - Run all tests (default)"
        exit 1
        ;;
esac

#!/usr/bin/env bash
set -e

# Test runner - executes every tests/test-*.sh on its own private tmux server.
# Exits non-zero if any test fails. A test that prints "SKIP:" and exits 0 counts as passed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "==================================="
echo "Running all tests in $TESTS_DIR"
echo "==================================="
echo

test_files=$(find "$TESTS_DIR" -maxdepth 1 -name "test-*.sh" -type f | sort)

if [ -z "$test_files" ]; then
	echo -e "${YELLOW}No test files found (test-*.sh)${NC}"
	exit 0
fi

total_tests=$(echo "$test_files" | wc -l)
passed=0
failed=0
failed_tests=()

echo "Found $total_tests test(s) to run"
echo

for test_file in $test_files; do
	test_name=$(basename "$test_file")
	echo "==================================="
	echo "Running: $test_name"
	echo "==================================="

	if bash "$test_file"; then
		echo -e "${GREEN}✓ PASSED: $test_name${NC}"
		passed=$((passed + 1))
	else
		echo -e "${RED}✗ FAILED: $test_name${NC}"
		failed=$((failed + 1))
		failed_tests+=("$test_name")
	fi
	echo
done

echo "==================================="
echo "Test Summary"
echo "==================================="
echo "Total:  $total_tests"
echo -e "${GREEN}Passed: $passed${NC}"
if [ $failed -gt 0 ]; then
	echo -e "${RED}Failed: $failed${NC}"
	echo
	echo "Failed tests:"
	for test in "${failed_tests[@]}"; do
		echo -e "  ${RED}✗ $test${NC}"
	done
	echo
	exit 1
else
	echo "Failed: 0"
	echo
	echo -e "${GREEN}All tests passed!${NC}"
	exit 0
fi

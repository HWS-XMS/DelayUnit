#!/usr/bin/env python3
"""
Comprehensive test for DelayUnit - tests all combinations of delays and widths.

Tests:
- Delays: 5ns to 1000ns (5ns increments)
- Widths: 5ns, 10ns, 25ns, 50ns, 100ns
- For each combination: configure, soft trigger, check counter increments
"""

import sys
import time
from pathlib import Path

# Add package to path if not installed
sys.path.insert(0, str(Path(__file__).parent))

from delay_unit import DelayUnit, EdgeType


def test_delay_width_combination(unit, delay_ns, width_ns, verbose=False):
    """
    Test a specific delay/width combination.

    Args:
        unit: DelayUnit instance
        delay_ns: Delay in nanoseconds
        width_ns: Output width in nanoseconds
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    # Reset counter
    unit.reset_counter()
    time.sleep(0.01)

    # Configure delay and width
    unit.delay_ns = delay_ns
    unit.width_ns = width_ns
    time.sleep(0.01)

    # Verify configuration
    readback_delay = unit.delay_ns
    readback_width = unit.width_ns

    if readback_delay is None or readback_width is None:
        if verbose:
            print(f"✗ Failed to read back configuration")
        return False

    # Check delay is correct
    delay_cycles = int(round(delay_ns / 5.0))
    expected_delay = delay_cycles * 5.0
    if abs(readback_delay - expected_delay) > 0.1:
        if verbose:
            print(f"✗ Delay mismatch: expected {expected_delay}ns, got {readback_delay}ns")
        return False

    # Check width is correct
    width_cycles = int(round(width_ns / 5.0))
    expected_width = width_cycles * 5.0
    if abs(readback_width - expected_width) > 0.1:
        if verbose:
            print(f"✗ Width mismatch: expected {expected_width}ns, got {readback_width}ns")
        return False

    # Generate soft trigger
    unit.soft_trigger()
    time.sleep(0.01)

    # Check counter incremented
    status = unit.status
    if not status:
        if verbose:
            print(f"✗ Failed to read status")
        return False

    if status['trigger_count'] != 1:
        if verbose:
            print(f"✗ Counter not 1: got {status['trigger_count']}")
        return False

    if verbose:
        print(f"✓ Delay={delay_ns}ns, Width={width_ns}ns - PASS")

    return True


def main():
    print("=" * 70)
    print("COMPREHENSIVE DELAY/WIDTH TEST")
    print("=" * 70)
    print("\nThis test will verify:")
    print("  - Delays: 5ns to 1000ns (5ns steps) = 200 values")
    print("  - Widths: 5ns, 10ns, 25ns, 50ns, 100ns = 5 values")
    print("  - Total combinations: 1000 tests")
    print("=" * 70)

    # Connect to FPGA
    try:
        unit = DelayUnit()
        print("\n✓ Connected to Arty board")
    except RuntimeError as e:
        print(f"\n✗ Failed to connect: {e}")
        sys.exit(1)

    try:
        # Configure edge detection
        unit.edge = EdgeType.RISING
        print("✓ Edge detection: RISING\n")

        # Test parameters
        delay_values = list(range(5, 1005, 5))  # 5ns to 1000ns in 5ns steps
        width_values = [5, 10, 25, 50, 100]  # Test widths in nanoseconds

        total_tests = len(delay_values) * len(width_values)
        passed = 0
        failed = 0
        failures = []

        print(f"Running {total_tests} tests...")
        print(f"{'Progress':>10} {'Delay':>10} {'Width':>10} {'Status':>10}")
        print("-" * 70)

        test_num = 0
        for width_ns in width_values:
            for delay_ns in delay_values:
                test_num += 1

                # Run test
                result = test_delay_width_combination(unit, delay_ns, width_ns, verbose=False)

                if result:
                    passed += 1
                    status_str = "✓"
                else:
                    failed += 1
                    status_str = "✗"
                    failures.append((delay_ns, width_ns))

                # Print progress every 50 tests or on failure
                if test_num % 50 == 0 or not result:
                    progress = f"{test_num}/{total_tests}"
                    print(f"{progress:>10} {delay_ns:>9}ns {width_ns:>9}ns {status_str:>10}")

        # Final progress
        progress = f"{test_num}/{total_tests}"
        print(f"{progress:>10} {'COMPLETE':>10} {'':<10} {'':>10}")

        # Summary
        print("\n" + "=" * 70)
        print("TEST SUMMARY")
        print("=" * 70)
        print(f"Total tests:  {total_tests}")
        print(f"Passed:       {passed} ({100*passed/total_tests:.1f}%)")
        print(f"Failed:       {failed} ({100*failed/total_tests:.1f}%)")

        if failed > 0:
            print(f"\nFailed combinations (showing first 10):")
            for delay_ns, width_ns in failures[:10]:
                print(f"  Delay={delay_ns}ns, Width={width_ns}ns")
            if len(failures) > 10:
                print(f"  ... and {len(failures) - 10} more")

        print("=" * 70)

        if failed == 0:
            print("\n✓ ALL TESTS PASSED!")
            print("The delay unit is working perfectly across all configurations.")
            sys.exit(0)
        else:
            print(f"\n✗ {failed} TEST(S) FAILED")
            sys.exit(1)

    finally:
        unit.close()


if __name__ == '__main__':
    main()

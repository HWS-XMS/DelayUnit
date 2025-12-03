#!/usr/bin/env python3
"""
Comprehensive test for DelayUnit - Counter trigger mode.

HARDWARE SETUP:
  - Connect JUMPER: Pin 3 -> Pin 1 on Pmod JA
  - Pin 1 acts as INPUT from DuT (receives from Pin 3 via jumper)

Tests:
- Counter mode configuration readback
- Counter mode DISABLED: every edge triggers
- Counter mode ENABLED with various targets (1, 2, 3, 5, 10, 50, 100)
- Edge types: RISING, FALLING
- Reset edge count functionality
- Auto-reset after trigger
- Boundary conditions (target=1, partial counts)
"""

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from delay_unit import DelayUnit, EdgeType, TriggerMode, CounterMode


def test_counter_mode_readback(unit, mode, verbose=False):
    """
    Test counter mode configuration and readback.

    Args:
        unit: DelayUnit instance
        mode: CounterMode to test
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    unit.counter_mode = mode
    time.sleep(0.01)

    readback = unit.counter_mode
    if readback is None:
        if verbose:
            print(f"  FAIL: Failed to read back counter_mode")
        return False

    if readback != mode:
        if verbose:
            print(f"  FAIL: counter_mode mismatch: expected {mode}, got {readback}")
        return False

    return True


def test_edge_count_target_readback(unit, target, verbose=False):
    """
    Test edge count target configuration and readback.

    Args:
        unit: DelayUnit instance
        target: Target value to test
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    unit.edge_count_target = target
    time.sleep(0.01)

    readback = unit.edge_count_target
    if readback is None:
        if verbose:
            print(f"  FAIL: Failed to read back edge_count_target")
        return False

    if readback != target:
        if verbose:
            print(f"  FAIL: edge_count_target mismatch: expected {target}, got {readback}")
        return False

    return True


def test_counter_trigger(unit, counter_mode, edge_count_target, edge_type, num_triggers, verbose=False):
    """
    Test a specific counter trigger configuration.

    Args:
        unit: DelayUnit instance
        counter_mode: CounterMode (DISABLED or ENABLED)
        edge_count_target: Target edge count (only used if counter_mode is ENABLED)
        edge_type: EdgeType for trigger detection
        num_triggers: Number of soft triggers to fire
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    # Reset counter
    unit.reset_counter()
    time.sleep(0.01)

    # Configure trigger mode (EXTERNAL to use jumper)
    unit.trigger_mode = TriggerMode.EXTERNAL
    time.sleep(0.01)

    # Configure edge type
    unit.edge = edge_type
    time.sleep(0.01)

    # Configure counter mode
    unit.counter_mode = counter_mode
    time.sleep(0.01)

    # Configure edge count target (if enabled)
    if counter_mode == CounterMode.ENABLED:
        unit.edge_count_target = edge_count_target
        time.sleep(0.01)

    # Reset edge count
    unit.reset_edge_count()
    time.sleep(0.01)

    # Verify configuration readback
    readback_mode = unit.trigger_mode
    readback_edge = unit.edge
    readback_counter_mode = unit.counter_mode

    if readback_mode is None or readback_edge is None or readback_counter_mode is None:
        if verbose:
            print(f"  FAIL: Failed to read back configuration")
        return False

    if readback_mode != TriggerMode.EXTERNAL:
        if verbose:
            print(f"  FAIL: trigger_mode mismatch: expected EXTERNAL, got {readback_mode}")
        return False

    if readback_edge != edge_type:
        if verbose:
            print(f"  FAIL: edge mismatch: expected {edge_type}, got {readback_edge}")
        return False

    if readback_counter_mode != counter_mode:
        if verbose:
            print(f"  FAIL: counter_mode mismatch: expected {counter_mode}, got {readback_counter_mode}")
        return False

    if counter_mode == CounterMode.ENABLED:
        readback_target = unit.edge_count_target
        if readback_target is None:
            if verbose:
                print(f"  FAIL: Failed to read back edge_count_target")
            return False
        if readback_target != edge_count_target:
            if verbose:
                print(f"  FAIL: edge_count_target mismatch: expected {edge_count_target}, got {readback_target}")
            return False

    # Get initial status
    status = unit.status
    if status is None:
        if verbose:
            print(f"  FAIL: Failed to read initial status")
        return False

    if status['trigger_count'] != 0:
        if verbose:
            print(f"  FAIL: Initial trigger_count not 0: got {status['trigger_count']}")
        return False

    # Fire soft triggers
    for _ in range(num_triggers):
        unit.soft_trigger()
        time.sleep(0.01)

    # Read final status
    status = unit.status
    if status is None:
        if verbose:
            print(f"  FAIL: Failed to read final status")
        return False

    # Calculate expected trigger count
    if counter_mode == CounterMode.DISABLED:
        expected_count = num_triggers
    else:
        expected_count = num_triggers // edge_count_target

    if status['trigger_count'] != expected_count:
        if verbose:
            print(f"  FAIL: trigger_count mismatch: expected {expected_count}, got {status['trigger_count']}")
        return False

    if verbose:
        mode_str = "DISABLED" if counter_mode == CounterMode.DISABLED else f"ENABLED(target={edge_count_target})"
        edge_str = {EdgeType.RISING: "RISING", EdgeType.FALLING: "FALLING", EdgeType.BOTH: "BOTH"}.get(edge_type, str(edge_type))
        print(f"  PASS: counter={mode_str}, edge={edge_str}, triggers={num_triggers} -> count={status['trigger_count']}")

    return True


def test_reset_edge_count(unit, verbose=False):
    """
    Test that reset_edge_count resets the internal edge counter.

    Args:
        unit: DelayUnit instance
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    # Setup
    unit.reset_counter()
    unit.trigger_mode = TriggerMode.EXTERNAL
    unit.edge = EdgeType.RISING
    unit.counter_mode = CounterMode.ENABLED
    unit.edge_count_target = 5
    unit.reset_edge_count()
    time.sleep(0.01)

    # Fire 3 triggers (not enough to reach target)
    for _ in range(3):
        unit.soft_trigger()
        time.sleep(0.01)

    status = unit.status
    if status is None or status['trigger_count'] != 0:
        if verbose:
            print(f"  FAIL: Expected 0 after 3 triggers, got {status}")
        return False

    # Reset edge count (internal counter goes back to 0)
    unit.reset_edge_count()
    time.sleep(0.01)

    # Fire 3 more triggers (still not enough since we reset)
    for _ in range(3):
        unit.soft_trigger()
        time.sleep(0.01)

    status = unit.status
    if status is None or status['trigger_count'] != 0:
        if verbose:
            print(f"  FAIL: Expected 0 after reset + 3 triggers, got {status}")
        return False

    # Fire 2 more to reach 5
    for _ in range(2):
        unit.soft_trigger()
        time.sleep(0.01)

    status = unit.status
    if status is None or status['trigger_count'] != 1:
        if verbose:
            print(f"  FAIL: Expected 1 after 5 triggers post-reset, got {status}")
        return False

    if verbose:
        print(f"  PASS: reset_edge_count correctly resets internal counter")

    return True


def test_partial_count_no_trigger(unit, verbose=False):
    """
    Test that partial counts (less than target) don't trigger.

    Args:
        unit: DelayUnit instance
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    # Setup with target=10
    unit.reset_counter()
    unit.trigger_mode = TriggerMode.EXTERNAL
    unit.edge = EdgeType.RISING
    unit.counter_mode = CounterMode.ENABLED
    unit.edge_count_target = 10
    unit.reset_edge_count()
    time.sleep(0.01)

    # Fire 1 to 9 triggers, verify count stays 0
    for i in range(1, 10):
        unit.soft_trigger()
        time.sleep(0.01)

        status = unit.status
        if status is None or status['trigger_count'] != 0:
            if verbose:
                print(f"  FAIL: Expected 0 after {i} triggers (target=10), got {status}")
            return False

    # Fire 10th trigger
    unit.soft_trigger()
    time.sleep(0.01)

    status = unit.status
    if status is None or status['trigger_count'] != 1:
        if verbose:
            print(f"  FAIL: Expected 1 after 10 triggers (target=10), got {status}")
        return False

    if verbose:
        print(f"  PASS: Partial counts don't trigger, 10th trigger fires")

    return True


def main():
    print("=" * 70)
    print("COMPREHENSIVE TEST - COUNTER TRIGGER MODE")
    print("=" * 70)
    print("\n*** HARDWARE SETUP REQUIRED:")
    print("  - Connect JUMPER: Pmod JA Pin 3 to Pin 1")
    print()
    print("  Signal flow: soft_trigger() -> Pin 3 -> [jumper] -> Pin 1 -> counter -> delay -> Pin 2")
    print("=" * 70)

    response = input("\nConfirm JUMPER is connected Pin 3 to Pin 1 (yes/no): ").strip().lower()
    if response not in ['yes', 'y']:
        print("Test aborted. Please connect jumper and try again.")
        sys.exit(0)

    print("\nThis test will verify:")
    print("  - Counter mode readback (DISABLED, ENABLED)")
    print("  - Edge count target readback (1, 2, 3, 5, 10, 50, 100)")
    print("  - Counter DISABLED: triggers on every edge")
    print("  - Counter ENABLED: triggers only on Nth edge")
    print("  - Edge types: RISING, FALLING")
    print("  - Reset edge count functionality")
    print("  - Partial count behavior (no trigger before target)")
    print("  - Auto-reset after trigger")
    print("=" * 70)

    # Connect to FPGA
    try:
        unit = DelayUnit(port='/dev/ttyUSB0')
        print("\nConnected to DelayUnit")
    except RuntimeError as e:
        print(f"\nFailed to connect: {e}")
        sys.exit(1)

    try:
        total_tests = 0
        passed = 0
        failed = 0
        failures = []

        # Test 1: Counter mode readback
        print("\n--- Test: Counter mode readback ---")
        for mode in [CounterMode.DISABLED, CounterMode.ENABLED]:
            total_tests += 1
            if test_counter_mode_readback(unit, mode, verbose=True):
                passed += 1
                print(f"  PASS: counter_mode = {mode.name}")
            else:
                failed += 1
                failures.append(f"counter_mode readback {mode.name}")

        # Test 2: Edge count target readback
        print("\n--- Test: Edge count target readback ---")
        for target in [1, 2, 3, 5, 10, 50, 100]:
            total_tests += 1
            if test_edge_count_target_readback(unit, target, verbose=True):
                passed += 1
                print(f"  PASS: edge_count_target = {target}")
            else:
                failed += 1
                failures.append(f"edge_count_target readback {target}")

        # Test 3: Counter DISABLED (trigger on every edge)
        print("\n--- Test: Counter DISABLED (trigger on every edge) ---")
        for edge_type in [EdgeType.RISING, EdgeType.FALLING]:
            total_tests += 1
            if test_counter_trigger(unit, CounterMode.DISABLED, 1, edge_type, 10, verbose=True):
                passed += 1
            else:
                failed += 1
                failures.append(f"counter DISABLED edge={edge_type}")

        # Test 4: Counter ENABLED with various targets
        print("\n--- Test: Counter ENABLED with various targets ---")
        test_configs = [
            (1, EdgeType.RISING, 10),     # target=1 is same as disabled
            (2, EdgeType.RISING, 10),     # 10/2 = 5 triggers
            (3, EdgeType.RISING, 9),      # 9/3 = 3 triggers
            (5, EdgeType.RISING, 25),     # 25/5 = 5 triggers
            (10, EdgeType.RISING, 50),    # 50/10 = 5 triggers
            (50, EdgeType.RISING, 200),   # 200/50 = 4 triggers
            (100, EdgeType.RISING, 500),  # 500/100 = 5 triggers
            (3, EdgeType.FALLING, 12),    # 12/3 = 4 triggers (falling edge)
            (5, EdgeType.FALLING, 20),    # 20/5 = 4 triggers (falling edge)
        ]
        for target, edge_type, num_triggers in test_configs:
            total_tests += 1
            if test_counter_trigger(unit, CounterMode.ENABLED, target, edge_type, num_triggers, verbose=True):
                passed += 1
            else:
                failed += 1
                failures.append(f"counter ENABLED target={target} edge={edge_type}")

        # Test 5: Reset edge count
        print("\n--- Test: Reset edge count functionality ---")
        total_tests += 1
        if test_reset_edge_count(unit, verbose=True):
            passed += 1
        else:
            failed += 1
            failures.append("reset_edge_count")

        # Test 6: Partial count (no trigger before target)
        print("\n--- Test: Partial count behavior ---")
        total_tests += 1
        if test_partial_count_no_trigger(unit, verbose=True):
            passed += 1
        else:
            failed += 1
            failures.append("partial_count_no_trigger")

        # Summary
        print("\n" + "=" * 70)
        print("TEST SUMMARY - COUNTER TRIGGER MODE")
        print("=" * 70)
        print(f"Total tests:  {total_tests}")
        print(f"Passed:       {passed} ({100*passed/total_tests:.1f}%)")
        print(f"Failed:       {failed} ({100*failed/total_tests:.1f}%)")

        if failed > 0:
            print(f"\nFailed tests:")
            for f in failures:
                print(f"  - {f}")

        print("=" * 70)

        if failed == 0:
            print("\nALL TESTS PASSED!")
            print("The counter trigger mode is working correctly.")
            sys.exit(0)
        else:
            print(f"\n{failed} TEST(S) FAILED")
            sys.exit(1)

    finally:
        unit.close()


if __name__ == '__main__':
    main()

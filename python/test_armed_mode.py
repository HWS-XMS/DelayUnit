#!/usr/bin/env python3
"""
Comprehensive test for DelayUnit - Armed mode functionality.

HARDWARE SETUP:
  - Connect JUMPER: Pin 3 -> Pin 1 on Pmod JA
  - Pin 1 acts as INPUT from DuT (receives from Pin 3 via jumper)

Tests:
- Armed state readback (arm/disarm)
- Armed mode readback (SINGLE/REPEAT)
- Disarmed state: no triggers generated
- Armed state: triggers generated
- SINGLE mode: auto-disarm after first trigger
- REPEAT mode: stay armed after trigger
- Counter only increments when armed
- Edge count only increments when armed
- Arm during edge stream
- Disarm during edge stream
"""

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from delay_unit import DelayUnit, EdgeType, TriggerMode, CounterMode, ArmedMode


def setup_unit(unit):
    """
    Common setup for all tests - set all parameters to known state.
    """
    unit.disarm()
    unit.trigger_mode = TriggerMode.EXTERNAL
    unit.edge = EdgeType.RISING
    unit.counter_mode = CounterMode.DISABLED
    unit.armed_mode = ArmedMode.SINGLE
    unit.coarse = 1  # Minimum 1 cycle for proper state machine operation
    unit.edge_count_target = 1
    unit.reset_counter()
    unit.reset_edge_count()
    time.sleep(0.01)


def test_armed_readback(unit, verbose=False):
    """
    Test arm/disarm commands and armed state readback.

    Args:
        unit: DelayUnit instance
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    setup_unit(unit)

    # Test disarm
    unit.disarm()
    time.sleep(0.01)

    armed = unit.armed
    if armed is None:
        if verbose:
            print(f"  FAIL: Failed to read armed state")
        return False

    if armed != False:
        if verbose:
            print(f"  FAIL: Expected armed=False after disarm, got {armed}")
        return False

    # Test arm
    unit.arm()
    time.sleep(0.01)

    armed = unit.armed
    if armed is None:
        if verbose:
            print(f"  FAIL: Failed to read armed state")
        return False

    if armed != True:
        if verbose:
            print(f"  FAIL: Expected armed=True after arm, got {armed}")
        return False

    # Cleanup: disarm
    unit.disarm()
    time.sleep(0.01)

    return True


def test_armed_mode_readback(unit, mode, verbose=False):
    """
    Test armed mode configuration and readback.

    Args:
        unit: DelayUnit instance
        mode: ArmedMode to test
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    setup_unit(unit)
    unit.armed_mode = mode
    time.sleep(0.01)

    readback = unit.armed_mode
    if readback is None:
        if verbose:
            print(f"  FAIL: Failed to read back armed_mode")
        return False

    if readback != mode:
        if verbose:
            print(f"  FAIL: armed_mode mismatch: expected {mode}, got {readback}")
        return False

    return True


def test_disarmed_no_triggers(unit, verbose=False):
    """
    Test that no triggers are generated when disarmed.

    Args:
        unit: DelayUnit instance
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    setup_unit(unit)

    # Fire 10 soft triggers while disarmed
    for _ in range(10):
        unit.soft_trigger()
        time.sleep(0.01)

    status = unit.status
    if status is None:
        if verbose:
            print(f"  FAIL: Failed to read status")
        return False

    if status['trigger_count'] != 0:
        if verbose:
            print(f"  FAIL: Expected 0 triggers while disarmed, got {status['trigger_count']}")
        return False

    return True


def test_armed_triggers(unit, verbose=False):
    """
    Test that triggers are generated when armed.

    Args:
        unit: DelayUnit instance
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    setup_unit(unit)
    unit.armed_mode = ArmedMode.REPEAT  # Stay armed
    unit.arm()
    time.sleep(0.01)

    # Fire 10 soft triggers while armed
    for _ in range(10):
        unit.soft_trigger()
        time.sleep(0.01)

    status = unit.status
    if status is None:
        if verbose:
            print(f"  FAIL: Failed to read status")
        return False

    if status['trigger_count'] != 10:
        if verbose:
            print(f"  FAIL: Expected 10 triggers while armed, got {status['trigger_count']}")
        return False

    # Cleanup
    unit.disarm()
    time.sleep(0.01)

    return True


def test_single_mode_auto_disarm(unit, verbose=False):
    """
    Test SINGLE mode auto-disarms after first trigger.

    Args:
        unit: DelayUnit instance
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    setup_unit(unit)
    unit.armed_mode = ArmedMode.SINGLE
    unit.arm()
    time.sleep(0.01)

    # Verify armed
    if not unit.armed:
        if verbose:
            print(f"  FAIL: Expected armed=True after arm")
        return False

    # Fire first soft trigger
    unit.soft_trigger()
    time.sleep(0.01)

    # Should now be disarmed
    armed = unit.armed
    if armed != False:
        if verbose:
            print(f"  FAIL: Expected armed=False after trigger in SINGLE mode, got {armed}")
        return False

    # Verify trigger count is 1
    status = unit.status
    if status is None or status['trigger_count'] != 1:
        if verbose:
            print(f"  FAIL: Expected trigger_count=1, got {status}")
        return False

    # Fire more triggers - should not increment since disarmed
    for _ in range(5):
        unit.soft_trigger()
        time.sleep(0.01)

    status = unit.status
    if status is None or status['trigger_count'] != 1:
        if verbose:
            print(f"  FAIL: Expected trigger_count=1 after more triggers while disarmed, got {status}")
        return False

    return True


def test_repeat_mode_stays_armed(unit, verbose=False):
    """
    Test REPEAT mode stays armed after trigger.

    Args:
        unit: DelayUnit instance
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    setup_unit(unit)
    unit.armed_mode = ArmedMode.REPEAT
    unit.arm()
    time.sleep(0.01)

    # Fire multiple triggers
    for i in range(5):
        unit.soft_trigger()
        time.sleep(0.01)

        # Verify still armed after each trigger
        armed = unit.armed
        if armed != True:
            if verbose:
                print(f"  FAIL: Expected armed=True after trigger {i+1} in REPEAT mode, got {armed}")
            return False

    # Verify all triggers counted
    status = unit.status
    if status is None or status['trigger_count'] != 5:
        if verbose:
            print(f"  FAIL: Expected trigger_count=5, got {status}")
        return False

    # Cleanup
    unit.disarm()
    time.sleep(0.01)

    return True


def test_edge_count_only_when_armed(unit, verbose=False):
    """
    Test that edge counter only increments when armed.

    Args:
        unit: DelayUnit instance
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    setup_unit(unit)
    unit.counter_mode = CounterMode.ENABLED
    unit.edge_count_target = 5
    unit.armed_mode = ArmedMode.REPEAT
    time.sleep(0.01)

    # Fire 3 soft triggers while DISARMED
    for _ in range(3):
        unit.soft_trigger()
        time.sleep(0.01)

    # Should have 0 triggers (disarmed, edges not counted)
    status = unit.status
    if status is None or status['trigger_count'] != 0:
        if verbose:
            print(f"  FAIL: Expected 0 triggers while disarmed, got {status}")
        return False

    # Now arm
    unit.arm()
    time.sleep(0.01)

    # Fire 5 soft triggers - should trigger once (5 edges = 1 trigger)
    for _ in range(5):
        unit.soft_trigger()
        time.sleep(0.01)

    status = unit.status
    if status is None or status['trigger_count'] != 1:
        if verbose:
            print(f"  FAIL: Expected 1 trigger after 5 edges while armed, got {status}")
        return False

    # Fire 5 more - should trigger again
    for _ in range(5):
        unit.soft_trigger()
        time.sleep(0.01)

    status = unit.status
    if status is None or status['trigger_count'] != 2:
        if verbose:
            print(f"  FAIL: Expected 2 triggers after 10 edges while armed, got {status}")
        return False

    # Cleanup
    unit.disarm()
    time.sleep(0.01)

    return True


def test_single_mode_with_counter(unit, verbose=False):
    """
    Test SINGLE mode with counter: trigger once on Nth edge, then disarm.

    Args:
        unit: DelayUnit instance
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    setup_unit(unit)
    unit.counter_mode = CounterMode.ENABLED
    unit.edge_count_target = 3
    unit.armed_mode = ArmedMode.SINGLE
    unit.arm()
    time.sleep(0.01)

    # Fire 2 edges - should not trigger yet
    for _ in range(2):
        unit.soft_trigger()
        time.sleep(0.01)

    status = unit.status
    armed = unit.armed
    if status is None or status['trigger_count'] != 0:
        if verbose:
            print(f"  FAIL: Expected 0 triggers after 2 edges (target=3), got {status}")
        return False
    if armed != True:
        if verbose:
            print(f"  FAIL: Expected still armed after 2 edges, got {armed}")
        return False

    # Fire 3rd edge - should trigger and auto-disarm
    unit.soft_trigger()
    time.sleep(0.01)

    status = unit.status
    armed = unit.armed
    if status is None or status['trigger_count'] != 1:
        if verbose:
            print(f"  FAIL: Expected 1 trigger after 3rd edge, got {status}")
        return False
    if armed != False:
        if verbose:
            print(f"  FAIL: Expected disarmed after trigger in SINGLE mode, got {armed}")
        return False

    # Fire more edges - should not trigger (disarmed)
    for _ in range(10):
        unit.soft_trigger()
        time.sleep(0.01)

    status = unit.status
    if status is None or status['trigger_count'] != 1:
        if verbose:
            print(f"  FAIL: Expected still 1 trigger after more edges while disarmed, got {status}")
        return False

    return True


def test_arm_disarm_during_operation(unit, verbose=False):
    """
    Test arming and disarming mid-operation.

    Args:
        unit: DelayUnit instance
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    setup_unit(unit)
    unit.armed_mode = ArmedMode.REPEAT
    time.sleep(0.01)

    # Fire 5 triggers while disarmed
    for _ in range(5):
        unit.soft_trigger()
        time.sleep(0.01)

    status = unit.status
    if status is None or status['trigger_count'] != 0:
        if verbose:
            print(f"  FAIL: Expected 0 triggers while disarmed, got {status}")
        return False

    # Arm
    unit.arm()
    time.sleep(0.01)

    # Fire 3 triggers while armed
    for _ in range(3):
        unit.soft_trigger()
        time.sleep(0.01)

    status = unit.status
    if status is None or status['trigger_count'] != 3:
        if verbose:
            print(f"  FAIL: Expected 3 triggers while armed, got {status}")
        return False

    # Disarm
    unit.disarm()
    time.sleep(0.01)

    # Fire 5 more triggers while disarmed
    for _ in range(5):
        unit.soft_trigger()
        time.sleep(0.01)

    status = unit.status
    if status is None or status['trigger_count'] != 3:
        if verbose:
            print(f"  FAIL: Expected still 3 triggers after disarm, got {status}")
        return False

    # Arm again
    unit.arm()
    time.sleep(0.01)

    # Fire 2 more triggers
    for _ in range(2):
        unit.soft_trigger()
        time.sleep(0.01)

    status = unit.status
    if status is None or status['trigger_count'] != 5:
        if verbose:
            print(f"  FAIL: Expected 5 triggers total, got {status}")
        return False

    # Cleanup
    unit.disarm()
    time.sleep(0.01)

    return True


def test_rearm_after_single(unit, verbose=False):
    """
    Test re-arming after SINGLE mode auto-disarm.

    Args:
        unit: DelayUnit instance
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    setup_unit(unit)
    unit.armed_mode = ArmedMode.SINGLE
    unit.arm()
    time.sleep(0.01)

    # First trigger - auto-disarms
    unit.soft_trigger()
    time.sleep(0.01)

    if unit.armed != False:
        if verbose:
            print(f"  FAIL: Expected disarmed after first trigger")
        return False

    status = unit.status
    if status is None or status['trigger_count'] != 1:
        if verbose:
            print(f"  FAIL: Expected 1 trigger, got {status}")
        return False

    # Re-arm
    unit.arm()
    time.sleep(0.01)

    if unit.armed != True:
        if verbose:
            print(f"  FAIL: Expected armed after re-arm")
        return False

    # Second trigger - auto-disarms again
    unit.soft_trigger()
    time.sleep(0.01)

    if unit.armed != False:
        if verbose:
            print(f"  FAIL: Expected disarmed after second trigger")
        return False

    status = unit.status
    if status is None or status['trigger_count'] != 2:
        if verbose:
            print(f"  FAIL: Expected 2 triggers, got {status}")
        return False

    return True


def test_falling_edge(unit, verbose=False):
    """
    Test armed mode with FALLING edge detection.

    Args:
        unit: DelayUnit instance
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    setup_unit(unit)
    unit.edge = EdgeType.FALLING
    unit.armed_mode = ArmedMode.REPEAT
    unit.arm()
    time.sleep(0.01)

    # Fire 5 soft triggers
    for _ in range(5):
        unit.soft_trigger()
        time.sleep(0.01)

    status = unit.status
    if status is None or status['trigger_count'] != 5:
        if verbose:
            print(f"  FAIL: Expected 5 triggers with FALLING edge, got {status}")
        return False

    unit.disarm()
    return True


def test_arm_idempotent(unit, verbose=False):
    """
    Test that arm() is idempotent (calling multiple times has no side effect).

    Args:
        unit: DelayUnit instance
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    setup_unit(unit)
    unit.armed_mode = ArmedMode.REPEAT

    # Arm multiple times
    unit.arm()
    time.sleep(0.01)
    unit.arm()
    time.sleep(0.01)
    unit.arm()
    time.sleep(0.01)

    if not unit.armed:
        if verbose:
            print(f"  FAIL: Expected armed=True after multiple arm() calls")
        return False

    # Fire trigger
    unit.soft_trigger()
    time.sleep(0.01)

    status = unit.status
    if status is None or status['trigger_count'] != 1:
        if verbose:
            print(f"  FAIL: Expected 1 trigger after multiple arm() calls, got {status}")
        return False

    unit.disarm()
    return True


def test_disarm_idempotent(unit, verbose=False):
    """
    Test that disarm() is idempotent (calling multiple times has no side effect).

    Args:
        unit: DelayUnit instance
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    setup_unit(unit)

    # Disarm multiple times (already disarmed from setup)
    unit.disarm()
    time.sleep(0.01)
    unit.disarm()
    time.sleep(0.01)
    unit.disarm()
    time.sleep(0.01)

    if unit.armed:
        if verbose:
            print(f"  FAIL: Expected armed=False after multiple disarm() calls")
        return False

    # Fire trigger - should not count
    unit.soft_trigger()
    time.sleep(0.01)

    status = unit.status
    if status is None or status['trigger_count'] != 0:
        if verbose:
            print(f"  FAIL: Expected 0 triggers after multiple disarm() calls, got {status}")
        return False

    return True


def test_reset_edge_count_while_armed(unit, verbose=False):
    """
    Test reset_edge_count() works while armed.

    Args:
        unit: DelayUnit instance
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    setup_unit(unit)
    unit.counter_mode = CounterMode.ENABLED
    unit.edge_count_target = 5
    unit.armed_mode = ArmedMode.REPEAT
    unit.arm()
    time.sleep(0.01)

    # Fire 3 edges (partial, not enough to trigger)
    for _ in range(3):
        unit.soft_trigger()
        time.sleep(0.01)

    status = unit.status
    if status is None or status['trigger_count'] != 0:
        if verbose:
            print(f"  FAIL: Expected 0 triggers after 3 edges (target=5), got {status}")
        return False

    # Reset edge count while armed
    unit.reset_edge_count()
    time.sleep(0.01)

    # Fire 3 more edges - still not enough (reset back to 0)
    for _ in range(3):
        unit.soft_trigger()
        time.sleep(0.01)

    status = unit.status
    if status is None or status['trigger_count'] != 0:
        if verbose:
            print(f"  FAIL: Expected 0 triggers after reset + 3 edges, got {status}")
        return False

    # Fire 2 more to complete 5 edges
    for _ in range(2):
        unit.soft_trigger()
        time.sleep(0.01)

    status = unit.status
    if status is None or status['trigger_count'] != 1:
        if verbose:
            print(f"  FAIL: Expected 1 trigger after 5 edges post-reset, got {status}")
        return False

    unit.disarm()
    return True


def test_switch_armed_mode_while_armed(unit, verbose=False):
    """
    Test switching armed_mode while armed.

    Args:
        unit: DelayUnit instance
        verbose: Print detailed info

    Returns:
        True if test passed, False otherwise
    """
    setup_unit(unit)
    unit.armed_mode = ArmedMode.REPEAT
    unit.arm()
    time.sleep(0.01)

    # Fire a trigger in REPEAT mode
    unit.soft_trigger()
    time.sleep(0.01)

    if not unit.armed:
        if verbose:
            print(f"  FAIL: Expected still armed in REPEAT mode")
        return False

    status = unit.status
    if status is None or status['trigger_count'] != 1:
        if verbose:
            print(f"  FAIL: Expected 1 trigger, got {status}")
        return False

    # Switch to SINGLE mode while armed
    unit.armed_mode = ArmedMode.SINGLE
    time.sleep(0.01)

    # Should still be armed
    if not unit.armed:
        if verbose:
            print(f"  FAIL: Expected still armed after mode switch")
        return False

    # Next trigger should auto-disarm (now in SINGLE mode)
    unit.soft_trigger()
    time.sleep(0.01)

    if unit.armed:
        if verbose:
            print(f"  FAIL: Expected disarmed after trigger in SINGLE mode")
        return False

    status = unit.status
    if status is None or status['trigger_count'] != 2:
        if verbose:
            print(f"  FAIL: Expected 2 triggers total, got {status}")
        return False

    return True


def main():
    print("=" * 70)
    print("COMPREHENSIVE TEST - ARMED MODE")
    print("=" * 70)
    print("\n*** HARDWARE SETUP REQUIRED:")
    print("  - Connect JUMPER: Pmod JA Pin 3 to Pin 1")
    print()
    print("  Signal flow: soft_trigger() -> Pin 3 -> [jumper] -> Pin 1 -> trigger logic")
    print("=" * 70)

    response = input("\nConfirm JUMPER is connected Pin 3 to Pin 1 (yes/no): ").strip().lower()
    if response not in ['yes', 'y']:
        print("Test aborted. Please connect jumper and try again.")
        sys.exit(0)

    print("\nThis test will verify:")
    print("  - Arm/disarm commands and readback")
    print("  - Armed mode readback (SINGLE, REPEAT)")
    print("  - No triggers when disarmed")
    print("  - Triggers generated when armed")
    print("  - SINGLE mode: auto-disarm after first trigger")
    print("  - REPEAT mode: stay armed after trigger")
    print("  - Edge counter only increments when armed")
    print("  - SINGLE mode with counter (Nth edge)")
    print("  - Arm/disarm mid-operation")
    print("  - Re-arm after SINGLE mode auto-disarm")
    print("  - FALLING edge detection")
    print("  - Arm idempotency")
    print("  - Disarm idempotency")
    print("  - Reset edge count while armed")
    print("  - Switch armed_mode while armed")
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

        # Test 1: Armed state readback
        print("\n--- Test: Arm/disarm and readback ---")
        total_tests += 1
        if test_armed_readback(unit, verbose=True):
            passed += 1
            print(f"  PASS: arm/disarm and armed readback")
        else:
            failed += 1
            failures.append("arm/disarm readback")

        # Test 2: Armed mode readback
        print("\n--- Test: Armed mode readback ---")
        for mode in [ArmedMode.SINGLE, ArmedMode.REPEAT]:
            total_tests += 1
            if test_armed_mode_readback(unit, mode, verbose=True):
                passed += 1
                print(f"  PASS: armed_mode = {mode.name}")
            else:
                failed += 1
                failures.append(f"armed_mode readback {mode.name}")

        # Test 3: No triggers when disarmed
        print("\n--- Test: No triggers when disarmed ---")
        total_tests += 1
        if test_disarmed_no_triggers(unit, verbose=True):
            passed += 1
            print(f"  PASS: No triggers generated while disarmed")
        else:
            failed += 1
            failures.append("disarmed no triggers")

        # Test 4: Triggers when armed
        print("\n--- Test: Triggers when armed ---")
        total_tests += 1
        if test_armed_triggers(unit, verbose=True):
            passed += 1
            print(f"  PASS: Triggers generated while armed")
        else:
            failed += 1
            failures.append("armed triggers")

        # Test 5: SINGLE mode auto-disarm
        print("\n--- Test: SINGLE mode auto-disarm ---")
        total_tests += 1
        if test_single_mode_auto_disarm(unit, verbose=True):
            passed += 1
            print(f"  PASS: SINGLE mode auto-disarms after first trigger")
        else:
            failed += 1
            failures.append("SINGLE mode auto-disarm")

        # Test 6: REPEAT mode stays armed
        print("\n--- Test: REPEAT mode stays armed ---")
        total_tests += 1
        if test_repeat_mode_stays_armed(unit, verbose=True):
            passed += 1
            print(f"  PASS: REPEAT mode stays armed after triggers")
        else:
            failed += 1
            failures.append("REPEAT mode stays armed")

        # Test 7: Edge count only when armed
        print("\n--- Test: Edge count only when armed ---")
        total_tests += 1
        if test_edge_count_only_when_armed(unit, verbose=True):
            passed += 1
            print(f"  PASS: Edge counter only increments when armed")
        else:
            failed += 1
            failures.append("edge count only when armed")

        # Test 8: SINGLE mode with counter
        print("\n--- Test: SINGLE mode with counter ---")
        total_tests += 1
        if test_single_mode_with_counter(unit, verbose=True):
            passed += 1
            print(f"  PASS: SINGLE mode triggers on Nth edge then disarms")
        else:
            failed += 1
            failures.append("SINGLE mode with counter")

        # Test 9: Arm/disarm during operation
        print("\n--- Test: Arm/disarm during operation ---")
        total_tests += 1
        if test_arm_disarm_during_operation(unit, verbose=True):
            passed += 1
            print(f"  PASS: Arm/disarm mid-operation works correctly")
        else:
            failed += 1
            failures.append("arm/disarm during operation")

        # Test 10: Re-arm after SINGLE
        print("\n--- Test: Re-arm after SINGLE mode ---")
        total_tests += 1
        if test_rearm_after_single(unit, verbose=True):
            passed += 1
            print(f"  PASS: Re-arm after SINGLE mode auto-disarm works")
        else:
            failed += 1
            failures.append("re-arm after SINGLE")

        # Test 11: FALLING edge detection
        print("\n--- Test: FALLING edge detection ---")
        total_tests += 1
        if test_falling_edge(unit, verbose=True):
            passed += 1
            print(f"  PASS: FALLING edge detection works")
        else:
            failed += 1
            failures.append("FALLING edge")

        # Test 12: Arm idempotency
        print("\n--- Test: Arm idempotency ---")
        total_tests += 1
        if test_arm_idempotent(unit, verbose=True):
            passed += 1
            print(f"  PASS: Multiple arm() calls are idempotent")
        else:
            failed += 1
            failures.append("arm idempotent")

        # Test 13: Disarm idempotency
        print("\n--- Test: Disarm idempotency ---")
        total_tests += 1
        if test_disarm_idempotent(unit, verbose=True):
            passed += 1
            print(f"  PASS: Multiple disarm() calls are idempotent")
        else:
            failed += 1
            failures.append("disarm idempotent")

        # Test 14: Reset edge count while armed
        print("\n--- Test: Reset edge count while armed ---")
        total_tests += 1
        if test_reset_edge_count_while_armed(unit, verbose=True):
            passed += 1
            print(f"  PASS: reset_edge_count() works while armed")
        else:
            failed += 1
            failures.append("reset edge count while armed")

        # Test 15: Switch armed_mode while armed
        print("\n--- Test: Switch armed_mode while armed ---")
        total_tests += 1
        if test_switch_armed_mode_while_armed(unit, verbose=True):
            passed += 1
            print(f"  PASS: Switching armed_mode while armed works")
        else:
            failed += 1
            failures.append("switch armed_mode while armed")

        # Summary
        print("\n" + "=" * 70)
        print("TEST SUMMARY - ARMED MODE")
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
            print("The armed mode is working correctly.")
            sys.exit(0)
        else:
            print(f"\n{failed} TEST(S) FAILED")
            sys.exit(1)

    finally:
        # Ensure disarmed on exit
        unit.disarm()
        unit.close()


if __name__ == '__main__':
    main()

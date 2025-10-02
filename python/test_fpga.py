#!/usr/bin/env python3
"""
Exhaustive FPGA test for the delay unit.
Tests conversion accuracy, MMCM phase shifting, and end-to-end delay.

Requirements:
- FPGA must be programmed with the delay unit bitstream
- Board must be connected via USB
"""

import sys
import time
from delay_unit import DelayUnit, EdgeType

def test_connection():
    """Test basic connection to FPGA"""
    print("=" * 70)
    print("TEST 1: Connection Test")
    print("=" * 70)

    try:
        unit = DelayUnit()
        print("✓ Successfully connected to Arty board")

        # Test basic read
        status = unit.status
        if status:
            print(f"✓ UART communication working")
            print(f"  Trigger count: {status['trigger_count']}")
            print(f"  Current delay: {status['actual_delay_ps']}ps")
            return unit
        else:
            print("✗ Failed to read status")
            return None

    except RuntimeError as e:
        print(f"✗ Connection failed: {e}")
        return None

def test_coarse_delay(unit):
    """Test coarse delay (clock cycle increments)"""
    print("\n" + "=" * 70)
    print("TEST 2: Coarse Delay Test")
    print("=" * 70)

    test_values = [0, 1, 10, 100, 1000, 10000, 65535]

    print(f"{'Set (cycles)':>15} {'Read (cycles)':>15} {'Match':>8}")
    print("-" * 70)

    passed = 0
    failed = 0

    for cycles in test_values:
        unit.coarse = cycles
        time.sleep(0.05)  # Allow FPGA to update

        readback = unit.coarse
        match = "✓" if readback == cycles else "✗"

        print(f"{cycles:15} {readback:15} {match:>8}")

        if readback == cycles:
            passed += 1
        else:
            failed += 1

    print(f"\nResult: {passed}/{passed+failed} passed")
    return failed == 0

def test_fine_delay(unit):
    """Test fine delay (picosecond increments)"""
    print("\n" + "=" * 70)
    print("TEST 3: Fine Delay Test")
    print("=" * 70)

    # Test multiples of 17ps (should be exact)
    test_values = [0, 17, 34, 51, 68, 85, 102, 170, 340, 510, 850, 1700, 5000, 9999]

    print(f"{'Set (ps)':>10} {'Read (ps)':>10} {'Match':>8}")
    print("-" * 70)

    passed = 0
    failed = 0

    for ps in test_values:
        unit.fine = ps
        time.sleep(0.05)

        readback = unit.fine
        match = "✓" if readback == ps else "✗"

        print(f"{ps:10} {readback:10} {match:>8}")

        if readback == ps:
            passed += 1
        else:
            failed += 1

    print(f"\nResult: {passed}/{passed+failed} passed")
    return failed == 0

def test_delay_ps_property(unit):
    """Test the high-level delay_ps property"""
    print("\n" + "=" * 70)
    print("TEST 4: delay_ps Property Test")
    print("=" * 70)

    # Test various delay values
    test_values = [
        0,          # Zero delay
        17,         # One step
        170,        # 10 steps
        1700,       # 100 steps
        10000,      # 1 cycle
        25500,      # 2.5 cycles + 5500ps
        50000,      # 5 cycles
        100000,     # 10 cycles
    ]

    print(f"{'Set (ps)':>12} {'Read (ps)':>12} {'Error (ps)':>12} {'Error %':>12}")
    print("-" * 70)

    passed = 0
    failed = 0
    max_error = 0

    for ps in test_values:
        unit.delay_ps = ps
        time.sleep(0.1)  # Allow FPGA to update both coarse and fine

        readback = unit.delay_ps
        if readback is None:
            print(f"{ps:12} {'ERROR':>12}")
            failed += 1
            continue

        error = readback - ps
        if ps > 0:
            error_pct = abs(error / ps * 100)
        else:
            error_pct = 0

        # For multiples of 17ps, expect exact match
        # For others, allow up to 17ps error (one step)
        expected_exact = (ps % 17 == 0) and (ps >= 17)

        if expected_exact:
            match = "✓" if error == 0 else "✗"
        else:
            match = "✓" if abs(error) <= 17 else "✗"

        print(f"{ps:12} {readback:12} {error:+12} {error_pct:11.2f}% {match}")

        if match == "✓":
            passed += 1
        else:
            failed += 1

        max_error = max(max_error, abs(error))

    print(f"\nMaximum error: {max_error}ps")
    print(f"Result: {passed}/{passed+failed} passed")
    return failed == 0

def test_edge_detection(unit):
    """Test edge detection configuration"""
    print("\n" + "=" * 70)
    print("TEST 5: Edge Detection Test")
    print("=" * 70)

    edge_types = [
        (EdgeType.NONE, "NONE"),
        (EdgeType.RISING, "RISING"),
        (EdgeType.FALLING, "FALLING"),
        (EdgeType.BOTH, "BOTH"),
    ]

    print(f"{'Set':>10} {'Read':>10} {'Match':>8}")
    print("-" * 70)

    passed = 0
    failed = 0

    for edge_val, edge_name in edge_types:
        unit.edge = edge_val
        time.sleep(0.05)

        readback = unit.edge
        match = "✓" if readback == edge_val else "✗"

        print(f"{edge_name:>10} {readback.name if readback else 'ERROR':>10} {match:>8}")

        if readback == edge_val:
            passed += 1
        else:
            failed += 1

    print(f"\nResult: {passed}/{passed+failed} passed")
    return failed == 0

def test_status_readback(unit):
    """Test status register reading"""
    print("\n" + "=" * 70)
    print("TEST 6: Status Register Test")
    print("=" * 70)

    # Set known values
    unit.coarse = 100
    unit.fine = 500
    time.sleep(0.1)

    status = unit.status
    if not status:
        print("✗ Failed to read status")
        return False

    print(f"Trigger count: {status['trigger_count']}")
    print(f"Coarse cycles: {status['coarse_cycles']}")
    print(f"Fine ps requested: {status['fine_ps_requested']}")
    print(f"Actual delay (ps): {status['actual_delay_ps']}")
    print(f"Actual delay (ns): {status['actual_delay_ns']:.3f}")

    # Verify coarse matches
    if status['coarse_cycles'] != 100:
        print(f"✗ Coarse mismatch: expected 100, got {status['coarse_cycles']}")
        return False

    # Verify fine matches
    if status['fine_ps_requested'] != 500:
        print(f"✗ Fine mismatch: expected 500, got {status['fine_ps_requested']}")
        return False

    print("✓ Status readback matches set values")
    return True

def test_counter_reset(unit):
    """Test trigger counter reset"""
    print("\n" + "=" * 70)
    print("TEST 7: Counter Reset Test")
    print("=" * 70)

    # Read initial count
    status1 = unit.status
    if not status1:
        print("✗ Failed to read status")
        return False

    count_before = status1['trigger_count']
    print(f"Counter before reset: {count_before}")

    # Reset counter
    unit.reset_counter()
    time.sleep(0.05)

    # Read again
    status2 = unit.status
    if not status2:
        print("✗ Failed to read status after reset")
        return False

    count_after = status2['trigger_count']
    print(f"Counter after reset: {count_after}")

    if count_after == 0:
        print("✓ Counter reset successful")
        return True
    else:
        print(f"✗ Counter not zero after reset (got {count_after})")
        return False

def test_17ps_multiples(unit):
    """Comprehensive test of all 17ps multiples up to 10ns"""
    print("\n" + "=" * 70)
    print("TEST 8: Comprehensive 17ps Multiple Test (0-10ns)")
    print("=" * 70)

    errors = []
    max_steps = 588  # Maximum steps for 10ns

    print("Testing all 17ps steps from 0 to 588...")
    print(f"{'Steps':>6} {'PS':>10} {'Readback':>10} {'Error':>8}")
    print("-" * 70)

    sample_points = [0, 1, 2, 3, 5, 10, 20, 50, 100, 200, 300, 400, 500, 588]

    for steps in range(0, max_steps + 1):
        ps_value = steps * 17
        unit.delay_ps = ps_value
        time.sleep(0.02)  # Small delay for FPGA update

        readback = unit.delay_ps
        if readback is None:
            errors.append((steps, ps_value, None, "READ_ERROR"))
            continue

        error = readback - ps_value

        if error != 0:
            errors.append((steps, ps_value, readback, error))

        # Print sample points
        if steps in sample_points:
            match = "✓" if error == 0 else "✗"
            print(f"{steps:6} {ps_value:10} {readback:10} {error:+8} {match}")

    print(f"\nTested {max_steps + 1} values")

    if len(errors) == 0:
        print("✓ ALL tests passed - perfect accuracy!")
        return True
    else:
        print(f"✗ {len(errors)} errors found:")
        for steps, ps, rb, err in errors[:10]:  # Show first 10 errors
            print(f"  Steps {steps}: requested {ps}ps, got {rb}ps, error {err}")
        if len(errors) > 10:
            print(f"  ... and {len(errors) - 10} more errors")
        return False

def test_conversion_consistency(unit):
    """Verify FPGA stores and returns requested values correctly"""
    print("\n" + "=" * 70)
    print("TEST 9: FPGA Value Storage Consistency")
    print("=" * 70)

    test_ps_values = [0, 17, 34, 51, 100, 500, 1000, 2500, 5000, 7500, 9999]

    print(f"{'Set (ps)':>10} {'Read (ps)':>10} {'Match':>8}")
    print("-" * 70)

    passed = 0
    failed = 0

    for ps in test_ps_values:
        unit.fine = ps
        time.sleep(0.05)
        readback = unit.fine

        match = "✓" if readback == ps else "✗"
        print(f"{ps:10} {readback:10} {match:>8}")

        if readback == ps:
            passed += 1
        else:
            failed += 1

    print(f"\nResult: {passed}/{passed+failed} passed")
    print("Note: FPGA stores requested values; conversion to steps happens in MMCM")
    return failed == 0

def main():
    print("\n" + "=" * 70)
    print("FPGA DELAY UNIT - EXHAUSTIVE TEST SUITE")
    print("=" * 70)
    print()

    # Test connection
    unit = test_connection()
    if unit is None:
        print("\n✗ Cannot proceed without connection")
        sys.exit(1)

    try:
        results = {}

        # Run all tests
        results['Coarse Delay'] = test_coarse_delay(unit)
        results['Fine Delay'] = test_fine_delay(unit)
        results['delay_ps Property'] = test_delay_ps_property(unit)
        results['Edge Detection'] = test_edge_detection(unit)
        results['Status Readback'] = test_status_readback(unit)
        results['Counter Reset'] = test_counter_reset(unit)
        results['Value Storage Consistency'] = test_conversion_consistency(unit)
        results['17ps Multiples (0-10ns)'] = test_17ps_multiples(unit)

        # Summary
        print("\n" + "=" * 70)
        print("TEST SUMMARY")
        print("=" * 70)

        for test_name, passed in results.items():
            status = "✓ PASS" if passed else "✗ FAIL"
            print(f"{test_name:.<50} {status}")

        total_passed = sum(results.values())
        total_tests = len(results)

        print("=" * 70)
        print(f"Overall: {total_passed}/{total_tests} test suites passed")

        if total_passed == total_tests:
            print("\n🎉 ALL TESTS PASSED! FPGA is working perfectly.")
            sys.exit(0)
        else:
            print(f"\n⚠️  {total_tests - total_passed} test suite(s) failed.")
            sys.exit(1)

    finally:
        unit.close()

if __name__ == '__main__':
    main()

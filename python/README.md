# DelayUnit Python Package

Python control interface for the Precision Trigger Delay System.

## Installation (Optional)

```bash
pip install -e .
```

Or just run tests directly - they auto-import from local path.

## Quick Start

```python
from delay_unit import DelayUnit, EdgeType

with DelayUnit() as unit:
    unit.delay_ns = 100
    unit.width_ns = 50
    unit.edge = EdgeType.RISING
    unit.soft_trigger()
    print(unit.status)
```

## API Reference

**Properties:**
- `delay_ns` / `width_ns` - Timing in nanoseconds
- `edge` - Edge detection mode
- `status` - Trigger count and configuration

**Methods:**
- `soft_trigger()` - Generate test trigger
- `reset_counter()` - Reset counter

## Testing

```bash
python test_comprehensive.py  # 1000 test combinations
```

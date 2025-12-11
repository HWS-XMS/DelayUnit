"""
Core module for DelayUnit - FPGA-based picosecond delay control.
"""

import serial
import serial.tools.list_ports
import struct
import time
from decimal import Decimal, getcontext
from enum import IntEnum
from typing import Optional, Dict, Any

# Configure Decimal precision for ~0.01ps resolution
getcontext().prec = 14


class Command(IntEnum):
    """UART command codes for FPGA communication."""
    SET_COARSE = 0x01
    GET_COARSE = 0x02
    SET_EDGE = 0x03
    GET_EDGE = 0x04
    GET_STATUS = 0x05
    RESET_COUNT = 0x06
    SOFT_TRIGGER = 0x07
    SET_OUTPUT_TRIGGER_WIDTH = 0x08
    GET_OUTPUT_TRIGGER_WIDTH = 0x09
    SET_TRIGGER_MODE = 0x0A
    GET_TRIGGER_MODE = 0x0B
    SET_SOFT_TRIGGER_WIDTH = 0x0C
    GET_SOFT_TRIGGER_WIDTH = 0x0D
    SET_COUNTER_MODE = 0x0E
    GET_COUNTER_MODE = 0x0F
    SET_EDGE_COUNT_TARGET = 0x10
    GET_EDGE_COUNT_TARGET = 0x11
    RESET_EDGE_COUNT = 0x12
    ARM = 0x13
    DISARM = 0x14
    SET_ARMED_MODE = 0x15
    GET_ARMED_MODE = 0x16
    GET_ARMED = 0x17
    SET_FINE_OFFSET = 0x18
    GET_FINE_OFFSET = 0x19
    SET_FINE_WIDTH = 0x1A
    GET_FINE_WIDTH = 0x1B


class EdgeType(IntEnum):
    """Trigger edge detection types."""
    NONE = 0x00
    RISING = 0x01
    FALLING = 0x02
    BOTH = 0x03


class TriggerMode(IntEnum):
    """Trigger mode types."""
    EXTERNAL = 0x00
    INTERNAL = 0x01


class CounterMode(IntEnum):
    """Counter trigger mode types."""
    DISABLED = 0x00
    ENABLED = 0x01


class ArmedMode(IntEnum):
    """Armed mode types."""
    SINGLE = 0x00
    REPEAT = 0x01


class DelayUnit:
    """
    Control interface for FPGA-based trigger delay unit.

    All timing values use Decimal in seconds for precision.

    Resolution: ~8.93ps
    Range: 0 to ~21.5 seconds

    Example:
        with DelayUnit() as du:
            du.delay = Decimal("0.000000500")  # 500ns
            du.width = Decimal("0.000000010")  # 10ns
            du.arm()
    """

    BOARD_IDS = [
        (0x1337, 0x0099, "EMFI Lab DelayUnit"),
    ]

    # Timing constants
    COARSE_STEP_S = Decimal("0.000000005")  # 5ns
    FINE_STEPS_PER_CYCLE = 560
    FINE_STEP_S = COARSE_STEP_S / FINE_STEPS_PER_CYCLE  # ~8.93ps
    MAX_FINE_STEPS = 280  # Aliasing limit (50%)

    def __init__(self, port: Optional[str] = None):
        """
        Initialize DelayUnit connection.

        Args:
            port: Serial port path. If None, auto-detects board.

        Raises:
            RuntimeError: If board not found or connection fails
        """
        if port is None:
            port = self._find_board_port()
            if port is None:
                raise RuntimeError("No DelayUnit board found. Specify port manually.")

        try:
            self.ser = serial.Serial(port, 1000000, timeout=1)
            time.sleep(0.1)
        except serial.SerialException as e:
            raise RuntimeError(f"Failed to open serial port {port}: {e}")

    def _find_board_port(self) -> Optional[str]:
        for port_info in serial.tools.list_ports.comports():
            for vid, pid, _ in self.BOARD_IDS:
                if port_info.vid == vid and port_info.pid == pid:
                    return port_info.device
        return None

    def close(self):
        """Close the serial connection."""
        self.ser.close()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()

    # =========================================================================
    # Internal coarse/fine access (hidden from user)
    # =========================================================================

    def _get_coarse(self) -> Optional[int]:
        self.ser.write(bytes([Command.GET_COARSE]))
        data = self.ser.read(4)
        if len(data) == 4:
            return struct.unpack('<I', data)[0]
        return None

    def _set_coarse(self, cycles: int):
        self.ser.write(bytes([Command.SET_COARSE]))
        self.ser.write(struct.pack('<I', max(0, cycles)))

    def _get_fine_offset(self) -> Optional[int]:
        self.ser.write(bytes([Command.GET_FINE_OFFSET]))
        data = self.ser.read(4)
        if len(data) == 4:
            return struct.unpack('<i', data)[0]  # Signed
        return None

    def _set_fine_offset(self, steps: int):
        self.ser.write(bytes([Command.SET_FINE_OFFSET]))
        self.ser.write(struct.pack('<i', steps))  # Signed

    def _get_coarse_width(self) -> Optional[int]:
        self.ser.write(bytes([Command.GET_OUTPUT_TRIGGER_WIDTH]))
        data = self.ser.read(4)
        if len(data) == 4:
            return struct.unpack('<I', data)[0]
        return None

    def _set_coarse_width(self, cycles: int):
        self.ser.write(bytes([Command.SET_OUTPUT_TRIGGER_WIDTH]))
        self.ser.write(struct.pack('<I', max(1, cycles)))

    def _get_fine_width(self) -> Optional[int]:
        self.ser.write(bytes([Command.GET_FINE_WIDTH]))
        data = self.ser.read(4)
        if len(data) == 4:
            return struct.unpack('<i', data)[0]  # Signed
        return None

    def _set_fine_width(self, steps: int):
        self.ser.write(bytes([Command.SET_FINE_WIDTH]))
        self.ser.write(struct.pack('<i', steps))  # Signed

    def _split_time(self, seconds: Decimal) -> tuple[int, int]:
        """Split time into coarse cycles and fine steps with aliasing protection."""
        total_fine = seconds / self.FINE_STEP_S
        coarse = int(total_fine // self.FINE_STEPS_PER_CYCLE)
        fine = int(total_fine % self.FINE_STEPS_PER_CYCLE)

        # Aliasing protection: keep fine within ±280
        if fine > self.MAX_FINE_STEPS:
            coarse += 1
            fine -= self.FINE_STEPS_PER_CYCLE

        return coarse, fine

    def _combine_time(self, coarse: int, fine: int) -> Decimal:
        """Combine coarse cycles and fine steps into seconds."""
        return Decimal(coarse) * self.COARSE_STEP_S + Decimal(fine) * self.FINE_STEP_S

    # =========================================================================
    # Public API - Timing
    # =========================================================================

    @property
    def delay(self) -> Optional[Decimal]:
        """
        Get/set total delay in seconds (Decimal).

        Returns:
            Delay in seconds, or None if read fails
        """
        coarse = self._get_coarse()
        fine = self._get_fine_offset()
        if coarse is None or fine is None:
            return None
        return self._combine_time(coarse, fine)

    @delay.setter
    def delay(self, seconds: Decimal):
        """
        Set total delay in seconds.

        Args:
            seconds: Delay as Decimal in seconds
        """
        coarse, fine = self._split_time(seconds)
        self._set_coarse(coarse)
        self._set_fine_offset(fine)

    @property
    def width(self) -> Optional[Decimal]:
        """
        Get/set output pulse width in seconds (Decimal).

        Returns:
            Width in seconds, or None if read fails
        """
        coarse = self._get_coarse_width()
        fine = self._get_fine_width()
        if coarse is None or fine is None:
            return None
        return self._combine_time(coarse, fine)

    @width.setter
    def width(self, seconds: Decimal):
        """
        Set output pulse width in seconds.

        Args:
            seconds: Width as Decimal in seconds
        """
        coarse, fine = self._split_time(seconds)
        self._set_coarse_width(coarse)
        self._set_fine_width(fine)

    # =========================================================================
    # Public API - Trigger Configuration
    # =========================================================================

    @property
    def edge(self) -> Optional[EdgeType]:
        """Get/set trigger edge detection type."""
        self.ser.write(bytes([Command.GET_EDGE]))
        data = self.ser.read(1)
        if len(data) == 1:
            return EdgeType(data[0])
        return None

    @edge.setter
    def edge(self, edge_type: EdgeType):
        self.ser.write(bytes([Command.SET_EDGE, edge_type]))

    @property
    def trigger_mode(self) -> Optional[TriggerMode]:
        """Get/set trigger mode (EXTERNAL or INTERNAL)."""
        self.ser.write(bytes([Command.GET_TRIGGER_MODE]))
        data = self.ser.read(1)
        if len(data) == 1:
            return TriggerMode(data[0])
        return None

    @trigger_mode.setter
    def trigger_mode(self, mode: TriggerMode):
        self.ser.write(bytes([Command.SET_TRIGGER_MODE, mode]))

    @property
    def counter_mode(self) -> Optional[CounterMode]:
        """Get/set counter trigger mode."""
        self.ser.write(bytes([Command.GET_COUNTER_MODE]))
        data = self.ser.read(1)
        if len(data) == 1:
            return CounterMode(data[0])
        return None

    @counter_mode.setter
    def counter_mode(self, mode: CounterMode):
        self.ser.write(bytes([Command.SET_COUNTER_MODE, mode]))

    @property
    def edge_count_target(self) -> Optional[int]:
        """Get/set edge count target for counter mode."""
        self.ser.write(bytes([Command.GET_EDGE_COUNT_TARGET]))
        data = self.ser.read(4)
        if len(data) == 4:
            return struct.unpack('<I', data)[0]
        return None

    @edge_count_target.setter
    def edge_count_target(self, count: int):
        self.ser.write(bytes([Command.SET_EDGE_COUNT_TARGET]))
        self.ser.write(struct.pack('<I', count))

    @property
    def armed_mode(self) -> Optional[ArmedMode]:
        """Get/set armed mode (SINGLE or REPEAT)."""
        self.ser.write(bytes([Command.GET_ARMED_MODE]))
        data = self.ser.read(1)
        if len(data) == 1:
            return ArmedMode(data[0])
        return None

    @armed_mode.setter
    def armed_mode(self, mode: ArmedMode):
        self.ser.write(bytes([Command.SET_ARMED_MODE, mode]))

    @property
    def armed(self) -> Optional[bool]:
        """Get current armed state."""
        self.ser.write(bytes([Command.GET_ARMED]))
        data = self.ser.read(1)
        if len(data) == 1:
            return bool(data[0])
        return None

    # =========================================================================
    # Public API - Actions
    # =========================================================================

    def arm(self) -> bool:
        """Arm the trigger."""
        self.ser.write(bytes([Command.ARM]))
        return True

    def disarm(self) -> bool:
        """Disarm the trigger."""
        self.ser.write(bytes([Command.DISARM]))
        return True

    def soft_trigger(self) -> bool:
        """Generate a soft trigger pulse."""
        self.ser.write(bytes([Command.SOFT_TRIGGER]))
        time.sleep(0.001)
        return True

    def reset_counter(self) -> bool:
        """Reset the trigger counter."""
        self.ser.write(bytes([Command.RESET_COUNT]))
        return True

    def reset_edge_count(self) -> bool:
        """Reset the edge counter."""
        self.ser.write(bytes([Command.RESET_EDGE_COUNT]))
        return True

    @property
    def status(self) -> Optional[Dict[str, Any]]:
        """
        Get full system status.

        Returns dict with:
            - delay: Total delay in seconds (Decimal)
            - width: Total width in seconds (Decimal)
            - trigger_count: Number of triggers fired
            - armed: Whether trigger is armed
            - trigger_mode: EXTERNAL or INTERNAL
            - armed_mode: SINGLE or REPEAT
            - counter_mode: DISABLED or ENABLED
            - edge_type: NONE, RISING, FALLING, or BOTH
            - mmcm_locked: Whether MMCM PLLs are locked
            - phase_shift_ready: Whether phase shifting is complete
        """
        self.ser.write(bytes([Command.GET_STATUS]))
        data = self.ser.read(26)
        if len(data) == 26:
            trigger_count = struct.unpack('<H', data[0:2])[0]
            coarse_delay = struct.unpack('<I', data[2:6])[0]
            fine_offset = struct.unpack('<i', data[6:10])[0]
            coarse_width = struct.unpack('<I', data[10:14])[0]
            fine_width = struct.unpack('<i', data[14:18])[0]

            return {
                'delay': self._combine_time(coarse_delay, fine_offset),
                'width': self._combine_time(coarse_width, fine_width),
                'trigger_count': trigger_count,
                'armed': bool(data[18]),
                'trigger_mode': TriggerMode(data[19]),
                'armed_mode': ArmedMode(data[20]),
                'counter_mode': CounterMode(data[21]),
                'mmcm_locked': bool(data[22]),
                'phase_shift_ready': bool(data[23]),
                'edge_type': EdgeType(data[24]),
            }
        return None

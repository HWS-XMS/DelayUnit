"""
Core module for DelayUnit - FPGA-based picosecond delay control.
"""

import serial
import serial.tools.list_ports
import struct
import time
from enum import IntEnum
from typing import Optional, Dict, Any


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


class EdgeType(IntEnum):
    """Trigger edge detection types."""
    NONE = 0x00
    RISING = 0x01
    FALLING = 0x02
    BOTH = 0x03


class TriggerMode(IntEnum):
    """Trigger mode types."""
    EXTERNAL = 0x00  # Receive trigger from DuT
    INTERNAL = 0x01  # Generate trigger for DuT


class DelayUnit:
    """
    Control interface for FPGA-based trigger delay unit.

    This class provides high-level control of a trigger delay system
    implemented on Xilinx FPGAs with clock cycle delay.

    Resolution: 5ns per clock cycle (200MHz system clock)
    Range: 0 to 2^32-1 cycles (0 to 21.5 seconds)

    Attributes:
        port: Serial port for UART communication
        baudrate: UART baud rate (default 1Mbaud)
    """
    
    # Supported board USB identifiers
    # Only custom programmed DelayUnit with unique VID/PID
    BOARD_IDS = [
        (0x1337, 0x0099, "EMFI Lab DelayUnit"),
    ]

    def __init__(self, port: Optional[str] = None):
        """
        Initialize DelayUnit connection.

        Args:
            port: Serial port path (e.g., '/dev/ttyUSB2'). If None, auto-detects board.

        Raises:
            RuntimeError: If board not found or connection fails
        """
        if port is None:
            port = self._find_board_port()
            if port is None:
                vid_pid_list = ", ".join([f"{vid:04X}:{pid:04X}" for vid, pid, _ in self.BOARD_IDS])
                raise RuntimeError(
                    f"No supported board found (searched VID:PID = {vid_pid_list}). "
                    "Please ensure the board is connected and drivers are installed.\n"
                    "Alternatively, specify the port manually: DelayUnit(port='/dev/ttyUSBx')"
                )

        try:
            self.ser = serial.Serial(port, 1000000, timeout=1)
            time.sleep(0.1)  # Allow serial to settle
        except serial.SerialException as e:
            raise RuntimeError(f"Failed to open serial port {port}: {e}")

    def _find_board_port(self) -> Optional[str]:
        """
        Search for DelayUnit with custom VID/PID among connected USB devices.

        Returns:
            Serial port path if found, None otherwise
        """
        for port_info in serial.tools.list_ports.comports():
            for vid, pid, board_name in self.BOARD_IDS:
                if port_info.vid == vid and port_info.pid == pid:
                    return port_info.device
        return None
    
    def close(self):
        """Close the serial connection."""
        self.ser.close()
    
    def __enter__(self):
        """Context manager entry."""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit - ensures serial port is closed."""
        self.close()
    
    @property
    def edge(self) -> Optional[EdgeType]:
        """
        Get/set trigger edge detection type.
        
        Returns:
            EdgeType enum value, or None if read fails
        """
        self.ser.write(bytes([Command.GET_EDGE]))
        data = self.ser.read(1)
        if len(data) == 1:
            return EdgeType(data[0])
        return None
    
    @edge.setter
    def edge(self, edge_type: EdgeType):
        """
        Set trigger edge detection type.
        
        Args:
            edge_type: EdgeType enum value
        """
        self.ser.write(bytes([Command.SET_EDGE, edge_type]))
    
    @property
    def coarse(self) -> Optional[int]:
        """
        Get/set coarse delay in clock cycles.
        
        Returns:
            Coarse delay in clock cycles, or None if read fails
        """
        self.ser.write(bytes([Command.GET_COARSE]))
        data = self.ser.read(4)
        if len(data) == 4:
            return struct.unpack('<I', data)[0]
        return None
    
    @coarse.setter
    def coarse(self, cycles: int):
        """
        Set coarse delay in clock cycles.

        Args:
            cycles: Number of clock cycles (5ns each at 200MHz)
        """
        self.ser.write(bytes([Command.SET_COARSE]))
        self.ser.write(struct.pack('<I', cycles))
    
    @property
    def status(self) -> Optional[Dict[str, Any]]:
        """
        Get system status including trigger count and delay.

        Returns:
            Dictionary with status information, or None if read fails
        """
        self.ser.write(bytes([Command.GET_STATUS]))
        data = self.ser.read(6)
        if len(data) == 6:
            trigger_count = struct.unpack('<H', data[0:2])[0]
            coarse_cycles = struct.unpack('<I', data[2:6])[0]

            # Each cycle is 5ns (200MHz clock)
            actual_delay_ns = coarse_cycles * 5.0

            return {
                'trigger_count': trigger_count,
                'coarse_cycles': coarse_cycles,
                'delay_ns': actual_delay_ns
            }
        return None
    
    @property
    def delay_ns(self) -> Optional[float]:
        """
        Get/set total delay in nanoseconds.

        Returns:
            Total delay in nanoseconds, or None if read fails
        """
        coarse_cycles = self.coarse
        if coarse_cycles is None:
            return None
        # Each cycle is 5ns (200MHz clock)
        return coarse_cycles * 5.0

    @delay_ns.setter
    def delay_ns(self, nanoseconds: float):
        """
        Set total delay in nanoseconds.

        Args:
            nanoseconds: Total delay in nanoseconds (5ns resolution)
        """
        # Calculate cycles (5ns per cycle at 200MHz)
        coarse_cycles = int(round(nanoseconds / 5.0))
        self.coarse = coarse_cycles

    def reset_counter(self) -> bool:
        """
        Reset the trigger counter.

        Returns:
            True if successful
        """
        self.ser.write(bytes([Command.RESET_COUNT]))
        return True

    def soft_trigger(self) -> bool:
        """
        Generate a soft trigger pulse (single cycle on JA-3).

        Returns:
            True if successful
        """
        self.ser.write(bytes([Command.SOFT_TRIGGER]))
        time.sleep(0.001)  # Small delay for pulse to complete
        return True

    @property
    def output_trigger_width_cycles(self) -> Optional[int]:
        """
        Get/set output trigger pulse width in clock cycles.

        Returns:
            Pulse width in clock cycles, or None if read fails
        """
        self.ser.write(bytes([Command.GET_OUTPUT_TRIGGER_WIDTH]))
        data = self.ser.read(4)
        if len(data) == 4:
            return struct.unpack('<I', data)[0]
        return None

    @output_trigger_width_cycles.setter
    def output_trigger_width_cycles(self, cycles: int):
        """
        Set output trigger pulse width in clock cycles.

        Args:
            cycles: Number of clock cycles (5ns each at 200MHz)
        """
        self.ser.write(bytes([Command.SET_OUTPUT_TRIGGER_WIDTH]))
        self.ser.write(struct.pack('<I', cycles))

    @property
    def output_trigger_width_ns(self) -> Optional[float]:
        """
        Get/set output trigger pulse width in nanoseconds.

        Returns:
            Pulse width in nanoseconds, or None if read fails
        """
        cycles = self.output_trigger_width_cycles
        if cycles is None:
            return None
        # Each cycle is 5ns (200MHz clock)
        return cycles * 5.0

    @output_trigger_width_ns.setter
    def output_trigger_width_ns(self, nanoseconds: float):
        """
        Set output trigger pulse width in nanoseconds.

        Args:
            nanoseconds: Pulse width in nanoseconds (5ns resolution)
        """
        # Calculate cycles (5ns per cycle at 200MHz)
        cycles = int(round(nanoseconds / 5.0))
        if cycles < 1:
            cycles = 1  # Minimum 1 cycle
        self.output_trigger_width_cycles = cycles

    @property
    def trigger_mode(self) -> Optional[TriggerMode]:
        """
        Get/set trigger mode.

        Returns:
            TriggerMode enum value, or None if read fails
        """
        self.ser.write(bytes([Command.GET_TRIGGER_MODE]))
        data = self.ser.read(1)
        if len(data) == 1:
            return TriggerMode(data[0])
        return None

    @trigger_mode.setter
    def trigger_mode(self, mode: TriggerMode):
        """
        Set trigger mode.

        Args:
            mode: TriggerMode enum value (EXTERNAL or INTERNAL)
        """
        self.ser.write(bytes([Command.SET_TRIGGER_MODE, mode]))

    @property
    def soft_trigger_width_cycles(self) -> Optional[int]:
        """
        Get/set soft trigger pulse width in clock cycles.

        Returns:
            Pulse width in clock cycles, or None if read fails
        """
        self.ser.write(bytes([Command.GET_SOFT_TRIGGER_WIDTH]))
        data = self.ser.read(4)
        if len(data) == 4:
            return struct.unpack('<I', data)[0]
        return None

    @soft_trigger_width_cycles.setter
    def soft_trigger_width_cycles(self, cycles: int):
        """
        Set soft trigger pulse width in clock cycles.

        Args:
            cycles: Number of clock cycles (5ns each at 200MHz)
        """
        self.ser.write(bytes([Command.SET_SOFT_TRIGGER_WIDTH]))
        self.ser.write(struct.pack('<I', cycles))

    @property
    def soft_trigger_width_ns(self) -> Optional[float]:
        """
        Get/set soft trigger pulse width in nanoseconds.

        Returns:
            Pulse width in nanoseconds, or None if read fails
        """
        cycles = self.soft_trigger_width_cycles
        if cycles is None:
            return None
        # Each cycle is 5ns (200MHz clock)
        return cycles * 5.0

    @soft_trigger_width_ns.setter
    def soft_trigger_width_ns(self, nanoseconds: float):
        """
        Set soft trigger pulse width in nanoseconds.

        Args:
            nanoseconds: Pulse width in nanoseconds (5ns resolution)
        """
        # Calculate cycles (5ns per cycle at 200MHz)
        cycles = int(round(nanoseconds / 5.0))
        if cycles < 1:
            cycles = 1  # Minimum 1 cycle
        self.soft_trigger_width_cycles = cycles
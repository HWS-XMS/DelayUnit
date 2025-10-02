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
    SET_FINE = 0x07
    GET_FINE = 0x08


class EdgeType(IntEnum):
    """Trigger edge detection types."""
    NONE = 0x00
    RISING = 0x01
    FALLING = 0x02
    BOTH = 0x03


class DelayUnit:
    """
    Control interface for FPGA-based picosecond delay unit.
    
    This class provides high-level control of a trigger delay system
    implemented on Xilinx FPGAs with MMCM-based fine delay adjustment.
    
    Resolution: 17.0068ps per step (1050MHz VCO / 56 steps)
    Range: Unlimited (coarse + fine delay combination)
    
    Attributes:
        port: Serial port for UART communication
        baudrate: UART baud rate (default 115200)
    """
    
    # Digilent Arty USB identifiers
    ARTY_VID = 0x0403  # FTDI vendor ID
    ARTY_PID = 0x6010  # FT2232H product ID used by Arty
    
    def __init__(self):
        """
        Initialize DelayUnit connection.
        
        Automatically searches for and connects to Digilent Arty board
        at 1Mbaud.
        
        Raises:
            RuntimeError: If Arty board not found or connection fails
        """
        port = self._find_arty_port()
        if port is None:
            raise RuntimeError(
                f"Digilent Arty board not found (VID:PID = {self.ARTY_VID:04X}:{self.ARTY_PID:04X}). "
                "Please ensure the board is connected and drivers are installed."
            )
        
        try:
            self.ser = serial.Serial(port, 1000000, timeout=1)
            time.sleep(0.1)  # Allow serial to settle
        except serial.SerialException as e:
            raise RuntimeError(f"Failed to open serial port {port}: {e}")
    
    def _find_arty_port(self) -> Optional[str]:
        """
        Search for Digilent Arty board among connected USB devices.
        
        Returns:
            Serial port path if found, None otherwise
        """
        for port_info in serial.tools.list_ports.comports():
            if port_info.vid == self.ARTY_VID and port_info.pid == self.ARTY_PID:
                # Arty has two serial ports (JTAG and UART), typically the second one is UART
                # On Linux: /dev/ttyUSB1, on Windows: higher COM port number
                # We can identify by checking if it's the second interface
                if 'usbserial' in port_info.location or port_info.location.endswith('1'):
                    return port_info.device
                # If we can't determine which interface, try the port anyway
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
            cycles: Number of clock cycles (10ns each at 100MHz)
        """
        self.ser.write(bytes([Command.SET_COARSE]))
        self.ser.write(struct.pack('<I', cycles))
    
    @property
    def fine(self) -> Optional[int]:
        """
        Get/set fine delay in picoseconds.
        
        Returns:
            Fine delay in picoseconds, or None if read fails
        """
        self.ser.write(bytes([Command.GET_FINE]))
        data = self.ser.read(2)
        if len(data) == 2:
            return struct.unpack('<H', data)[0]
        return None
    
    @fine.setter
    def fine(self, picoseconds: int):
        """
        Set fine delay in picoseconds (0-9999ps).
        
        Args:
            picoseconds: Fine delay in picoseconds
        """
        self.ser.write(bytes([Command.SET_FINE]))
        self.ser.write(struct.pack('<H', picoseconds))
    
    @property
    def status(self) -> Optional[Dict[str, Any]]:
        """
        Get system status including trigger count and delays.
        
        Returns:
            Dictionary with status information, or None if read fails
        """
        self.ser.write(bytes([Command.GET_STATUS]))
        data = self.ser.read(8)
        if len(data) == 8:
            trigger_count = struct.unpack('<H', data[0:2])[0]
            coarse_cycles = struct.unpack('<I', data[2:6])[0]
            fine_ps = struct.unpack('<H', data[6:8])[0]

            # FPGA stores requested values, not quantized
            # Conversion happens internally in MMCM
            actual_total_ps = coarse_cycles * 10000 + fine_ps
            
            return {
                'trigger_count': trigger_count,
                'coarse_cycles': coarse_cycles,
                'fine_ps_requested': fine_ps,
                'actual_delay_ps': actual_total_ps,
                'actual_delay_ns': actual_total_ps / 1000.0
            }
        return None
    
    @property
    def delay_ps(self) -> Optional[int]:
        """
        Get/set total delay in picoseconds.

        When setting, automatically splits the delay into coarse (clock cycles)
        and fine (MMCM phase shift) components.

        Returns:
            Total delay in picoseconds, or None if read fails
        """
        # Get coarse delay
        coarse_cycles = self.coarse
        if coarse_cycles is None:
            return None

        # Get fine delay
        fine_ps = self.fine
        if fine_ps is None:
            return None

        # FPGA stores the requested value, not the quantized value
        # Conversion to steps happens internally in MMCM
        return coarse_cycles * 10000 + fine_ps

    @delay_ps.setter
    def delay_ps(self, picoseconds: int):
        """
        Set total delay in picoseconds.

        Args:
            picoseconds: Total delay in picoseconds
        """
        # Calculate coarse cycles (10000ps per cycle at 100MHz)
        coarse_cycles = int(picoseconds // 10000)
        # Calculate fine delay (remainder, up to 9999ps)
        fine_ps = int(picoseconds % 10000)

        # Set coarse delay
        self.coarse = coarse_cycles
        time.sleep(0.01)

        # Set fine delay
        self.fine = fine_ps

    def reset_counter(self) -> bool:
        """
        Reset the trigger counter.
        
        Returns:
            True if successful
        """
        self.ser.write(bytes([Command.RESET_COUNT]))
        return True
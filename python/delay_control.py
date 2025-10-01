#!/usr/bin/env python3
"""
Trigger Delay Control Script
Controls the FPGA-based trigger delay system via UART

Resolution: 20.12ps per step (887.5MHz VCO / 56 steps)
Math: steps = ps * 50 / 1006 (avoids floating point)
"""

import serial
import struct
import time
import argparse
from enum import IntEnum

class Command(IntEnum):
    SET_COARSE = 0x01
    GET_COARSE = 0x02
    SET_EDGE = 0x03
    GET_EDGE = 0x04
    GET_STATUS = 0x05
    RESET_COUNT = 0x06
    SET_FINE = 0x07
    GET_FINE = 0x08

class EdgeType(IntEnum):
    NONE = 0x00
    RISING = 0x01
    FALLING = 0x02
    BOTH = 0x03

class DelayUnit:
    # Digilent Arty USB identifiers
    ARTY_VID = 0x0403  # FTDI vendor ID
    ARTY_PID = 0x6010  # FT2232H product ID used by Arty
    
    def __init__(self):
        port = self._find_arty_port()
        if port is None:
            raise RuntimeError(
                f"Digilent Arty board not found (VID:PID = {self.ARTY_VID:04X}:{self.ARTY_PID:04X}). "
                "Please ensure the board is connected and drivers are installed."
            )
        print(f"Found Arty board on {port}")
        
        self.ser = serial.Serial(port, 1000000, timeout=1)
        time.sleep(0.1)  # Allow serial to settle
    
    def _find_arty_port(self):
        """Search for Digilent Arty board among connected USB devices."""
        import serial.tools.list_ports
        for port_info in serial.tools.list_ports.comports():
            if port_info.vid == self.ARTY_VID and port_info.pid == self.ARTY_PID:
                # Arty has two serial ports (JTAG and UART), typically the second one is UART
                if 'usbserial' in port_info.location or port_info.location.endswith('1'):
                    return port_info.device
                return port_info.device
        return None
    
    def close(self):
        self.ser.close()
    
    def set_delay(self, picoseconds):
        """Set total delay in picoseconds, automatically splitting coarse/fine"""
        # Calculate coarse cycles (10000ps per cycle at 100MHz)
        coarse_cycles = int(picoseconds // 10000)
        # Calculate fine delay (remainder, up to 9999ps)
        fine_ps = int(picoseconds % 10000)
        
        # Set coarse delay
        self.ser.write(bytes([Command.SET_COARSE]))
        self.ser.write(struct.pack('<I', coarse_cycles))
        time.sleep(0.01)
        
        # Set fine delay  
        self.ser.write(bytes([Command.SET_FINE]))
        self.ser.write(struct.pack('<H', fine_ps))
        
        # Return what was set
        return {
            'requested_ps': picoseconds,
            'coarse_cycles': coarse_cycles,
            'fine_ps': fine_ps,
            'actual_ps': self.get_delay()  # Read back actual value
        }
    
    def get_delay(self):
        """Get actual configured delay in picoseconds"""
        # Get coarse delay
        self.ser.write(bytes([Command.GET_COARSE]))
        data = self.ser.read(4)
        if len(data) != 4:
            return None
        coarse_cycles = struct.unpack('<I', data)[0]
        
        # Get fine delay
        self.ser.write(bytes([Command.GET_FINE]))
        data = self.ser.read(2)
        if len(data) != 2:
            return None
        fine_ps = struct.unpack('<H', data)[0]
        
        # Calculate actual delay in ps
        # With 887.5MHz VCO: each step is 20.12ps
        # steps = ps * 50 / 1006 (matches FPGA calculation)
        steps = (fine_ps * 50) // 1006
        actual_fine_ps = (steps * 2012) // 100  # steps * 20.12
        
        return coarse_cycles * 10000 + actual_fine_ps
    
    def set_edge_type(self, edge_type):
        """Set trigger edge detection type"""
        self.ser.write(bytes([Command.SET_EDGE, edge_type]))
        return True
    
    def get_edge_type(self):
        """Get current edge detection type"""
        self.ser.write(bytes([Command.GET_EDGE]))
        data = self.ser.read(1)
        if len(data) == 1:
            return EdgeType(data[0])
        return None
    
    def get_status(self):
        """Get system status including trigger count and delays"""
        self.ser.write(bytes([Command.GET_STATUS]))
        data = self.ser.read(8)
        if len(data) == 8:
            trigger_count = struct.unpack('<H', data[0:2])[0]
            coarse_cycles = struct.unpack('<I', data[2:6])[0]
            fine_ps = struct.unpack('<H', data[6:8])[0]
            
            # Calculate actual delay with 20.12ps resolution
            steps = (fine_ps * 50) // 1006
            actual_fine_ps = (steps * 2012) // 100
            actual_total_ps = coarse_cycles * 10000 + actual_fine_ps
            
            return {
                'trigger_count': trigger_count,
                'coarse_cycles': coarse_cycles,
                'fine_ps_requested': fine_ps,
                'actual_delay_ps': actual_total_ps,
                'actual_delay_ns': actual_total_ps / 1000.0
            }
        return None
    
    def reset_counter(self):
        """Reset the trigger counter"""
        self.ser.write(bytes([Command.RESET_COUNT]))
        return True

def main():
    parser = argparse.ArgumentParser(description='Control FPGA trigger delay')
    
    subparsers = parser.add_subparsers(dest='command', help='Commands')
    
    # Set delay command
    set_parser = subparsers.add_parser('set', help='Set delay in picoseconds')
    set_parser.add_argument('delay', type=int, help='Delay in picoseconds')
    
    # Get delay command
    subparsers.add_parser('get', help='Get actual configured delay')
    
    # Get status command
    subparsers.add_parser('status', help='Get system status')
    
    # Set edge command
    edge_parser = subparsers.add_parser('edge', help='Set edge type')
    edge_parser.add_argument('type', choices=['none', 'rising', 'falling', 'both'])
    
    # Reset counter command
    subparsers.add_parser('reset', help='Reset trigger counter')
    
    # Test sweep command
    sweep_parser = subparsers.add_parser('sweep', help='Sweep delay range')
    sweep_parser.add_argument('start', type=int, help='Start delay (ps)')
    sweep_parser.add_argument('stop', type=int, help='Stop delay (ps)')
    sweep_parser.add_argument('step', type=int, help='Step size (ps)')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    try:
        controller = DelayUnit()
    except RuntimeError as e:
        print(f"Error: {e}")
        return
    
    try:
        if args.command == 'set':
            result = controller.set_delay(args.delay)
            print(f"Requested: {result['requested_ps']} ps ({result['requested_ps']/1000:.3f} ns)")
            print(f"Configured:")
            print(f"  Coarse: {result['coarse_cycles']} cycles ({result['coarse_cycles']*10000} ps)")
            print(f"  Fine: {result['fine_ps']} ps")
            if result['actual_ps']:
                print(f"Actual: {result['actual_ps']} ps ({result['actual_ps']/1000:.3f} ns)")
                error = result['actual_ps'] - result['requested_ps']
                print(f"Error: {error:+d} ps ({abs(error/result['requested_ps']*100):.2f}%)")
        
        elif args.command == 'get':
            actual_ps = controller.get_delay()
            if actual_ps is not None:
                print(f"Actual delay: {actual_ps} ps ({actual_ps/1000:.3f} ns)")
            else:
                print("Failed to read delay")
        
        elif args.command == 'status':
            status = controller.get_status()
            if status:
                print(f"Trigger count: {status['trigger_count']}")
                print(f"Coarse: {status['coarse_cycles']} cycles")
                print(f"Fine requested: {status['fine_ps_requested']} ps")
                print(f"Actual delay: {status['actual_delay_ps']} ps ({status['actual_delay_ns']:.3f} ns)")
            else:
                print("Failed to get status")
        
        elif args.command == 'edge':
            edge_map = {
                'none': EdgeType.NONE,
                'rising': EdgeType.RISING,
                'falling': EdgeType.FALLING,
                'both': EdgeType.BOTH
            }
            controller.set_edge_type(edge_map[args.type])
            print(f"Edge type set to: {args.type}")
        
        elif args.command == 'reset':
            controller.reset_counter()
            print("Counter reset")
        
        elif args.command == 'sweep':
            print(f"Sweeping delay from {args.start} ps to {args.stop} ps")
            delay = args.start
            while delay <= args.stop:
                result = controller.set_delay(delay)
                time.sleep(0.1)
                status = controller.get_status()
                if status:
                    print(f"  {delay:7d} ps: actual={status['actual_delay_ps']:7d} ps, triggers={status['trigger_count']}")
                delay += args.step
    
    finally:
        controller.close()

if __name__ == '__main__':
    main()
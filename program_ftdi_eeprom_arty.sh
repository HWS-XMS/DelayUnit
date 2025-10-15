#!/bin/bash
# Program Arty A7 board with DelayUnit VID/PID
# Run this script to convert an Arty A7 board into a DelayUnit

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/delayunit_eeprom.conf"

echo "================================================"
echo "  Program Arty A7 as DelayUnit"
echo "================================================"
echo ""
echo "This will program the FTDI EEPROM with:"
echo "  VID: 0x1337"
echo "  PID: 0x0099"
echo "  Manufacturer: EMFI Lab"
echo "  Product: DelayUnit"
echo ""
echo "Target device: Arty A7 (FT2232H, VID=0x0403 PID=0x6010)"
echo ""
echo "WARNING: Arty A7 has TWO FTDI interfaces."
echo "         This will program BOTH interfaces with the same VID/PID."
echo "         Only ONE interface will be used for UART communication."
echo ""

# Search for Arty A7
DEVICE_SERIAL=$(lsusb -v -d 0403:6010 2>/dev/null | grep iSerial | head -1 | awk '{print $3}')

if [ -z "$DEVICE_SERIAL" ]; then
    echo "ERROR: No Arty A7 board found (VID=0x0403 PID=0x6010)"
    echo "Please ensure the board is connected via USB."
    exit 1
fi

echo "Found Arty A7 with serial: $DEVICE_SERIAL"
echo ""
read -p "Continue programming? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Backing up current EEPROM..."
ftdi_eeprom --device s:0x0403:0x6010:$DEVICE_SERIAL --read-eeprom "$SCRIPT_DIR/delayunit_read.conf"

echo "Programming new VID/PID..."
sudo ftdi_eeprom --device s:0x0403:0x6010:$DEVICE_SERIAL --flash-eeprom "$CONFIG_FILE"

echo ""
echo "================================================"
echo "  Programming complete!"
echo "================================================"
echo ""
echo "IMPORTANT: Unplug and replug the USB cable for changes to take effect."
echo ""
echo "After reconnecting, register the new VID/PID with the kernel:"
echo "  echo 1337 0099 | sudo tee /sys/bus/usb-serial/drivers/ftdi_sio/new_id"
echo ""
echo "NOTE: Arty A7 will create TWO serial ports. The DelayUnit code"
echo "      will automatically select the correct one."
echo ""

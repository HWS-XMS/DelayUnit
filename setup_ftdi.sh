#!/bin/bash
# Setup FTDI driver for DelayUnit custom VID:PID (1337:0099)

VID="1337"
PID="0099"

# Check if ftdi_sio module is loaded
if lsmod | grep -q "ftdi_sio"; then
    echo "ftdi_sio module already loaded"
else
    echo "Loading ftdi_sio module..."
    sudo modprobe ftdi_sio
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to load ftdi_sio module"
        exit 1
    fi
    echo "ftdi_sio module loaded"
fi

# Add custom VID:PID
echo "Adding custom VID:PID ${VID}:${PID}..."
echo ${VID} ${PID} | sudo tee /sys/bus/usb-serial/drivers/ftdi_sio/new_id

if [ $? -eq 0 ]; then
    echo "Setup complete. DelayUnit should now be available as /dev/ttyUSBx"
else
    echo "ERROR: Failed to add VID:PID"
    exit 1
fi

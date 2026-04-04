#!/bin/bash
set -e

# Sync filesystem to ensure data safety before power cut
sync

# Ensure i2c-dev kernel module is loaded so we can communicate with i2c devices
modprobe i2c-dev || true

# Ensure the AXP20x driver is unbound to prevent kernel interference
echo '0-0034' > /sys/bus/i2c/drivers/axp20x-i2c/unbind 2>/dev/null || true

# Wait briefly for the hardware/driver to settle
sleep 0.5

# Force power off via I2C command
# Register 0x32 on AXP209/AXP22x is the Shutdown control
# 0xcb (11001011) sets the shutdown bit
/usr/bin/i2cset -y 0 0x34 0x32 0xcb

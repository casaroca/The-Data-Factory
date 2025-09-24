#!/bin/bash
set -e

echo "--- Setting up Main Data Factory Monitor v5 ---"

# --- 1. Define Paths ---
MONITOR_DIR="/factory/workers/monitors/main_monitor_v5"
LOG_DIR="/factory/logs"
USER="tdf"

# --- 2. Create Directory ---
echo "[+] Creating monitor directory..."
mkdir -p $MONITOR_DIR

# --- 3. Create the Monitor Script ---
echo "[+] Creating main_monitor.sh file..."
cp /home/tdf/main_monitor.sh $MONITOR_DIR/main_monitor.sh

# --- 4. Make the monitor script executable and set permissions ---
chmod +x $MONITOR_DIR/main_monitor.sh
sudo chown -R $USER:$USER $MONITOR_DIR

echo "--- Main Factory Monitor Setup Complete v5 ---"
echo "You can now run the monitor with the command:"
echo "$MONITOR_DIR/main_monitor.sh"

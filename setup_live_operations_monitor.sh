#!/bin/bash
set -e

echo "--- Setting up Live Operations Monitor ---"

# --- 1. Define Paths ---
MONITOR_DIR="/factory/workers/monitors/live_operations_monitor"
USER="tdf"

# --- 2. Create Directory ---
echo "[+] Creating monitor directory..."
mkdir -p $MONITOR_DIR

# --- 3. Create the Monitor Script ---
echo "[+] Creating live_operations_monitor.sh file..."
cp /home/tdf/live_operations_monitor.sh $MONITOR_DIR/live_operations_monitor.sh

# --- 4. Make the monitor script executable and set permissions ---
chmod +x $MONITOR_DIR/live_operations_monitor.sh
sudo chown -R $USER:$USER $MONITOR_DIR

echo "--- Live Operations Monitor Setup Complete ---"
echo "You can now run the monitor with the command:"
echo "$MONITOR_DIR/live_operations_monitor.sh"

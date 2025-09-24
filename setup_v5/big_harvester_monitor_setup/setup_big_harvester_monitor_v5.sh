#!/bin/bash
set -e

echo "--- Setting up Monitor for Big Harvester v1 v5 ---"

# --- 1. Define Paths ---
PROJECT_DIR="/factory/workers/monitors/big_harvester_v1_v5"
LOG_DIR="/factory/logs"
DB_PATH="/factory/db/big_harvester_log.db"
RAW_DUMP_DIR="/mnt/harvested_data/big_harvester_output"
USER="tdf"

# --- 2. Create the monitoring script ---
echo "[+] Creating monitoring script..."
cat << 'EOF' > $PROJECT_DIR/monitor.sh
#!/bin/bash
echo "=== Big Harvester v1 Status ==="
echo ""
echo "Service Status:"
sudo systemctl status big_harvester_v1 --no-pager -l
echo -e "\nLast 10 log entries:"
tail -n 10 /factory/logs/big_harvester_v1.log
echo -e "\nDisk Usage:"
df -h /mnt/harvested_data
echo -e "\nMemory Usage:"
free -h
echo -e "\nDatabase Stats (Today):"
sqlite3 /factory/db/big_harvester_log.db "SELECT date, archives_processed, ROUND(total_gb, 2) as size_gb FROM daily_stats WHERE date = date('now');"
EOF

# --- 3. Make the monitor script executable and set permissions ---
chmod +x $PROJECT_DIR/monitor.sh
sudo chown -R $USER:$USER $PROJECT_DIR

echo ""
echo "--- Harvester Monitor Setup Complete v5 ---"
echo "You can now run the monitor with:"
echo "watch -n 10 $PROJECT_DIR/monitor.sh"

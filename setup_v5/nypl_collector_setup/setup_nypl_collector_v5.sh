#!/bin/bash
set -e

echo "--- Setting up NYPL Collector v5 ---"

# --- 1. Define Absolute Paths ---
PROJECT_DIR="/factory/workers/collectors/nypl_collector_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/nypl_collector.log"
DUMP_DIR="/factory/data/raw/nypl_api"
USER="tdf"

# --- 2. Create Project Directory ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $DUMP_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE

# --- 3. Create Application Files ---
echo "[+] Creating NYPL Collector application files..."
cp /home/tdf/nypl_collector.py $PROJECT_DIR/nypl_collector.py

# --- 4. Create requirements.txt file ---
echo "[+] Creating requirements.txt file..."
cat << 'EOF' > $PROJECT_DIR/requirements.txt
requests
EOF

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/nypl_collector_v5.service
[Unit]
Description=NYPL Collector Service v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 nypl_collector.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting NYPL Collector service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $DUMP_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start nypl_collector_v5
sudo systemctl enable nypl_collector_v5

echo "--- NYPL Collector Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status nypl_collector_v5"
echo "To watch the logs, run: tail -f /factory/logs/nypl_collector.log"
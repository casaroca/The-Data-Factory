#!/bin/bash
set -e

echo "--- Setting up DPLA Harvester v5 ---"

# --- 1. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/dpla_harvester_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/dpla_harvester.log"
RAW_DUMP_DIR="/factory/data/raw/dpla_harvest"
USER="tdf"

# --- 2. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $RAW_DUMP_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE

# --- 3. Create Application Files ---
echo "[+] Creating dpla_harvester.py application file..."
cp /home/tdf/dpla_harvester.py $PROJECT_DIR/dpla_harvester.py

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
sudo bash -c "cat << EOF > /etc/systemd/system/dpla_harvester_v5.service
[Unit]
Description=DPLA Harvester Service v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 dpla_harvester.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting DPLA Harvester service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $RAW_DUMP_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start dpla_harvester_v5
sudo systemctl enable dpla_harvester_v5

echo "--- DPLA Harvester Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status dpla_harvester_v5"
echo "To watch the logs, run: tail -f /factory/logs/dpla_harvester.log"

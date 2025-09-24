#!/bin/bash
set -e

echo "--- Setting up Targeted Ebook Collector v5 ---"

# --- 1. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/targeted_collector_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/targeted_collector.log"
BOOK_DEPOSIT_DIR="/library/book_deposit"
USER="tdf"

# --- 2. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $BOOK_DEPOSIT_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE

# --- 3. Create Application Files ---
echo "[+] Creating targeted_collector.py application file..."
cp /home/tdf/targeted_collector.py $PROJECT_DIR/targeted_collector.py

# --- 4. Create requirements.txt file ---
echo "[+] Creating requirements.txt file..."
cat << 'EOF' > $PROJECT_DIR/requirements.txt
requests
beautifulsoup4
EOF

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/targeted_collector_v5.service
[Unit]
Description=Targeted Ebook Collector Service v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 targeted_collector.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting Targeted Ebook Collector service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $BOOK_DEPOSIT_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start targeted_collector_v5
sudo systemctl enable targeted_collector_v5

echo "--- Targeted Ebook Collector Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status targeted_collector_v5"
echo "To watch the logs, run: tail -f /factory/logs/targeted_collector.log"
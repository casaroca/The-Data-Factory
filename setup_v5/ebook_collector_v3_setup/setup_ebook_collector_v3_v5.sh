#!/bin/bash
set -e

echo "--- Setting up Ebook Collector v3 v5 ---"

# --- 1. Stop and remove the old service to prevent conflicts ---
echo "[+] Stopping and removing old ebook_collector_v2 service..."
sudo systemctl stop ebook_collector_v2 || true
sudo systemctl disable ebook_collector_v2 || true
sudo rm -f /etc/systemd/system/ebook_collector_v2.service
sudo rm -rf /factory/workers/collectors/ebook_collector_v2
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/ebook_collector_v3_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/ebook_collector_v3.log"
DEPOSIT_DIR="/factory/library/book_deposit"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project directories..."
mkdir -p $PROJECT_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE

# --- 4. Create Application Files ---
echo "[+] Creating ebook_collector_v3.py application file..."
cp /home/tdf/ebook_collector_v3.py $PROJECT_DIR/ebook_collector_v3.py

# --- 5. Create requirements.txt file ---
echo "[+] Creating requirements.txt file..."
cat << 'EOF' > $PROJECT_DIR/requirements.txt
requests
beautifulsoup4
EOF

# --- 6. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
rm -rf $PROJECT_DIR/venv # Remove existing venv to ensure clean install
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install --upgrade pip
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt
$PROJECT_DIR/venv/bin/pip install certifi # Explicitly install certifi

# THE FIX: Set REQUESTS_CA_BUNDLE to the certifi bundle path
CERTIFI_BUNDLE=$($PROJECT_DIR/venv/bin/python -c "import certifi; print(certifi.where())")
sudo mkdir -p /etc/systemd/system/ebook_collector_v3_v5.service.d
sudo bash -c "echo 'Environment=REQUESTS_CA_BUNDLE=$CERTIFI_BUNDLE' >> /etc/systemd/system/ebook_collector_v3_v5.service.d/override.conf"

# --- 7. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/ebook_collector_v3_v5.service
[Unit]
Description=Ebook Collector Service v3 v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 ebook_collector_v3.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 8. Start the Service ---
echo "[+] Starting Ebook Collector v3 service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $DEPOSIT_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start ebook_collector_v3_v5
sudo systemctl enable ebook_collector_v3_v5

echo "--- Ebook Collector v3 Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status ebook_collector_v3_v5"
echo "To watch the logs, run: tail -f /factory/logs/ebook_collector_v3.log"

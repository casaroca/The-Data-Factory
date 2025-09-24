#!/bin/bash
set -e

echo "--- Setting up Data Packager (Corrected) v5 ---"

# --- 1. Define Paths ---
PROJECT_DIR="/factory/workers/processors/data_packager_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/data_packager.log"
FINAL_DATA_DIR="/factory/data/final"
OLD_PACKAGE_OUTPUT_DIR="/factory/data/final/packages"
PACKAGE_OUTPUT_DIR="/mnt/market_ready"
USER="tdf"

# --- 2. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $PACKAGE_OUTPUT_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE

# --- 3. Move existing packages ---
echo "[+] Moving existing packages to new location..."
if [ -d "$OLD_PACKAGE_OUTPUT_DIR" ]; then
    sudo mv $OLD_PACKAGE_OUTPUT_DIR/* $PACKAGE_OUTPUT_DIR/ || true
    sudo rm -rf $OLD_PACKAGE_OUTPUT_DIR
fi

# --- 4. Create Application Files ---
echo "[+] Creating data_packager.py application file..."
cp /home/tdf/data_packager.py $PROJECT_DIR/data_packager.py

cat << 'EOF' > $PROJECT_DIR/requirements.txt
# No external pip packages needed
EOF

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/data_packager_v5.service
[Unit]
Description=Data Packager Service v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 data_packager.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting Data Packager service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $PACKAGE_OUTPUT_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start data_packager_v5
sudo systemctl enable data_packager_v5

echo "--- Data Packager Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status data_packager_v5"
echo "To watch the logs, run: tail -f /factory/logs/data_packager.log"
#!/bin/bash
set -e

echo "--- Setting up Outlier Detector v1 ---"

# --- 1. Define Paths ---
PROJECT_DIR="/factory/workers/processors/outlier_detector_v1"
LOG_DIR="/factory/logs"
INBOX_DIR="/factory/data/processed" # Output of ethical_sorter
CLEAN_OUTPUT_DIR="/factory/data/processed_clean" # Input for data_processor
OUTLIER_DISCARD_DIR="/factory/data/discarded/semantic_outliers"
USER="tdf"

# --- 2. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $LOG_DIR
mkdir -p $INBOX_DIR
mkdir -p $CLEAN_OUTPUT_DIR
mkdir -p $OUTLIER_DISCARD_DIR

# --- 3. Move Application File ---
echo "[+] Moving outlier_detector_v1.py to project directory..."
mv /home/$USER/outlier_detector_v1.py $PROJECT_DIR/outlier_detector_v1.py

# --- 4. Create requirements.txt ---
cat << 'EOF' > $PROJECT_DIR/requirements.txt
scikit-learn
sentence-transformers
torch
EOF

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment (this may take a while)..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install --upgrade pip
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/outlier_detector_v1.service
[Unit]
Description=Semantic Outlier Detector Service v1
After=network-online.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 outlier_detector_v1.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Setting permissions and starting Outlier Detector service..."
sudo chown -R $USER:$USER $PROJECT_DIR $LOG_DIR $INBOX_DIR $CLEAN_OUTPUT_DIR $OUTLIER_DISCARD_DIR
sudo systemctl daemon-reload
sudo systemctl start outlier_detector_v1
sudo systemctl enable outlier_detector_v1

echo "--- Outlier Detector v1 Setup Complete ---"
echo "To check the status, run: sudo systemctl status outlier_detector_v1"
echo "To watch the logs, run: tail -f /factory/logs/outlier_detector_v1.log"

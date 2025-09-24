#!/bin/bash
set -e

echo "--- Setting up Media Processor v5 ---"

# --- 1. System Prerequisites ---
echo "[+] Installing prerequisites..."
sudo apt-get update
sudo apt-get install -y python3-pip python3-venv

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/processors/media_processor_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/media_processor.log"
INPUT_DIR="/factory/library/media_for_processing"
OUTPUT_DIR="/factory/data/raw/image_captions"
PROCESSED_DIR="/factory/library/processed_media"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $OUTPUT_DIR
mkdir -p $PROCESSED_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE

# --- 4. Create Application Files ---
echo "[+] Creating media_processor.py application file..."
cp /home/tdf/media_processor.py $PROJECT_DIR/media_processor.py

# --- 5. Create requirements.txt file ---
echo "[+] Creating requirements.txt file..."
cat << 'EOF' > $PROJECT_DIR/requirements.txt
Pillow
torch
transformers
EOF

# --- 6. Set Up Python Environment ---
echo "[+] Setting up Python environment (this will take a long time)..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install --upgrade pip
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 7. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/media_processor_v5.service
[Unit]
Description=Media Processor Service v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 media_processor.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 8. Start the Service ---
echo "[+] Starting Media Processor service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $INPUT_DIR
sudo chown -R $USER:$USER $OUTPUT_DIR
sudo chown -R $USER:$USER $PROCESSED_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start media_processor_v5
sudo systemctl enable media_processor_v5

echo "--- Media Processor Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status media_processor_v5"
echo "To watch the logs, run: tail -f /factory/logs/media_processor.log"

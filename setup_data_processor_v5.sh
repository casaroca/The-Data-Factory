#!/bin/bash
set -e

echo "--- Setting up Data Processor v5 ---"

# --- 1. Define Paths ---
PROJECT_DIR="/factory/workers/processors/data_processor_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/data_processor.log"
INBOX_DIR="/factory/data/processed_clean"
OUTPUT_PROMPTS_CSV_DIR="/factory/data/final/prompts/csv"
OUTPUT_PROMPTS_JSONL_DIR="/factory/data/final/prompts/jsonl"
OUTPUT_INSTRUCTIONS_CSV_DIR="/factory/data/final/instructions/csv"
OUTPUT_INSTRUCTIONS_JSONL_DIR="/factory/data/final/instructions/jsonl"
USER="tdf"

# --- 2. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $OUTPUT_PROMPTS_CSV_DIR
mkdir -p $OUTPUT_PROMPTS_JSONL_DIR
mkdir -p $OUTPUT_INSTRUCTIONS_CSV_DIR
mkdir -p $OUTPUT_INSTRUCTIONS_JSONL_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE

# --- 3. Create Application Files ---
echo "[+] Creating data_processor.py application file..."
cp /home/tdf/data_processor.py $PROJECT_DIR/data_processor.py

cat << 'EOF' > $PROJECT_DIR/requirements.txt
# No external pip packages needed
EOF

# --- 4. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 5. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/data_processor_v5.service
[Unit]
Description=Data Processor Service v5
After=network-online.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 data_processor.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 6. Start the Service ---
echo "[+] Starting Data Processor service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $INBOX_DIR
sudo chown -R $USER:$USER $OUTPUT_PROMPTS_CSV_DIR
sudo chown -R $USER:$USER $OUTPUT_PROMPTS_JSONL_DIR
sudo chown -R $USER:$USER $OUTPUT_INSTRUCTIONS_CSV_DIR
sudo chown -R $USER:$USER $OUTPUT_INSTRUCTIONS_JSONL_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start data_processor_v5
sudo systemctl enable data_processor_v5

echo "--- Data Processor Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status data_processor_v5"
echo "To watch the logs, run: tail -f /factory/logs/data_processor.log"

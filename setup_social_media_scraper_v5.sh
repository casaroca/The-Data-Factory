#!/bin/bash
set -e

echo "--- Setting up Social Media Scraper (Reddit) v5 ---"

# --- 1. System Prerequisites ---
echo "[+] Installing prerequisites (Chrome, Chromedriver, Python)..."
export NEEDRESTART_MODE=a
sudo apt-get update
# Removed chromium-browser, rely on google-chrome-stable and the separate chromedriver package
sudo apt-get install -y python3-pip python3-venv wget gnupg chromium-chromedriver

# Install Google Chrome (if not already present)
if ! command -v google-chrome &> /dev/null
then
    wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
    sudo sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list'
    sudo apt-get update
    sudo apt-get install -y google-chrome-stable
fi

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/social_media_scraper_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/social_media_scraper.log"
DUMP_DIR="/factory/data/raw/social_media_reddit"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project directories..."
mkdir -p $PROJECT_DIR
mkdir -p $DUMP_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE

# --- 4. Create Application Files ---
echo "[+] Creating application files..."
cp /home/tdf/social_media_scraper.py $PROJECT_DIR/social_media_scraper.py

# --- 5. Create requirements.txt file ---
echo "[+] Creating requirements.txt file..."
cat << 'EOF' > $PROJECT_DIR/requirements.txt
selenium
EOF

# --- 6. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 7. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/social_media_scraper_v5.service
[Unit]
Description=Social Media Scraper Service (Reddit) v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 social_media_scraper.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 8. Start the Service ---
echo "[+] Starting Social Media Scraper service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $DUMP_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start social_media_scraper_v5
sudo systemctl enable social_media_scraper_v5

echo "--- Social Media Scraper Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status social_media_scraper_v5"
echo "To watch the logs, run: tail -f /factory/logs/social_media_scraper.log"

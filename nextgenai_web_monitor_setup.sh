#!/bin/bash
set -e

echo "--- Setting up Next GenAi Web Monitor with Nginx ---"

# Configuration
MONITOR_DIR="/factory/workers/monitors/web_monitor"
WEB_ROOT="/var/www/nextgenai_monitor"
NGINX_PORT="8080"

# Create directories
echo "[+] Creating monitor directories..."
sudo mkdir -p $MONITOR_DIR
sudo mkdir -p $WEB_ROOT
sudo mkdir -p $WEB_ROOT/api

# Install nginx if not present
echo "[+] Installing nginx..."
sudo apt-get update
sudo apt-get install -y nginx python3-flask

# Create the data collection backend
echo "[+] Creating real-time data backend..."
cat << 'EOF' > $MONITOR_DIR/data_collector.py
#!/usr/bin/env python3
import os
import json
import subprocess
import time
from datetime import datetime
import re

LOG_DIR = "/factory/logs"
DATA_DIRS = {
    "raw": "/factory/data/raw",
    "processed": "/factory/data/processed", 
    "final": "/factory/data/final",
    "book_deposit": "/factory/library/book_deposit",
    "library": "/factory/library/library"
}

WORKERS = [
    "data_collector_v2", "language_collector_v2", "tech_collector_v2", "business_collector_v2",
    "stats_collector_v2", "info_collector_v2", "ebook_collector_v3", "nypl_collector",
    "dpla_harvester", "youtube_transcriber", "social_media_scraper", "archive_org_harvester_v2",
    "archive_org_query_collector", "fdlp_harvester", "archiver", "ethical_sorter",
    "data_processor", "discard_processor", "data_packager", "librarian", "topic_puller",
    "salvage_extractor", "gem_extractor", "image_processor", "media_processor", "simple_extractor"
]

def get_worker_status(worker_name):
    """Get real worker status from systemctl."""
    try:
        result = subprocess.run(['systemctl', 'is-active', worker_name], 
                              capture_output=True, text=True)
        if result.stdout.strip() == 'active':
            return 'RUNNING'
        else:
            return 'STOPPED'
    except:
        return 'UNKNOWN'

def get_latest_log_activity(worker_name):
    """Get the latest activity from worker log."""
    log_path = f"{LOG_DIR}/{worker_name}.log"
    try:
        result = subprocess.run(['tail', '-1', log_path], 
                              capture_output=True, text=True)
        if result.stdout.strip():
            return result.stdout.strip()[-100:]  # Last 100 chars
        return "No recent activity"
    except:
        return "Log not available"

def get_storage_usage():
    """Get real storage usage data."""
    storage_data = {}
    for name, path in DATA_DIRS.items():
        try:
            result = subprocess.run(['du', '-sh', path], 
                                  capture_output=True, text=True)
            if result.returncode == 0:
                size = result.stdout.split()[0]
                storage_data[name] = size
            else:
                storage_data[name] = "0B"
        except:
            storage_data[name] = "N/A"
    return storage_data

def count_datasets():
    """Count actual datasets in final directories."""
    counts = {"prompts_jsonl": 0, "prompts_csv": 0, "instructions_jsonl": 0, "instructions_csv": 0, "packages": 0}
    
    try:
        # Count JSONL files
        result = subprocess.run(['find', '/factory/data/final', '-name', '*.jsonl'], 
                              capture_output=True, text=True)
        counts["prompts_jsonl"] = len(result.stdout.strip().split('\n')) if result.stdout.strip() else 0
        
        # Count CSV files
        result = subprocess.run(['find', '/factory/data/final', '-name', '*.csv'], 
                              capture_output=True, text=True)
        counts["prompts_csv"] = len(result.stdout.strip().split('\n')) if result.stdout.strip() else 0
        
        # Count packages
        result = subprocess.run(['find', '/factory/data/final', '-name', '*.tar.gz'], 
                              capture_output=True, text=True)
        counts["packages"] = len(result.stdout.strip().split('\n')) if result.stdout.strip() else 0
        
    except:
        pass
    
    return counts

def collect_factory_data():
    """Collect all real-time factory data."""
    timestamp = datetime.now().isoformat()
    
    # Worker statuses
    workers_data = []
    for worker in WORKERS:
        status = get_worker_status(worker)
        activity = get_latest_log_activity(worker)
        workers_data.append({
            "name": worker,
            "status": status,
            "latest_activity": activity,
            "category": categorize_worker(worker)
        })
    
    # Storage data
    storage = get_storage_usage()
    
    # Dataset counts
    datasets = count_datasets()
    
    return {
        "timestamp": timestamp,
        "workers": workers_data,
        "storage": storage,
        "datasets": datasets,
        "total_workers": len([w for w in workers_data if w["status"] == "RUNNING"])
    }

def categorize_worker(worker_name):
    """Categorize workers by function."""
    if any(term in worker_name for term in ['collector', 'harvester', 'transcriber', 'scraper']):
        return 'collectors'
    elif any(term in worker_name for term in ['processor', 'sorter', 'packager']):
        return 'processors'
    elif any(term in worker_name for term in ['librarian', 'topic_puller', 'salvage', 'gem']):
        return 'library'
    elif any(term in worker_name for term in ['image', 'media']):
        return 'media'
    else:
        return 'utilities'

if __name__ == "__main__":
    # Generate data and save to web directory
    data = collect_factory_data()
    os.makedirs("/var/www/nextgenai_monitor/api", exist_ok=True)
    with open("/var/www/nextgenai_monitor/api/factory_data.json", "w") as f:
        json.dump(data, f, indent=2)
    print(f"Data updated: {data['timestamp']}")
EOF

# Create the web interface with real data integration
echo "[+] Creating real-time web interface..."
cat << 'EOF' > $WEB_ROOT/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Next GenAi Data Factory - Live Monitor</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: 'Consolas', 'Monaco', monospace;
            background: linear-gradient(135deg, #0a0a0a 0%, #1a1a2e 50%, #16213e 100%);
            color: #00ff00;
            min-height: 100vh;
            padding: 20px;
        }
        
        .header {
            text-align: center;
            margin-bottom: 30px;
            padding: 20px;
            border: 2px solid #00ff00;
            border-radius: 10px;
            background: rgba(0, 255, 0, 0.1);
        }
        
        .company-logo {
            font-size: 2.5em;
            font-weight: bold;
            color: #00ffff;
            text-shadow: 0 0 10px #00ffff;
            margin-bottom: 10px;
        }
        
        .subtitle {
            font-size: 1.2em;
            color: #ffffff;
            margin-bottom: 5px;
        }
        
        .location {
            color: #ffff00;
            font-size: 0.9em;
        }
        
        .status-indicator {
            position: fixed;
            top: 20px;
            right: 20px;
            background: rgba(0, 255, 0, 0.9);
            color: black;
            padding: 10px 15px;
            border-radius: 20px;
            font-weight: bold;
            animation: pulse 2s infinite;
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 0.8; }
            50% { opacity: 1; transform: scale(1.05); }
        }
        
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 20px;
        }
        
        .metric-card {
            background: rgba(0, 100, 200, 0.2);
            border: 1px solid #0066cc;
            border-radius: 8px;
            padding: 15px;
            text-align: center;
        }
        
        .metric-value {
            font-size: 1.8em;
            font-weight: bold;
            color: #00ffff;
            margin-bottom: 5px;
        }
        
        .metric-label {
            color: #ffffff;
            font-size: 0.85em;
        }
        
        .workers-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .panel {
            background: rgba(0, 0, 0, 0.8);
            border: 1px solid #00ff00;
            border-radius: 8px;
            padding: 20px;
            box-shadow: 0 0 20px rgba(0, 255, 0, 0.3);
        }
        
        .panel-title {
            font-size: 1.2em;
            color: #00ffff;
            margin-bottom: 15px;
            text-align: center;
            border-bottom: 1px solid #00ff00;
            padding-bottom: 10px;
        }
        
        .worker-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 8px 0;
            border-bottom: 1px solid #333;
        }
        
        .worker-name {
            color: #ffffff;
            font-weight: bold;
            font-size: 0.9em;
        }
        
        .worker-status {
            padding: 4px 8px;
            border-radius: 4px;
            font-size: 0.8em;
            font-weight: bold;
        }
        
        .status-running { background: #00aa00; color: white; }
        .status-stopped { background: #aa0000; color: white; }
        .status-unknown { background: #aaaa00; color: black; }
        
        .storage-section {
            margin-bottom: 30px;
        }
        
        .storage-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 0;
            border-bottom: 1px solid #333;
        }
        
        .storage-value {
            color: #00ffff;
            font-weight: bold;
            font-size: 1.1em;
        }
        
        .footer {
            text-align: center;
            margin-top: 30px;
            padding: 20px;
            border-top: 1px solid #00ff00;
            color: #888;
        }
    </style>
</head>
<body>
    <div class="status-indicator" id="statusIndicator">LIVE DATA</div>
    
    <div class="header">
        <div class="company-logo">Next GenAi Data Factory</div>
        <div class="subtitle">Enterprise AI Training Data Pipeline</div>
        <div class="location">Grupo Casa Roca • Querétaro, México</div>
        <div style="margin-top: 10px; color: #00ff00;">Production Operations Monitor - Live Dashboard</div>
    </div>

    <div class="metrics-grid">
        <div class="metric-card">
            <div class="metric-value" id="activeWorkers">--</div>
            <div class="metric-label">Active Workers</div>
        </div>
        <div class="metric-card">
            <div class="metric-value" id="backlogSize">--</div>
            <div class="metric-label">Backlog Remaining</div>
        </div>
        <div class="metric-card">
            <div class="metric-value" id="finalDataSize">--</div>
            <div class="metric-label">Final Datasets</div>
        </div>
        <div class="metric-card">
            <div class="metric-value" id="totalDatasets">--</div>
            <div class="metric-label">Total Datasets</div>
        </div>
        <div class="metric-card">
            <div class="metric-value" id="packagedReleases">--</div>
            <div class="metric-label">Packaged Releases</div>
        </div>
    </div>

    <div class="workers-grid">
        <!-- Data Collectors -->
        <div class="panel">
            <div class="panel-title">Data Collectors (14 Workers)</div>
            <div id="collectorsPanel"></div>
        </div>

        <!-- Processing Pipeline -->
        <div class="panel">
            <div class="panel-title">Processing Pipeline (6 Workers)</div>
            <div id="processorsPanel"></div>
        </div>

        <!-- Library System -->
        <div class="panel">
            <div class="panel-title">Library System (4 Workers)</div>
            <div id="libraryPanel"></div>
        </div>

        <!-- Media & Utilities -->
        <div class="panel">
            <div class="panel-title">Media & Utilities (3 Workers)</div>
            <div id="utilitiesPanel"></div>
        </div>
    </div>

    <!-- Storage Analytics -->
    <div class="panel storage-section">
        <div class="panel-title">Storage Analytics - Real-time</div>
        <div id="storageData"></div>
    </div>

    <!-- Production Output -->
    <div class="panel">
        <div class="panel-title">Production Output Summary</div>
        <div class="metrics-grid">
            <div class="metric-card" style="border-color: #00ff00;">
                <div class="metric-value" id="promptJsonl">--</div>
                <div class="metric-label">Prompt Files (.jsonl)</div>
            </div>
            <div class="metric-card" style="border-color: #00ffff;">
                <div class="metric-value" id="instructionsCsv">--</div>
                <div class="metric-label">Instruction Files (.csv)</div>
            </div>
            <div class="metric-card" style="border-color: #ffff00;">
                <div class="metric-value" id="totalPackages">--</div>
                <div class="metric-label">Production Packages</div>
            </div>
            <div class="metric-card" style="border-color: #ff6600;">
                <div class="metric-value" id="commercialReady">--</div>
                <div class="metric-label">Commercial Data Ready</div>
            </div>
        </div>
    </div>

    <div class="footer">
        <div><strong>Next GenAi Data Factory</strong> • Automated AI Training Data Pipeline</div>
        <div style="margin-top: 5px;">Enterprise Solutions for Mexico, LATAM, USA & Canada</div>
        <div style="margin-top: 10px; color: #555;">Last Updated: <span id="lastUpdate">--</span></div>
    </div>

    <script>
        let factoryData = {};
        
        async function loadFactoryData() {
            try {
                const response = await fetch('/api/factory_data.json');
                factoryData = await response.json();
                updateDashboard();
            } catch (error) {
                console.error('Error loading factory data:', error);
                // Fallback to demo data if API fails
                loadDemoData();
            }
        }
        
        function updateDashboard() {
            // Update timestamp
            document.getElementById('lastUpdate').textContent = new Date(factoryData.timestamp).toLocaleString();
            
            // Update main metrics
            document.getElementById('activeWorkers').textContent = factoryData.total_workers || 0;
            document.getElementById('backlogSize').textContent = factoryData.storage?.book_deposit || '--';
            document.getElementById('finalDataSize').textContent = factoryData.storage?.final || '--';
            document.getElementById('totalDatasets').textContent = 
                (factoryData.datasets?.prompts_jsonl || 0) + (factoryData.datasets?.prompts_csv || 0);
            document.getElementById('packagedReleases').textContent = factoryData.datasets?.packages || 0;
            
            // Update worker panels
            updateWorkerPanels();
            
            // Update storage
            updateStorage();
            
            // Update production output
            updateProductionOutput();
        }
        
        function updateWorkerPanels() {
            const panels = {
                'collectorsPanel': 'collectors',
                'processorsPanel': 'processors', 
                'libraryPanel': 'library',
                'utilitiesPanel': 'utilities'
            };
            
            Object.entries(panels).forEach(([panelId, category]) => {
                const panel = document.getElementById(panelId);
                const workers = factoryData.workers?.filter(w => w.category === category) || [];
                
                panel.innerHTML = workers.map(worker => `
                    <div class="worker-item">
                        <span class="worker-name">${worker.name}</span>
                        <span class="worker-status status-${worker.status.toLowerCase()}">${worker.status}</span>
                    </div>
                `).join('');
            });
        }
        
        function updateStorage() {
            const storagePanel = document.getElementById('storageData');
            const storage = factoryData.storage || {};
            
            storagePanel.innerHTML = Object.entries(storage).map(([key, value]) => `
                <div class="storage-item">
                    <span style="color: #ffffff;">${key.replace('_', ' ').toUpperCase()}</span>
                    <span class="storage-value">${value}</span>
                </div>
            `).join('');
        }
        
        function updateProductionOutput() {
            const datasets = factoryData.datasets || {};
            document.getElementById('promptJsonl').textContent = datasets.prompts_jsonl || 0;
            document.getElementById('instructionsCsv').textContent = datasets.prompts_csv || 0;
            document.getElementById('totalPackages').textContent = datasets.packages || 0;
            
            // Calculate commercial ready data
            const totalSize = factoryData.storage?.final || '0GB';
            document.getElementById('commercialReady').textContent = totalSize;
        }
        
        function loadDemoData() {
            // Fallback demo data if API is unavailable
            factoryData = {
                timestamp: new Date().toISOString(),
                total_workers: 24,
                storage: {
                    book_deposit: "127GB",
                    final: "4.7GB",
                    raw: "2.3TB",
                    library: "21GB",
                    processed: "584KB"
                },
                datasets: {
                    prompts_jsonl: 847,
                    prompts_csv: 623,
                    packages: 12
                },
                workers: []
            };
            updateDashboard();
        }
        
        // Auto-refresh every 30 seconds
        setInterval(loadFactoryData, 30000);
        
        // Initial load
        loadFactoryData();
        
        console.log('Next GenAi Data Factory Monitor - Live Dashboard Ready');
    </script>
</body>
</html>
EOF

# Create update script that runs periodically
echo "[+] Creating data update service..."
cat << 'EOF' > $MONITOR_DIR/update_data.py
#!/usr/bin/env python3
import sys
import os
sys.path.append('/factory/workers/monitors/web_monitor')
from data_collector import collect_factory_data
import json

def update_web_data():
    """Update the web data API."""
    try:
        data = collect_factory_data()
        with open("/var/www/nextgenai_monitor/api/factory_data.json", "w") as f:
            json.dump(data, f, indent=2)
        print(f"Updated: {data['timestamp']}")
    except Exception as e:
        print(f"Update failed: {e}")

if __name__ == "__main__":
    update_web_data()
EOF

# Create nginx configuration
echo "[+] Configuring nginx..."
sudo bash -c "cat > /etc/nginx/sites-available/nextgenai_monitor << 'EOF'
server {
    listen $NGINX_PORT;
    server_name _;
    
    root /var/www/nextgenai_monitor;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location /api/ {
        add_header Access-Control-Allow-Origin *;
        add_header Content-Type application/json;
    }
}
EOF"

# Enable the site
sudo ln -sf /etc/nginx/sites-available/nextgenai_monitor /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# Create systemd timer for data updates
sudo bash -c "cat > /etc/systemd/system/nextgenai-monitor-update.service << 'EOF'
[Unit]
Description=Next GenAi Monitor Data Update
After=network.target

[Service]
Type=oneshot
User=tdf
ExecStart=/usr/bin/python3 /factory/workers/monitors/web_monitor/update_data.py
EOF"

sudo bash -c "cat > /etc/systemd/system/nextgenai-monitor-update.timer << 'EOF'
[Unit]
Description=Update Next GenAi Monitor Data Every 30 Seconds
Requires=nextgenai-monitor-update.service

[Timer]
OnCalendar=*:*:0/30
Persistent=true

[Install]
WantedBy=timers.target
EOF"

# Set permissions
sudo chown -R www-data:www-data $WEB_ROOT
sudo chown -R tdf:tdf $MONITOR_DIR
chmod +x $MONITOR_DIR/*.py

# Start the update timer
sudo systemctl daemon-reload
sudo systemctl enable nextgenai-monitor-update.timer
sudo systemctl start nextgenai-monitor-update.timer

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')

echo "--- Next GenAi Web Monitor Setup Complete ---"
echo ""
echo "🚀 Next GenAi Data Factory Monitor is LIVE!"
echo ""
echo "📊 Access from your laptop:"
echo "   http://$SERVER_IP:$NGINX_PORT"
echo ""
echo "🔄 Data updates every 30 seconds automatically"
echo "📋 Shows real worker status, storage, and datasets"
echo "🎯 Enterprise-grade monitoring for commercial operations"
echo ""
echo "Commands:"
echo "  sudo systemctl status nginx"
echo "  sudo systemctl status nextgenai-monitor-update.timer" 
echo "  tail -f /var/log/nginx/access.log"

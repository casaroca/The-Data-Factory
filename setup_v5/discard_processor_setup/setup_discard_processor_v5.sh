#!/bin/bash
set -e

echo "--- Setting up Discard Processor v5 ---"

# --- 1. Define Paths ---
PROJECT_DIR="/factory/workers/processors/discard_processor_v5"
LOG_DIR="/factory/logs"
INBOX_DIR="/factory/data/discarded/unsafe_content"
OUTPUT_DIR="/factory/data/final/vocabulary_datasets"
USER="tdf"

# --- 2. Create Directories ---
echo "[+] Creating project and data directories..."
rm -rf $PROJECT_DIR # Ensure clean project directory
mkdir -p $PROJECT_DIR
mkdir -p $OUTPUT_DIR

# --- FIX: Set ownership immediately after creating directories ---
sudo chown -R $USER:$USER $PROJECT_DIR $OUTPUT_DIR

# --- 3. Create Application Files ---
echo "[+] Creating discard_processor.py application file..."
cat << 'EOF' > $PROJECT_DIR/discard_processor.py
import os
import time
import logging
import re
import json
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import random # Added for random.sample

# --- Configuration ---
LOG_DIR = "/factory/logs"
INBOX_DIR = "/factory/data/discarded/unsafe_content"
OUTPUT_DIR = "/factory/data/final/vocabulary_datasets"
MAX_WORKERS = 4
BATCH_SIZE = 100
MIN_WORD_LENGTH = 4
MIN_WORD_COUNT = 3

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'discard_processor.log'), level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

# --- Stop Words (a small, common list) ---
STOP_WORDS = set([
    'the', 'a', 'an', 'in', 'is', 'it', 'and', 'of', 'for', 'to', 'was', 'were', 'on', 'with',
    'as', 'by', 'that', 'this', 'i', 'you', 'he', 'she', 'we', 'they', 'are', 'not', 'have',
    'from', 'or', 'at', 'but', 'if', 'be', 'my', 'your', 'his', 'her', 'our', 'their'
])

def extract_vocabulary(text_content):
    """Extracts a list of the most common, meaningful words from a text."""
    try:
        # Find all words, convert to lowercase
        words = re.findall(r'\b[a-z]{3,}\b', text_content.lower())
        
        # Filter out stop words and short words
        meaningful_words = [word for word in words if word not in STOP_WORDS and len(word) >= MIN_WORD_LENGTH]
        
        if not meaningful_words:
            return []
        
        # Count the frequency of each word
        word_counts = Counter(meaningful_words)
        
        # Return the most common words that appear at least a few times
        return [word for word, count in word_counts.most_common(20) if count >= MIN_WORD_COUNT]
    except Exception as e:
        logging.error(f"Failed to extract vocabulary: {e}")
        return []

def generate_vocab_prompts(vocabulary):
    """Generates a list of instruction prompts from a vocabulary list."""
    prompts = []
    if not vocabulary:
        return prompts

    for word in vocabulary:
        # Generate a few different types of prompts for variety
        prompts.append({"instruction": f"Define the word: '{word}'", "input": "", "output": ""})
        prompts.append({"instruction": f"Use the word '{word}' in a sentence.", "input": "", "output": ""})

    if len(vocabulary) > 3:
        sample = random.sample(vocabulary, 3)
        prompts.append({
            "instruction": f"Explain the relationship between the following words: {sample[0]}, {sample[1]}, and {sample[2]}.",
            "input": "", "output": ""
        })
        
    return prompts

def process_file(filepath):
    """Full processing pipeline for a single discarded file."""
    filename = os.path.basename(filepath)
    try:
        logging.info(f"Processing discarded file: {filename}")
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()

        vocabulary = extract_vocabulary(content)
        
        if vocabulary:
            prompts = generate_vocab_prompts(vocabulary)
            if prompts:
                # Save prompts to a new .jsonl file
                output_filename = f"vocab_{os.path.splitext(filename)[0]}.jsonl"
                output_path = os.path.join(OUTPUT_DIR, output_filename)
                
                with open(output_path, 'w', encoding='utf-8') as f:
                    for prompt in prompts:
                        f.write(json.dumps(prompt) + '\n')
                logging.info(f"Successfully generated {len(prompts)} prompts to {output_path}")
        else:
            logging.warning(f"No usable vocabulary found in {filename}. Deleting.")

        # Delete the original discarded file after processing is complete
        os.remove(filepath)

    except Exception as e:
        logging.error(f"Failed to process {filename}: {e}")
        try:
            # On failure, still delete the file to prevent loops
            os.remove(filepath)
        except OSError:
            pass

def main():
    while True:
        logging.info("Discard Processor is checking for files...")
        all_files = [os.path.join(dp, f) for dp,_,fns in os.walk(INBOX_DIR) for f in fns]
        
        if all_files:
            batch_to_process = all_files[:BATCH_SIZE]
            logging.info(f"Found {len(all_files)} discarded files. Processing a batch of {len(batch_to_process)}.")
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                executor.map(process_file, batch_to_process)
            logging.info("Batch finished. Immediately checking for more...")
        else:
            logging.info("No discarded files found. Waiting...")
            time.sleep(30)

if __name__ == "__main__":
    main()
EOF

cat << 'EOF' > $PROJECT_DIR/requirements.txt
# No external pip packages needed
EOF

# --- 4. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 5. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/discard_processor_v5.service
[Unit]
Description=Discard Processor Service v5
After=network-online.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 discard_processor.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 6. Start the Service ---
echo "[+] Starting Discard Processor service..."
sudo chown -R $USER:$USER $LOG_DIR # Ensure log directory is owned by user
sudo systemctl daemon-reload
sudo systemctl start discard_processor_v5
sudo systemctl enable discard_processor_v5

echo "--- Discard Processor Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status discard_processor_v5"
echo "To watch the logs, run: tail -f /factory/logs/discard_processor.log"

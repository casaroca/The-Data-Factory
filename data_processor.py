import os
import time
import logging
import re
import json
import csv
from concurrent.futures import ThreadPoolExecutor

# --- Configuration ---
LOG_DIR = "/factory/logs"
INBOX_DIR = "/factory/data/processed_clean"
OUTPUT_PROMPTS_CSV_DIR = "/factory/data/final/prompts/csv"
OUTPUT_PROMPTS_JSONL_DIR = "/factory/data/final/prompts/jsonl"
OUTPUT_INSTRUCTIONS_CSV_DIR = "/factory/data/final/instructions/csv"
OUTPUT_INSTRUCTIONS_JSONL_DIR = "/factory/data/final/instructions/jsonl"
MAX_WORKERS = 10
BATCH_SIZE = 200

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'data_processor.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def generate_instruction(text, category):
    """Intelligently generates an instruction prompt from a text chunk."""
    # Rule 1: Look for explicit questions
    qa_match = re.search(r'^(.*?\?)\s*\n(.*?)$', text, re.DOTALL | re.MULTILINE)
    if qa_match:
        return {"instruction": qa_match.group(1).strip(), "input": "", "output": qa_match.group(2).strip()}

    # Rule 2: Look for list-like structures
    if re.search(r'(\n\s*(\*|\-|\d+\.)\s*){3,}', text): # Finds 3 or more list items
        first_line = text.split('\n')[0]
        return {"instruction": f"Generate a list based on the following topic: {first_line}", "input": text, "output": ""}

    # Rule 3: Default summarization prompt
    return {"instruction": "Summarize the following text.", "input": text, "output": ""}

def process_file(filepath):
    """Full processing pipeline for a single sorted file."""
    filename = os.path.basename(filepath)
    category = os.path.basename(os.path.dirname(filepath))
    try:
        logging.info(f"Processing file: {filename} from category: {category}")
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()

        if not content.strip() or len(content) < 100:
            logging.warning(f"File {filename} is empty or too short. Deleting.")
            os.remove(filepath)
            return

        # --- 1. Create and Save the "Prompt" Dataset ---
        prompt_data = {"text": content}
        
        # Save to JSONL
        prompt_jsonl_dir = os.path.join(OUTPUT_PROMPTS_JSONL_DIR, category)
        os.makedirs(prompt_jsonl_dir, exist_ok=True)
        prompt_jsonl_path = os.path.join(prompt_jsonl_dir, f"{category}_prompts.jsonl")
        with open(prompt_jsonl_path, 'a', encoding='utf-8') as f:
            f.write(json.dumps(prompt_data) + '\n')

        # Save to CSV
        prompt_csv_dir = os.path.join(OUTPUT_PROMPTS_CSV_DIR, category)
        os.makedirs(prompt_csv_dir, exist_ok=True)
        prompt_csv_path = os.path.join(prompt_csv_dir, f"{category}_prompts.csv")
        write_header_prompt = not os.path.exists(prompt_csv_path)
        with open(prompt_csv_path, 'a', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=prompt_data.keys())
            if write_header_prompt: writer.writeheader()
            writer.writerow(prompt_data)

        # --- 2. Create and Save the "Instruction" Dataset ---
        instruction_data = generate_instruction(content, category)
        
        # Save to JSONL
        instr_jsonl_dir = os.path.join(OUTPUT_INSTRUCTIONS_JSONL_DIR, category)
        os.makedirs(instr_jsonl_dir, exist_ok=True)
        instr_jsonl_path = os.path.join(instr_jsonl_dir, f"{category}_instructions.jsonl")
        with open(instr_jsonl_path, 'a', encoding='utf-8') as f:
            f.write(json.dumps(instruction_data) + '\n')
            
        # Save to CSV
        instr_csv_dir = os.path.join(OUTPUT_INSTRUCTIONS_CSV_DIR, category)
        os.makedirs(instr_csv_dir, exist_ok=True)
        instr_csv_path = os.path.join(instr_csv_dir, f"{category}_instructions.csv")
        write_header_instr = not os.path.exists(instr_csv_path)
        with open(instr_csv_path, 'a', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=instruction_data.keys())
            if write_header_instr: writer.writeheader()
            writer.writerow(instruction_data)

        logging.info(f"Successfully created prompt and instruction for {filename}")
        os.remove(filepath)

    except Exception as e:
        logging.error(f"Failed to process file {filename}: {e}")
        try:
            os.remove(filepath) # Delete failed file to prevent loops
        except OSError:
            pass

def main():
    while True:
        logging.info("Data Processor is checking for sorted files...")
        all_files = [os.path.join(dp, f) for dp,_,fns in os.walk(INBOX_DIR) for f in fns]
        
        if all_files:
            batch_to_process = all_files[:BATCH_SIZE]
            logging.info(f"Found {len(all_files)} sorted files. Processing a batch of {len(batch_to_process)}.")
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                executor.map(process_file, batch_to_process)
            logging.info("Batch finished. Immediately checking for more...")
        else:
            logging.info("No new sorted files found. Waiting...")
            time.sleep(20)

if __name__ == "__main__":
    main()

import os
import time
import logging
import subprocess
import shutil
import sqlite3
import zipfile
from PIL import Image
import torch
from transformers import BlipProcessor, BlipForConditionalGeneration
from concurrent.futures import ThreadPoolExecutor
import json

# --- Configuration ---
LOG_DIR = "/factory/logs"
DB_PATH = "/factory/db/image_processing_log.db"
OUTPUT_DIR = "/factory/data/final/image_datasets"
SCAN_DIRECTORIES = ["/factory/data", "/factory/library"]
IMAGE_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.gif', '.webp']
DOC_EXTENSIONS = ['.pdf', '.epub']
MAX_WORKERS = 4 # Image processing is resource-intensive

# --- Setup Logging ---
logging.basicConfig(filename=os.path.join(LOG_DIR, 'image_processor.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger("transformers").setLevel(logging.ERROR)
logging.getLogger('').addHandler(logging.StreamHandler())

# --- Load AI Model ---
MODEL = None
PROCESSOR = None
try:
    logging.info("Loading Image-to-Text model (Salesforce/blip-image-captioning-large)...")
    DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
    PROCESSOR = BlipProcessor.from_pretrained("Salesforce/blip-image-captioning-large")
    MODEL = BlipForConditionalGeneration.from_pretrained("Salesforce/blip-image-captioning-large").to(DEVICE)
    logging.info(f"Model loaded successfully onto {DEVICE}.")
except Exception as e:
    logging.error(f"Could not load AI model: {e}")

def init_database():
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute('CREATE TABLE IF NOT EXISTS processed_files (filepath TEXT PRIMARY KEY, processed_date TEXT)')
        conn.commit()

def is_file_processed(filepath):
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("SELECT 1 FROM processed_files WHERE filepath=?", (filepath,))
        return c.fetchone() is not None

def mark_file_as_processed(filepath):
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("INSERT OR IGNORE INTO processed_files VALUES (?, ?)", (filepath, time.strftime('%Y-%m-%d %H:%M:%S')))
        conn.commit()

def generate_caption(image_path):
    """Generates a caption for a single image."""
    if not MODEL or not PROCESSOR: return None
    try:
        raw_image = Image.open(image_path).convert('RGB')
        inputs = PROCESSOR(raw_image, return_tensors="pt").to(DEVICE)
        out = MODEL.generate(**inputs, max_new_tokens=50)
        return PROCESSOR.decode(out[0], skip_special_tokens=True)
    except Exception as e:
        logging.error(f"Failed to generate caption for {image_path}: {e}")
        return None

def save_dataset_entry(image_path, caption):
    """Saves a single image-caption pair to the final dataset."""
    entry = {"image_path": image_path, "caption": caption}
    output_path = os.path.join(OUTPUT_DIR, "master_image_captions.jsonl")
    with open(output_path, 'a', encoding='utf-8') as f:
        f.write(json.dumps(entry, ensure_ascii=False) + '\n')
    logging.info(f"Saved caption for {os.path.basename(image_path)}")

def process_image_file(image_path):
    """Processes a single standalone image file."""
    if is_file_processed(image_path): return
    logging.info(f"Processing image: {image_path}")
    caption = generate_caption(image_path)
    if caption:
        save_dataset_entry(image_path, caption)
    mark_file_as_processed(image_path)

def extract_and_process_from_pdf(pdf_path):
    """Extracts all images from a PDF and processes them."""
    if is_file_processed(pdf_path): return
    logging.info(f"Extracting images from PDF: {pdf_path}")
    temp_dir = f"/tmp/pdf_{os.path.basename(pdf_path)}"
    os.makedirs(temp_dir, exist_ok=True)
    try:
        # Use -png flag to force conversion of all image types to PNG
        subprocess.run(['pdfimages', '-png', pdf_path, os.path.join(temp_dir, 'img')], check=True, capture_output=True)
        extracted_images = [os.path.join(temp_dir, f) for f in os.listdir(temp_dir)]
        logging.info(f"Extracted {len(extracted_images)} images. Processing...")
        for img_path in extracted_images:
            process_image_file(img_path)
    except Exception as e:
        logging.error(f"Failed to extract from PDF {pdf_path}: {e}")
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
    mark_file_as_processed(pdf_path)

def extract_and_process_from_epub(epub_path):
    """Extracts all images from an EPUB and processes them."""
    if is_file_processed(epub_path): return
    logging.info(f"Extracting images from EPUB: {epub_path}")
    temp_dir = f"/tmp/epub_{os.path.basename(epub_path)}"
    try:
        with zipfile.ZipFile(epub_path, 'r') as zip_ref:
            for member in zip_ref.namelist():
                if any(member.lower().endswith(ext) for ext in IMAGE_EXTENSIONS):
                    zip_ref.extract(member, temp_dir)
        
        extracted_images = [os.path.join(dp, f) for dp,_,fns in os.walk(temp_dir) for f in fns]
        logging.info(f"Extracted {len(extracted_images)} images. Processing...")
        for img_path in extracted_images:
            process_image_file(img_path)
    except Exception as e:
        logging.error(f"Failed to extract from EPUB {epub_path}: {e}")
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
    mark_file_as_processed(epub_path)

def main():
    if not MODEL or not PROCESSOR:
        logging.critical("AI Model could not be loaded. Halting Image Processor.")
        return

    init_database()
    while True:
        logging.info("--- Starting new Image Processor cycle ---")
        all_files = []
        for directory in SCAN_DIRECTORIES:
            for dirpath, _, filenames in os.walk(directory):
                for filename in filenames:
                    all_files.append(os.path.join(dirpath, filename))
        
        image_files = [f for f in all_files if any(f.lower().endswith(ext) for ext in IMAGE_EXTENSIONS)]
        doc_files = [f for f in all_files if any(f.lower().endswith(ext) for ext in DOC_EXTENSIONS)]

        unprocessed_images = [f for f in image_files if not is_file_processed(f)][:100]
        unprocessed_docs = [f for f in doc_files if not is_file_processed(f)][:50]

        logging.info(f"Found {len(unprocessed_images)} new images and {len(unprocessed_docs)} new documents to scan.")

        if unprocessed_images or unprocessed_docs:
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                executor.map(process_image_file, unprocessed_images)
                executor.map(extract_and_process_from_pdf, [f for f in unprocessed_docs if f.lower().endswith('.pdf')])
                executor.map(extract_and_process_from_epub, [f for f in unprocessed_docs if f.lower().endswith('.epub')])
        
        logging.info("--- Image Processor cycle finished. Waiting 5 minutes... ---")
        time.sleep(5 * 60)

if __name__ == "__main__":
    main()

import os
import time
import logging
from PIL import Image
import torch
from transformers import BlipProcessor, BlipForConditionalGeneration
import shutil

# --- Configuration ---
LOG_DIR = "/factory/logs"
INPUT_DIR = "/factory/library/media_for_processing"
OUTPUT_DIR = "/factory/data/raw/image_captions"
PROCESSED_DIR = "/factory/library/processed_media"
REST_PERIOD_SECONDS = 60 # 1 minute

# --- Setup Logging ---
logging.basicConfig(filename=os.path.join(LOG_DIR, 'media_processor.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

# --- Load AI Model ---
try:
    logging.info("Loading Image-to-Text model (Salesforce/blip-image-captioning-large)...")
    DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
    PROCESSOR = BlipProcessor.from_pretrained("Salesforce/blip-image-captioning-large")
    MODEL = BlipForConditionalGeneration.from_pretrained("Salesforce/blip-image-captioning-large").to(DEVICE)
    logging.info(f"Model loaded successfully onto {DEVICE}.")
except Exception as e:
    logging.error(f"Could not load model: {e}")
    MODEL = None
    PROCESSOR = None

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

def process_image_file(filepath):
    """Generates a caption, saves it, and moves the processed image."""
    try:
        logging.info(f"Processing image: {os.path.basename(filepath)}")
        caption = generate_caption(filepath)
        
        if caption:
            # Save the caption to a text file
            output_filename = os.path.splitext(os.path.basename(filepath))[0] + ".txt"
            output_path = os.path.join(OUTPUT_DIR, output_filename)
            with open(output_path, 'w', encoding='utf-8') as f:
                f.write(caption)
            logging.info(f"Saved caption to {output_path}")
            
            # Move the processed image to the processed directory
            shutil.move(filepath, os.path.join(PROCESSED_DIR, os.path.basename(filepath)))
        else:
            # If captioning fails, move to a failed directory to avoid reprocessing
            failed_dir = os.path.join(PROCESSED_DIR, "failed")
            os.makedirs(failed_dir, exist_ok=True)
            shutil.move(filepath, os.path.join(failed_dir, os.path.basename(filepath)))

    except Exception as e:
        logging.error(f"A critical error occurred processing {os.path.basename(filepath)}: {e}", exc_info=True)


def main():
    if not MODEL or not PROCESSOR:
        logging.critical("AI model failed to load. Halting media_processor.")
        return

    while True:
        logging.info("--- Starting new Media Processor cycle ---")
        
        image_files = [os.path.join(INPUT_DIR, f) for f in os.listdir(INPUT_DIR) if f.lower().endswith(('.png', '.jpg', '.jpeg', '.webp'))]
        
        if image_files:
            logging.info(f"Found {len(image_files)} images to process.")
            # Process one by one to manage memory
            for image_file in image_files:
                process_image_file(image_file)
        else:
            logging.info("No new media files found. Waiting...")
        
        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()

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
MAX_WORKERS = 8
BATCH_SIZE = 200
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
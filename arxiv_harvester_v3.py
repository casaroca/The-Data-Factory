import os
import time
import logging
import arxiv
import random
from concurrent.futures import ThreadPoolExecutor
import tarfile
import tempfile
import shutil
import PyPDF2

# --- Configuration ---
LOG_DIR = "/factory/logs"
RAW_DUMP_DIR = "/factory/data/raw/arxiv_papers"
MAX_WORKERS = 5 # Increased worker count
REST_PERIOD_SECONDS = 15 # 1 minute rest period

# High-value queries from your list
SEARCH_QUERIES = [
    "philosophy", "logic AND reasoning", "critical thinking", "epistemology", "metaphysics",
    "ethics", "history of science", "linguistics", "sociology", "anthropology",
    "political science", "economics", "psychology", "education theory", "international relations",
    "physics", "chemistry", "biology", "astronomy", "mathematics",
    "computer science", "artificial intelligence", "machine learning", "data structures",
    "electronics", "information theory", "pathology", "pharmacology", "epidemiology",
    "public health", "nutrition science", "art history", "music theory", "architecture history",
    "design principles", "aesthetics philosophy", "cultural studies", "mathematical logic",
    "problem solving techniques"
]

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'arxiv_harvester_v3.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def process_paper(paper):
    """Downloads the source of a paper, extracts text, and saves it."""
    temp_dir = None
    try:
        logging.info(f"Processing paper: {paper.title}")
        
        # Create a unique filename
        sanitized_title = "".join([c for c in paper.title if c.isalnum() or c in (' ', '-')]).rstrip()
        output_filename = f"arxiv_{sanitized_title}.txt"
        output_path = os.path.join(RAW_DUMP_DIR, output_filename)
        full_text = ""
        
        try:
            # Create a temporary directory for this paper
            temp_dir = tempfile.mkdtemp()
            
            # Download the source to the temporary directory
            downloaded_path = paper.download_source(dirpath=temp_dir)
            
            # Try to open as tar.gz first
            try:
                with tarfile.open(downloaded_path, mode="r:gz") as tar:
                    for member in tar.getmembers():
                        if member.isfile() and member.name.endswith('.tex'):
                            extracted_file = tar.extractfile(member)
                            if extracted_file:
                                full_text += extracted_file.read().decode('utf-8', errors='ignore') + "\n\n"
            except (tarfile.ReadError, OSError, IOError):
                # If it's not a tar.gz, try reading as plain text
                try:
                    with open(downloaded_path, 'r', encoding='utf-8', errors='ignore') as f:
                        content = f.read()
                        if content.strip():
                            full_text = content
                except Exception:
                    pass # Continue to save metadata even if text extraction fails

            # If no text from source, try to download and extract from PDF
            if not full_text.strip():
                try:
                    pdf_path = paper.download_pdf(dirpath=temp_dir)
                    with open(pdf_path, 'rb') as f:
                        pdf_reader = PyPDF2.PdfReader(f)
                        for page in pdf_reader.pages:
                            full_text += page.extract_text()
                except Exception as pdf_error:
                    logging.warning(f"Could not extract text from PDF for {paper.title}: {pdf_error}")

        except Exception as download_error:
            logging.warning(f"Could not download or process source for {paper.title}: {download_error}")

        # Save the paper data (metadata and/or full text)
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(f"Title: {paper.title}\n")
            f.write(f"Authors: {', '.join([str(author) for author in paper.authors])}\n")
            f.write(f"Published: {paper.published}\n")
            f.write(f"arXiv ID: {paper.entry_id}\n")
            f.write(f"Abstract: {paper.summary}\n")
            f.write("="*80 + "\n")
            
            if full_text.strip():
                f.write("FULL TEXT:\n")
                f.write(full_text)
                logging.info(f"Successfully extracted and saved text to {output_path}")
            else:
                f.write("[Note: Source files not available or could not be processed - saved abstract and metadata only]\n")
                logging.info(f"Source not available, saved metadata and abstract to {output_path}")
                
    except Exception as e:
        logging.error(f"Failed to process paper {paper.title}: {e}")
    finally:
        # Clean up temporary directory
        if temp_dir and os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)

def main():
    while True:
        logging.info("--- Starting new arXiv Harvester cycle ---")
        
        try:
            query = random.choice(SEARCH_QUERIES)
            logging.info(f"Querying arXiv API for: '{query}'")
            
            search = arxiv.Search(
                query=query,
                max_results=20,
                sort_by=arxiv.SortCriterion.Relevance,
                sort_order=arxiv.SortOrder.Descending
            )
            
            results = list(search.results())
            logging.info(f"API returned {len(results)} results for query.")

            if results:
                with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                    executor.map(process_paper, results)

        except Exception as e:
            logging.error(f"An error occurred during the API search: {e}")

        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()

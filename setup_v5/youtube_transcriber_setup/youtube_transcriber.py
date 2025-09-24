import os
import time
import json
from datetime import datetime, timedelta
import requests
from youtube_transcript_api import YouTubeTranscriptApi
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
import re
import logging
import random
from concurrent.futures import ThreadPoolExecutor

# --- Configuration ---
LOG_DIR = "/factory/logs"
RAW_OUTPUT_DIR = "/factory/data/raw/youtube_transcripts"
# IMPORTANT: Replace with your key from Google Cloud Console
API_KEY = "YOUR_YOUTUBE_API_KEY_HERE"
MAX_WORKERS = 5
REST_PERIOD_SECONDS = 60 * 15 # 15 minutes

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'youtube_transcriber.log'), level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logging.getLogger('googleapiclient.discovery_cache').setLevel(logging.ERROR)
logging.getLogger('').addHandler(logging.StreamHandler())

class YouTubeTranscriptCrawler:
    def __init__(self, api_key):
        if "YOUR_YOUTUBE_API_KEY_HERE" in api_key:
            raise ValueError("YouTube API Key has not been set. Please edit the script and add your key.")
        self.youtube = build('youtube', 'v3', developerKey=api_key)
        self.search_queries = [
            "social media marketing tutorial", "AI training tutorial", "machine learning course",
            "digital marketing guide", "social media strategy tutorial", "artificial intelligence training",
            "deep learning tutorial", "facebook ads tutorial", "instagram marketing guide",
            "youtube marketing tutorial", "AI automation tutorial", "chatbot training",
            "content marketing tutorial", "SEO tutorial", "email marketing course"
        ]

    def search_educational_videos(self, query, max_results=10, days_back=30):
        try:
            published_after = (datetime.now() - timedelta(days=days_back)).isoformat() + 'Z'
            search_response = self.youtube.search().list(
                q=query + ' tutorial OR course OR guide OR training',
                part='id,snippet', maxResults=max_results, type='video',
                publishedAfter=published_after, order='relevance', videoDuration='medium'
            ).execute()
            
            videos = []
            educational_keywords = ['tutorial', 'course', 'guide', 'training', 'learn', 'how to', 'beginner', 'advanced', 'step by step', 'explained', 'basics']
            for item in search_response.get('items', []):
                snippet = item.get('snippet', {})
                if not snippet: continue
                title = snippet.get('title', '').lower()
                description = snippet.get('description', '').lower()
                if any(keyword in title or keyword in description for keyword in educational_keywords):
                    videos.append({
                        'video_id': item.get('id', {}).get('videoId'), 'title': snippet.get('title'),
                        'description': snippet.get('description'), 'channel': snippet.get('channelTitle'),
                        'published_at': snippet.get('publishedAt'), 'search_query': query
                    })
            return videos
        except HttpError as e:
            logging.error(f"An HTTP error occurred while searching for '{query}': {e}")
            return []

    def get_transcript(self, video_id, languages=['en']):
        try:
            transcript_list = YouTubeTranscriptApi.list_transcripts(video_id)
            transcript = None
            for lang in languages:
                try:
                    transcript = transcript_list.find_transcript([lang])
                    break
                except: continue
            if not transcript:
                try: transcript = transcript_list.find_generated_transcript(['en'])
                except: return None
            
            transcript_data = transcript.fetch()
            full_text = ' '.join([item['text'] for item in transcript_data])
            full_text = re.sub(r'\[.*?\]', '', full_text)
            full_text = re.sub(r'\s+', ' ', full_text).strip()
            return full_text
        except Exception as e:
            logging.warning(f"Could not retrieve transcript for {video_id}: {str(e)}")
            return None

    def crawl_and_save(self, query):
        """Crawls a single query and saves results to individual files."""
        logging.info(f"Processing query: '{query}'")
        videos = self.search_educational_videos(query, max_results=5)
        if not videos:
            logging.info(f"No relevant videos found for query: {query}")
            return

        for video in videos:
            video_id = video.get('video_id')
            if not video_id: continue
            
            transcript = self.get_transcript(video_id)
            if transcript:
                result = {**video, 'transcript': transcript, 'crawled_at': datetime.now().isoformat()}
                
                filename = f"youtube_{video_id}.json"
                filepath = os.path.join(RAW_OUTPUT_DIR, filename)
                with open(filepath, 'w', encoding='utf-8') as f:
                    json.dump(result, f, indent=2, ensure_ascii=False)
                logging.info(f"Successfully saved transcript for '{video.get('title', 'N/A')[:40]}...' to {filepath}")
            else:
                logging.warning(f"No transcript available for '{video.get('title', 'N/A')[:40]}...'")
            time.sleep(2)

def main():
    try:
        crawler = YouTubeTranscriptCrawler(API_KEY)
    except ValueError as e:
        logging.error(e)
        logging.error("Halting service until API key is provided.")
        return

    while True:
        logging.info("--- Starting new YouTube Crawler cycle ---")
        queries_to_run = random.sample(crawler.search_queries, min(len(crawler.search_queries), 3))
        
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            executor.map(crawler.crawl_and_save, queries_to_run)
            
        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()

import requests
import time

def fetch_metadata(app_id):
    url = f"https://flathub.org/api/v2/appstream/{app_id}"
    try:
        response = requests.get(url)
        response.raise_for_status()
        return response.json()
    except requests.HTTPError as e:
        print(f"Failed to fetch {app_id}: {e}")
        return None

def main(input_file):
    with open(input_file, encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            parts = line.strip().split('\t')
            if len(parts) < 3:
                print(f"Skipping invalid line {line_num}: {line.strip()}")
                continue
            
            app_id = parts[2]
            print(f"Fetching metadata for {app_id} (line {line_num})...")
            metadata = fetch_metadata(app_id)
            if metadata:
                # Just printing the app ID and metadata name here as example
                print(f"App ID: {app_id}")
                print(f"Name: {metadata.get('name', 'N/A')}")
                print(f"Verified: {metadata.get('metadata', {}).get('flathub::verification::verified', 'Unknown')}")
                print('-' * 40)

            # Be polite, sleep every 10 requests to avoid rate-limiting
            if line_num % 10 == 0:
                time.sleep(1)

if __name__ == "__main__":
    import sys
    if len(sys.argv) < 2:
        print("Usage: python fetch_flathub_metadata.py input_file.txt")
    else:
        main(sys.argv[1])


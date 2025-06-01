#!/usr/bin/env python3

import requests
import subprocess
import yaml
import json
from datetime import datetime
import time
import os
import sys

def get_flathub_apps():
    """Get all Flathub apps and save to dated file"""
    print("Fetching all Flathub apps...")
    
    # Run the curl command
    result = subprocess.run([
        'curl', '-X', 'GET',
        'https://flathub.org/api/v2/appstream?filter=apps',
        '-H', 'accept: application/json'
    ], capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"Error fetching apps: {result.stderr}")
        return None
    
    # Parse the response - it should be a JSON array
    apps_text = result.stdout.strip()
    print(f"Raw response (first 200 chars): {apps_text[:200]}")
    
    try:
        # Try to parse as JSON first
        apps = json.loads(apps_text)
        if isinstance(apps, list):
            print(f"Parsed as JSON array with {len(apps)} apps")
        else:
            print(f"Parsed as JSON but not an array: {type(apps)}")
            return None
    except json.JSONDecodeError:
        # Fallback to comma-separated parsing
        print("Not valid JSON, trying comma-separated parsing...")
        if apps_text.startswith('"') and apps_text.endswith('"'):
            apps_text = apps_text[1:-1]  # Remove surrounding quotes
        apps = [app.strip().strip('"') for app in apps_text.split(',')]
    
    # Save to dated file
    date_str = datetime.now().strftime("%Y-%m-%d")
    filename = f"flathub-verified-{date_str}.txt"
    
    with open(filename, 'w') as f:
        for app in apps:
            f.write(f"{app}\n")
    
    print(f"Saved {len(apps)} apps to {filename}")
    print(f"Sample apps: {apps[:5]}")
    return apps, filename

def load_apps_yaml(yaml_path):
    """Load existing apps.yaml file"""
    # Convert Windows path to WSL path if needed
    if yaml_path.startswith('/mnt/c/'):
        # Try the path as-is first
        if not os.path.exists(yaml_path):
            # Try converting to Windows path and back
            windows_path = yaml_path.replace('/mnt/c/', 'C:\\').replace('/', '\\')
            print(f"Trying Windows path: {windows_path}")
            
            # Also try some common variations
            possible_paths = [
                yaml_path,
                yaml_path.replace('/mnt/c/Users/', '/mnt/c/users/'),
                os.path.expanduser('~/apps.yaml'),
                './apps.yaml',
                'apps.yaml'
            ]
            
            for path in possible_paths:
                print(f"Trying path: {path}")
                if os.path.exists(path):
                    yaml_path = path
                    print(f"Found file at: {path}")
                    break
            else:
                print("Could not find apps.yaml file in any expected location")
                print("Please check the file path or run the script from the directory containing apps.yaml")
                return {}
    
    print(f"Attempting to load: {yaml_path}")
    print(f"File exists: {os.path.exists(yaml_path)}")
    
    if os.path.exists(yaml_path):
        print(f"File is readable: {os.access(yaml_path, os.R_OK)}")
        print(f"File size: {os.path.getsize(yaml_path)} bytes")
    
    try:
        with open(yaml_path, 'r') as f:
            data = yaml.safe_load(f)
            if data is None:
                print("YAML file is empty or contains only null")
                return {}
            print(f"Successfully loaded YAML with {len(data)} top-level entries")
            return data
    except FileNotFoundError:
        print(f"{yaml_path} not found, creating new one")
        return {}
    except yaml.YAMLError as e:
        print(f"YAML parsing error: {e}")
        return {}
    except Exception as e:
        print(f"Unexpected error loading YAML: {e}")
        return {}

def check_verification_status(app_id):
    """Check if an app is verified"""
    url = f"https://flathub.org/api/v2/verification/{app_id}/status"
    
    try:
        response = requests.get(url, headers={'accept': 'application/json'})
        if response.status_code == 200:
            data = response.json()
            return data.get('verified', False)
        else:
            # Don't print error for 404s (app not found) as that's normal
            if response.status_code != 404:
                print(f"Failed to check verification for {app_id}: {response.status_code}")
            return False
    except Exception as e:
        print(f"Error checking verification for {app_id}: {e}")
        return False

def get_app_details(app_id):
    """Get app name and summary from appstream"""
    url = f"https://flathub.org/api/v2/appstream/{app_id}?locale=en"
    
    try:
        response = requests.get(url, headers={'accept': 'application/json'})
        if response.status_code == 200:
            data = response.json()
            name = data.get('name', app_id)
            summary = data.get('summary', 'No description available')
            return name, summary
        else:
            print(f"Failed to get details for {app_id}: {response.status_code}")
            return app_id, 'No description available'
    except Exception as e:
        print(f"Error getting details for {app_id}: {e}")
        return app_id, 'No description available'

def generate_yaml_key(app_name):
    """Generate a YAML key from app name by replacing spaces with hyphens"""
    return app_name.replace(' ', '-').lower()

def main():
    # Check for command line argument
    if len(sys.argv) > 1:
        yaml_path = sys.argv[1]
    else:
        yaml_path = 'apps.yaml'
    
    print(f"Using YAML file: {yaml_path}")
    
    # Step 1: Get all Flathub apps
    flathub_apps, filename = get_flathub_apps()
    if not flathub_apps:
        return
    
    # Step 2: Load existing apps.yaml
    existing_apps = load_apps_yaml(yaml_path)
    
    # Get existing flatpak IDs
    existing_flatpak_ids = set()
    for app_name, app_data in existing_apps.items():
        if isinstance(app_data, dict) and 'flatpak' in app_data:
            existing_flatpak_ids.add(app_data['flatpak'])
    
    print(f"Found {len(existing_flatpak_ids)} existing flatpak entries")
    
    # Debug: show first few existing flatpak IDs
    if existing_flatpak_ids:
        print("Sample existing flatpak IDs:")
        for i, flatpak_id in enumerate(list(existing_flatpak_ids)[:5]):
            print(f"  {flatpak_id}")
        if len(existing_flatpak_ids) > 5:
            print(f"  ... and {len(existing_flatpak_ids) - 5} more")
    
    # Step 3: Find new apps not in apps.yaml
    new_apps = [app for app in flathub_apps if app not in existing_flatpak_ids]
    print(f"Found {len(new_apps)} new apps to check")
    
    # Debug: show first few new apps
    if new_apps:
        print("Sample new apps to check:")
        for i, app_id in enumerate(new_apps[:5]):
            print(f"  {app_id}")
        if len(new_apps) > 5:
            print(f"  ... and {len(new_apps) - 5} more")
    
    # Step 4: Check verification status for new apps
    verified_apps = []
    total_new = len(new_apps)
    
    for i, app_id in enumerate(new_apps, 1):
        if i % 100 == 0:  # Only print every 100th check to reduce spam
            print(f"Checking verification {i}/{total_new}: {app_id}")
        
        if check_verification_status(app_id):
            print(f"  ✓ Verified: {app_id}")
            verified_apps.append(app_id)
        
        # Be nice to the API
        time.sleep(0.05)  # Reduced delay since we're checking many apps
    
    print(f"\nFound {len(verified_apps)} verified apps to add")
    
    # Step 5: Get app details and add to apps.yaml
    if verified_apps:
        print("\nGetting details for verified apps...")
        
        for i, app_id in enumerate(verified_apps, 1):
            print(f"Getting details {i}/{len(verified_apps)}: {app_id}")
            
            name, summary = get_app_details(app_id)
            yaml_key = generate_yaml_key(name)
            
            # Ensure unique key
            original_key = yaml_key
            counter = 1
            while yaml_key in existing_apps:
                yaml_key = f"{original_key}-{counter}"
                counter += 1
            
            existing_apps[yaml_key] = {
                'flatpak': app_id,
                'comment': summary
            }
            
            print(f"  Added: {yaml_key} -> {app_id} ({name})")
            time.sleep(0.1)
        
        # Step 6: Save updated apps.yaml
        with open(yaml_path, 'w') as f:
            yaml.dump(existing_apps, f, default_flow_style=False, sort_keys=True)
        
        print(f"\nUpdated {yaml_path} with {len(verified_apps)} new verified apps")
    else:
        print("\nNo new verified apps to add")

if __name__ == "__main__":
    main()
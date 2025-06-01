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
    
    try:
        apps = json.loads(apps_text)
        print(f"Parsed as JSON array with {len(apps)} apps")
    except json.JSONDecodeError:
        print("Failed to parse as JSON")
        return None
    
    # Save to dated file
    date_str = datetime.now().strftime("%Y-%m-%d")
    filename = f"flathub-verified-{date_str}.txt"
    
    with open(filename, 'w') as f:
        for app in apps:
            f.write(f"{app}\n")
    
    print(f"Saved {len(apps)} apps to {filename}")
    return apps, filename

def load_apps_yaml_safe(yaml_path):
    """Load YAML file with custom parsing to handle shell commands"""
    print(f"Attempting to load: {yaml_path}")
    print(f"File exists: {os.path.exists(yaml_path)}")
    
    if not os.path.exists(yaml_path):
        print(f"{yaml_path} not found")
        return {}
    
    print(f"File size: {os.path.getsize(yaml_path)} bytes")
    
    try:
        with open(yaml_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Try standard YAML parsing first
        try:
            data = yaml.safe_load(content)
            if data is not None:
                print(f"Successfully loaded YAML with {len(data)} top-level entries")
                return data
        except yaml.YAMLError:
            print("Standard YAML parsing failed, trying custom parsing...")
        
        # Custom parsing for your format
        data = {}
        current_app = None
        
        lines = content.split('\n')
        i = 0
        
        while i < len(lines):
            line = lines[i]
            stripped = line.strip()
            
            # Skip empty lines and comments
            if not stripped or stripped.startswith('#'):
                i += 1
                continue
            
            # Calculate indentation
            indent = len(line) - len(line.lstrip())
            
            # Top-level app entry (no indentation)
            if indent == 0 and ':' in line:
                app_name = line.split(':')[0].strip()
                current_app = app_name
                data[current_app] = {}
                i += 1
                continue
            
            # Sub-entry (indented)
            if current_app and indent > 0 and ':' in line:
                key_value = line.strip()
                if ':' in key_value:
                    key = key_value.split(':', 1)[0].strip()
                    value = key_value.split(':', 1)[1].strip()
                    
                    # Handle multi-line values (commands with pipes, etc.)
                    if not value:  # Value is on next lines
                        i += 1
                        value_lines = []
                        while i < len(lines):
                            next_line = lines[i]
                            next_indent = len(next_line) - len(next_line.lstrip())
                            if next_indent > indent and next_line.strip():
                                value_lines.append(next_line.strip())
                                i += 1
                            else:
                                break
                        value = ' '.join(value_lines)
                        i -= 1  # Back up one since we'll increment at end of loop
                    
                    data[current_app][key] = value
            
            i += 1
        
        print(f"Custom parsing successful with {len(data)} top-level entries")
        return data
        
    except Exception as e:
        print(f"Error loading YAML: {e}")
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
            return False
    except Exception as e:
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
            return app_id, 'No description available'
    except Exception as e:
        return app_id, 'No description available'

def generate_yaml_key(app_name):
    """Generate a YAML key from app name by replacing spaces with hyphens"""
    return app_name.replace(' ', '-').lower()

def save_new_verified_apps(new_apps_data, date_str):
    """Save new verified apps to a separate file"""
    filename = f"new_verified_flatpaks_{date_str}.yaml"
    
    with open(filename, 'w', encoding='utf-8') as f:
        f.write(f"# New verified Flatpak apps found on {date_str}\n")
        f.write(f"# Total: {len(new_apps_data)} apps\n\n")
        
        for app_name in sorted(new_apps_data.keys()):
            app_data = new_apps_data[app_name]
            f.write(f"{app_name}:\n")
            f.write(f"  flatpak: {app_data['flatpak']}\n")
            f.write(f"  comment: {app_data['comment']}\n")
            f.write("\n")
    
    print(f"Saved {len(new_apps_data)} new verified apps to {filename}")
    return filename

def main():
    # Check for command line argument
    if len(sys.argv) > 1:
        yaml_path = sys.argv[1]
    else:
        yaml_path = 'apps.yaml'
    
    print(f"Reading from YAML file: {yaml_path}")
    
    # Step 1: Get all Flathub apps
    flathub_apps, flathub_filename = get_flathub_apps()
    if not flathub_apps:
        return
    
    # Step 2: Load existing apps.yaml (READ ONLY)
    existing_apps = load_apps_yaml_safe(yaml_path)
    
    # Get existing flatpak IDs
    existing_flatpak_ids = set()
    for app_name, app_data in existing_apps.items():
        if isinstance(app_data, dict) and 'flatpak' in app_data:
            existing_flatpak_ids.add(app_data['flatpak'])
    
    print(f"Found {len(existing_flatpak_ids)} existing flatpak entries in {yaml_path}")
    
    # Step 3: Find new apps not in apps.yaml
    new_apps = [app for app in flathub_apps if app not in existing_flatpak_ids]
    print(f"Found {len(new_apps)} new apps to check for verification")
    
    # Step 4: Check verification status for new apps
    verified_apps = []
    total_new = len(new_apps)
    
    print("Checking verification status...")
    for i, app_id in enumerate(new_apps, 1):
        if i % 100 == 0:
            print(f"Progress: {i}/{total_new}")
        
        if check_verification_status(app_id):
            print(f"  ✓ Verified: {app_id}")
            verified_apps.append(app_id)
        
        time.sleep(0.05)
    
    print(f"\nFound {len(verified_apps)} verified apps that are new")
    
    # Step 5: Get app details for verified apps
    if verified_apps:
        print("\nGetting details for verified apps...")
        new_apps_data = {}
        
        for i, app_id in enumerate(verified_apps, 1):
            print(f"Getting details {i}/{len(verified_apps)}: {app_id}")
            
            name, summary = get_app_details(app_id)
            yaml_key = generate_yaml_key(name)
            
            # Ensure unique key within new apps
            original_key = yaml_key
            counter = 1
            while yaml_key in new_apps_data:
                yaml_key = f"{original_key}-{counter}"
                counter += 1
            
            new_apps_data[yaml_key] = {
                'flatpak': app_id,
                'comment': summary
            }
            
            print(f"  Will add: {yaml_key} -> {app_id} ({name})")
            time.sleep(0.1)
        
        # Step 6: Save new verified apps to separate file
        date_str = datetime.now().strftime("%Y-%m-%d")
        output_filename = save_new_verified_apps(new_apps_data, date_str)
        
        print(f"\n✅ Complete! Found {len(verified_apps)} new verified Flatpak apps")
        print(f"📁 Original apps.yaml: UNCHANGED")
        print(f"📁 All Flathub apps: {flathub_filename}")
        print(f"📁 New verified apps: {output_filename}")
        print(f"\nYou can review {output_filename} and manually add entries to your apps.yaml if desired.")
        
    else:
        print("\n✅ No new verified apps found")
        print("📁 Original apps.yaml: UNCHANGED")

if __name__ == "__main__":
    main()
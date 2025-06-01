#!/usr/bin/env python3

import subprocess
import yaml
import string
import time
import os
import sys
from datetime import datetime

def get_snap_search_results():
    """Search through the alphabet and collect all snap results"""
    all_snaps = []
    
    print("Searching through alphabet for snaps...")
    
    for letter in string.ascii_lowercase:
        print(f"Searching for snaps starting with '{letter}'...")
        
        try:
            result = subprocess.run([
                'snap', 'search', letter
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')
                
                # Skip header line
                if len(lines) > 1:
                    for line in lines[1:]:
                        if line.strip():
                            snap_info = parse_snap_line(line)
                            if snap_info:
                                all_snaps.append(snap_info)
                
                print(f"  Found {len([l for l in lines[1:] if l.strip()])} snaps")
            else:
                print(f"  Error searching for '{letter}': {result.stderr}")
                
        except subprocess.TimeoutExpired:
            print(f"  Timeout searching for '{letter}'")
        except Exception as e:
            print(f"  Error searching for '{letter}': {e}")
        
        # Be nice to the snap store
        time.sleep(0.5)
    
    print(f"\nTotal snaps found: {len(all_snaps)}")
    return all_snaps

def parse_snap_line(line):
    """Parse a line from snap search output"""
    # Split by multiple spaces to separate columns
    parts = [part.strip() for part in line.split() if part.strip()]
    
    if len(parts) < 5:
        return None
    
    name = parts[0]
    version = parts[1]
    publisher = parts[2]
    notes = parts[3] if parts[3] != '-' else ''
    summary = ' '.join(parts[4:])
    
    # Check if publisher is verified (ends with **)
    is_verified = publisher.endswith('**')
    if is_verified:
        publisher = publisher[:-2]  # Remove the **
    
    # Check if it's a classic snap
    is_classic = 'classic' in notes
    
    return {
        'name': name,
        'version': version,
        'publisher': publisher,
        'verified': is_verified,
        'classic': is_classic,
        'notes': notes,
        'summary': summary
    }

def load_apps_yaml_safe(yaml_path):
    """Load YAML file with custom parsing to handle shell commands"""
    print(f"Loading apps.yaml from: {yaml_path}")
    
    if not os.path.exists(yaml_path):
        print(f"{yaml_path} not found")
        return {}
    
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

def save_apps_yaml_safe(yaml_path, data):
    """Save YAML file preserving the original format"""
    with open(yaml_path, 'w', encoding='utf-8') as f:
        for app_name in data.keys():  # Preserve original order
            app_data = data[app_name]
            f.write(f"{app_name}:\n")
            
            # Write fields in specific order: snap/custom, uninstall, flatpak, comment
            field_order = ['snap', 'custom', 'uninstall', 'flatpak', 'comment']
            written_fields = set()
            
            # Write fields in preferred order
            for field in field_order:
                if field in app_data:
                    value = app_data[field]
                    # Handle long commands that might contain special characters
                    if len(str(value)) > 80 or any(char in str(value) for char in ['|', '&', ';', '&&', '||']):
                        escaped_value = str(value).replace('"', '\\"')
                        f.write(f'  {field}: "{escaped_value}"\n')
                    else:
                        f.write(f"  {field}: {value}\n")
                    written_fields.add(field)
            
            # Write any remaining fields
            for key, value in app_data.items():
                if key not in written_fields:
                    if len(str(value)) > 80 or any(char in str(value) for char in ['|', '&', ';', '&&', '||']):
                        escaped_value = str(value).replace('"', '\\"')
                        f.write(f'  {key}: "{escaped_value}"\n')
                    else:
                        f.write(f"  {key}: {value}\n")
            
            f.write("\n")

def save_new_verified_snaps(new_snaps_data, date_str):
    """Save new verified snaps to a separate file"""
    filename = f"new_verified_snaps_{date_str}.yaml"
    
    with open(filename, 'w', encoding='utf-8') as f:
        f.write(f"# New verified Snap packages found on {date_str}\n")
        f.write(f"# Total: {len(new_snaps_data)} packages\n\n")
        
        for app_name in sorted(new_snaps_data.keys()):
            app_data = new_snaps_data[app_name]
            f.write(f"{app_name}:\n")
            
            if 'custom' in app_data:
                f.write(f"  custom: {app_data['custom']}\n")
                f.write(f"  uninstall: {app_data['uninstall']}\n")
            else:
                f.write(f"  snap: {app_data['snap']}\n")
            
            f.write(f"  comment: {app_data['comment']}\n")
            f.write("\n")
    
    print(f"Saved {len(new_snaps_data)} new verified snaps to {filename}")
    return filename

def main():
    # Check for command line argument
    if len(sys.argv) > 1:
        yaml_path = sys.argv[1]
    else:
        yaml_path = 'apps.yaml'
    
    print(f"Using YAML file: {yaml_path}")
    
    # Step 1: Get all verified snaps
    all_snaps = get_snap_search_results()
    verified_snaps = [snap for snap in all_snaps if snap['verified']]
    
    print(f"Found {len(verified_snaps)} verified snaps out of {len(all_snaps)} total")
    
    # Step 2: Load existing apps.yaml
    existing_apps = load_apps_yaml_safe(yaml_path)
    
    # Step 3: Process verified snaps
    classic_fixes = 0
    new_snaps_data = {}
    
    for snap in verified_snaps:
        snap_name = snap['name']
        
        if snap_name in existing_apps:
            # App exists in apps.yaml
            app_data = existing_apps[snap_name]
            
            if snap['classic']:
                # It's a classic snap, check if we need to fix it
                if 'snap' in app_data and 'custom' not in app_data:
                    # Convert from regular snap to classic snap
                    print(f"Converting {snap_name} to classic snap in apps.yaml")
                    app_data['custom'] = f"snap install {snap_name} --classic"
                    app_data['uninstall'] = f"snap remove {snap_name}"
                    del app_data['snap']  # Remove the old snap field
                    classic_fixes += 1
                else:
                    print(f"Skipping {snap_name} (already properly configured)")
            else:
                # It's a regular snap, skip since it already exists
                print(f"Skipping {snap_name} (already exists)")
        else:
            # App doesn't exist in apps.yaml, add it to new snaps file
            print(f"Found new verified snap: {snap_name}")
            
            if snap['classic']:
                # Classic snap
                new_entry = {
                    'custom': f"snap install {snap_name} --classic",
                    'uninstall': f"snap remove {snap_name}",
                    'comment': snap['summary']
                }
            else:
                # Regular snap
                new_entry = {
                    'snap': snap_name,
                    'comment': snap['summary']
                }
            
            new_snaps_data[snap_name] = new_entry
    
    # Step 4: Save results
    changes_made = False
    
    # Save apps.yaml if we made classic fixes
    if classic_fixes > 0:
        save_apps_yaml_safe(yaml_path, existing_apps)
        print(f"\n✅ Updated apps.yaml with {classic_fixes} classic snap fixes")
        changes_made = True
    
    # Save new snaps to separate file
    if new_snaps_data:
        date_str = datetime.now().strftime("%Y-%m-%d")
        save_new_verified_snaps(new_snaps_data, date_str)
        print(f"📁 New verified snaps: new_verified_snaps_{date_str}.yaml")
        changes_made = True
    
    if not changes_made:
        print("\n✅ No changes needed - all verified snaps are already properly configured")
    else:
        print(f"\n📁 apps.yaml: {'UPDATED' if classic_fixes > 0 else 'UNCHANGED'}")

if __name__ == "__main__":
    main()
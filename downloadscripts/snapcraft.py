#!/usr/bin/env python3

import subprocess
import yaml
import string
import time
import os
import sys
from datetime import datetime

def get_snap_sections():
    """Get list of available snap sections"""
    sections = [
        'art-and-design',
        'books-and-reference', 
        'development',
        'devices-and-iot',
        'education',
        'entertainment',
        'featured',
        'finance',
        'games',
        'health-and-fitness',
        'music-and-audio',
        'news-and-weather',
        'personalisation',
        'photo-and-video',
        'productivity',
        'science',
        'security',
        'server-and-cloud',
        'social',
        'utilities'
    ]
    return sections

def get_snap_search_results():
    """Search through the alphabet and sections to collect all snap results"""
    all_snaps = []
    seen_snaps = set()  # To avoid duplicates
    
    print("Searching through alphabet for snaps...")
    
    # Search by alphabet
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
                    found_count = 0
                    for line in lines[1:]:
                        if line.strip():
                            snap_info = parse_snap_line(line)
                            if snap_info and snap_info['name'] not in seen_snaps:
                                all_snaps.append(snap_info)
                                seen_snaps.add(snap_info['name'])
                                found_count += 1
                
                print(f"  Found {found_count} new snaps")
            else:
                print(f"  Error searching for '{letter}': {result.stderr}")
                
        except subprocess.TimeoutExpired:
            print(f"  Timeout searching for '{letter}'")
        except Exception as e:
            print(f"  Error searching for '{letter}': {e}")
        
        # Be nice to the snap store
        time.sleep(0.5)
    
    print(f"\nAlphabet search complete. Found {len(all_snaps)} unique snaps so far.")
    
    # Search by sections
    print("\nSearching through sections for snaps...")
    sections = get_snap_sections()
    
    for section in sections:
        print(f"Searching section '{section}'...")
        
        try:
            result = subprocess.run([
                'snap', 'find', f'--section={section}'
            ], capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')
                
                # Skip header line
                if len(lines) > 1:
                    found_count = 0
                    for line in lines[1:]:
                        if line.strip():
                            snap_info = parse_snap_line(line)
                            if snap_info and snap_info['name'] not in seen_snaps:
                                all_snaps.append(snap_info)
                                seen_snaps.add(snap_info['name'])
                                found_count += 1
                
                print(f"  Found {found_count} new snaps in {section}")
            else:
                print(f"  Error searching section '{section}': {result.stderr}")
                
        except subprocess.TimeoutExpired:
            print(f"  Timeout searching section '{section}'")
        except Exception as e:
            print(f"  Error searching section '{section}': {e}")
        
        # Be nice to the snap store
        time.sleep(0.5)
    
    print(f"\nTotal unique snaps found: {len(all_snaps)}")
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
                return data, content
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
        return data, content
        
    except Exception as e:
        print(f"Error loading YAML: {e}")
        return {}, ""

def save_apps_yaml_minimal(yaml_path, original_content, changes):
    """Save YAML file with minimal changes - only modify what needs to be changed"""
    lines = original_content.split('\n')
    
    for app_name, modifications in changes.items():
        # Find the app section
        app_line_idx = None
        for i, line in enumerate(lines):
            if line.strip() == f"{app_name}:":
                app_line_idx = i
                break
        
        if app_line_idx is None:
            continue
        
        # Find the end of this app's section
        section_end = len(lines)
        for i in range(app_line_idx + 1, len(lines)):
            line = lines[i]
            if line.strip() and not line.startswith(' ') and not line.startswith('\t'):
                section_end = i
                break
        
        # Apply modifications within this section
        for field, action in modifications.items():
            if action == 'remove_snap':
                # Remove the snap: line
                for i in range(app_line_idx + 1, section_end):
                    if lines[i].strip().startswith('snap:'):
                        del lines[i]  # Actually delete instead of emptying
                        section_end -= 1  # Adjust section end
                        break
            elif action.startswith('add_custom:'):
                custom_value = action[11:]  # Remove 'add_custom:' prefix
                # Add custom line after app name
                lines.insert(app_line_idx + 1, f"  custom: {custom_value}")
                section_end += 1
            elif action.startswith('add_uninstall:'):
                uninstall_value = action[14:]  # Remove 'add_uninstall:' prefix
                # Add uninstall line after custom line
                custom_line_idx = None
                for i in range(app_line_idx + 1, section_end):
                    if lines[i].strip().startswith('custom:'):
                        custom_line_idx = i
                        break
                if custom_line_idx:
                    lines.insert(custom_line_idx + 1, f"  uninstall: {uninstall_value}")
    
    # Don't filter out empty lines - preserve original spacing
    with open(yaml_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))

def save_new_verified_snaps(new_snaps_data, date_str):
    """Save new verified snaps to a separate file"""
    filename = f"new_verified_snaps_{date_str}.yaml"
    
    with open(filename, 'w', encoding='utf-8') as f:
        f.write(f"# New verified Snap packages found on {date_str}\n")
        f.write(f"# Searched through alphabet + all sections\n")
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
    
    # Step 1: Get all verified snaps (alphabet + sections)
    all_snaps = get_snap_search_results()
    verified_snaps = [snap for snap in all_snaps if snap['verified']]
    
    print(f"Found {len(verified_snaps)} verified snaps out of {len(all_snaps)} total")
    
    # Step 2: Load existing apps.yaml
    existing_apps, original_content = load_apps_yaml_safe(yaml_path)
    
    # Step 3: Process verified snaps
    classic_fixes = 0
    new_snaps_data = {}
    changes_to_make = {}
    
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
                    changes_to_make[snap_name] = {
                        'snap': 'remove_snap',
                        'custom': f"add_custom:snap install {snap_name} --classic",
                        'uninstall': f"add_uninstall:snap remove {snap_name}"
                    }
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
        save_apps_yaml_minimal(yaml_path, original_content, changes_to_make)
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
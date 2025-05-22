import re
import sys

def normalize_name(name):
    # lowercase
    name = name.lower()
    # replace any sequence of non-alphanumeric chars (spaces, punctuation, etc.) with a single dash
    name = re.sub(r'[^a-z0-9]+', '-', name)
    # strip leading/trailing dashes
    name = name.strip('-')
    return name

def parse_log_file(filename):
    verified_apps = {}
    with open(filename, encoding="utf-8") as f:
        lines = f.readlines()

    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if line.startswith("Fetching metadata for "):
            # Expect next lines: App ID, Name, Verified, separator
            app_id_line = lines[i+1].strip() if i+1 < len(lines) else ''
            name_line = lines[i+2].strip() if i+2 < len(lines) else ''
            verified_line = lines[i+3].strip() if i+3 < len(lines) else ''

            # Extract app ID
            app_id_match = re.match(r"App ID:\s*(.*)", app_id_line)
            app_id = app_id_match.group(1).strip() if app_id_match else None

            # Extract name
            name_match = re.match(r"Name:\s*(.*)", name_line)
            name = name_match.group(1).strip() if name_match else None

            # Extract verified
            verified_match = re.match(r"Verified:\s*(.*)", verified_line)
            verified = verified_match.group(1).strip().lower() if verified_match else 'false'

            if verified == 'true' and app_id and name:
                key = normalize_name(name)
                verified_apps[key] = app_id

            i += 5  # skip these lines plus separator line
        else:
            i += 1

    return verified_apps

def output_yaml(verified_apps):
    for name, app_id in verified_apps.items():
        print(f"{name}:")
        print(f"  flatpak: {app_id}")
        print()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python parse_verified_log.py your_log.txt")
        sys.exit(1)

    filename = sys.argv[1]
    apps = parse_log_file(filename)
    output_yaml(apps)


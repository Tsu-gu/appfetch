import re

def parse_snap_file(filename):
    with open(filename, 'r') as f:
        lines = f.readlines()

    entries_started = False

    for line in lines:
        if not entries_started:
            if line.startswith('Name'):
                entries_started = True
            continue
        if line.strip() == '':
            continue

        parts = re.split(r'\s{2,}', line.strip())
        if len(parts) < 3:
            continue

        snap_name, version, publisher = parts[0], parts[1], parts[2]

        # Skip names containing "ubuntu" or "core" (case-insensitive)
        if re.search(r'ubuntu', snap_name, re.IGNORECASE) or re.search(r'core', snap_name, re.IGNORECASE):
            continue

        # Only include publishers ending in **
        if re.search(r'\*\*$', publisher):
            print(f"{snap_name}:")
            print(f"  snap: {snap_name}")
            print()

if __name__ == '__main__':
    import sys
    if len(sys.argv) != 2:
        print("Usage: python parse_snap.py <filename>")
    else:
        parse_snap_file(sys.argv[1])


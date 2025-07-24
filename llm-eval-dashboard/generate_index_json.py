import os
import json

RESULTS_DIR = "./results"
INDEX_FILE = os.path.join(RESULTS_DIR, "index.json")

def generate_index():
    json_files = [
        f for f in os.listdir(RESULTS_DIR)
        if f.endswith(".json") and f != "index.json"
    ]
    print(json_files)
    with open(INDEX_FILE, "w") as f:
        json.dump(sorted(json_files), f, indent=2)
    print(f"✅ Generated {INDEX_FILE} with {len(json_files)} files.")

if __name__ == "__main__":
    generate_index()

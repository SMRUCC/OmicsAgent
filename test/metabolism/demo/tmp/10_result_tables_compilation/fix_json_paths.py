"""Fix JSON file: replace backslashes with forward slashes in paths."""
import re

json_path = r"G:/OmicsWorks/test/metabolism/demo/analysis\2_pca_plsda_oplsda_analysis\table_descriptions.json"

with open(json_path, 'r', encoding='utf-8') as f:
 content = f.read()

# Replace backslashes with forward slashes
fixed = content.replace('\\', '/')

with open(json_path, 'w', encoding='utf-8') as f:
 f.write(fixed)

print("Fixed JSON paths: replaced \\ with /")
print(json_path)

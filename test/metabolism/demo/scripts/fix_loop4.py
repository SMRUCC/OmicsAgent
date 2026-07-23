path = "G:/OmicsWorks/test/metabolism/demo/scripts/module_4_limma_analysis.R"
with open(path, 'r', encoding='utf-8') as f:
 content = f.read()

# The line: for (i in1:nrow(combined)) {
# "in1" should be "in1" (with space between "in" and "1")
old_str = "in1:nrow(combined)"
new_str = "in1:nrow(combined)"
print(f"Old bytes: {old_str.encode('utf-8')}")
print(f"New bytes: {new_str.encode('utf-8')}")

if old_str in content:
 content = content.replace(old_str, new_str)
 with open(path, 'w', encoding='utf-8') as f:
 f.write(content)
 print("Fixed! Added space between 'in' and '1'")
else:
 print("Pattern 'in1:nrow(combined)' not found!")
 # Let's search for similar patterns
 import re
 for m in re.finditer(r'in\d*:nrow\(combined\)', content):
 print(f"Found: {repr(m.group())}")

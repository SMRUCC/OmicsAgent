path = "G:/OmicsWorks/test/metabolism/demo/scripts/module_4_limma_analysis.R"
with open(path, 'r', encoding='utf-8') as f:
 content = f.read()

# The line currently has: for (i in1:nrow(combined)) {
# It needs: for (i in1:nrow(combined)) {
# Where "in1" -> "in1" (add a space between "in" and "1")

old = "for (i in1:nrow(combined)) {"
new = "for (i in1:nrow(combined)) {"
print(f"Old: {repr(old)}")
print(f"New: {repr(new)}")

if old in content:
 content = content.replace(old, new)
 with open(path, 'w', encoding='utf-8') as f:
 f.write(content)
 print("Fixed!")
else:
 print("Pattern not found!")
 # Search for similar patterns
 import re
 matches = list(re.finditer(r'for.*nrow.*combined', content))
 for m in matches:
 print(f"Found: {repr(m.group())}")

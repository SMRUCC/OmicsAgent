# Python script to fix the for loop syntax in the R script
import re

path = "G:/OmicsWorks/test/metabolism/demo/scripts/module_4_limma_analysis.R"
with open(path, 'r', encoding='utf-8') as f:
 content = f.read()

# Fix: "in1:nrow" -> "in1:nrow" (add space between 'in' and '1')
# The old text has no space: "in1:nrow"
# The new text has a space: "in1:nrow"
content = content.replace("(i in1:nrow(combined))", "(i in1:nrow(combined))")

with open(path, 'w', encoding='utf-8') as f:
 f.write(content)

# Verify
with open(path, 'r', encoding='utf-8') as f:
 for i, line in enumerate(f,1):
 if 'nrow(combined)' in line and 'for' in line:
 print(f"Line {i}: {repr(line)}")
 break

print("Done!")

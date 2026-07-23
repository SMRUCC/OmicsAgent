r = open("G:/OmicsWorks/test/metabolism/demo/scripts/module_4_limma_analysis.R", "r").read()
import re
for m in re.finditer(r"for.*nrow.*combined.*\{", r):
 print("Found:", repr(m.group()))
 # Show hex bytes
 for c in m.group():
 print(hex(ord(c)), end=" ")
 print()

path = "G:/OmicsWorks/test/metabolism/demo/scripts/module_4_limma_analysis.R"
with open(path, 'r', encoding='utf-8') as f:
 content = f.read()
old = "in1:nrow"
new = "in" + " " + "1:nrow"
print(f"Old: {repr(old)}, New: {repr(new)}")
if old in content:
 content = content.replace(old, new)
 with open(path, 'w', encoding='utf-8') as f:
 f.write(content)
 print("Fixed!")
else:
 print("Not found!")

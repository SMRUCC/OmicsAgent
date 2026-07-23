content = open("G:/OmicsWorks/test/metabolism/demo/scripts/module_4_limma_analysis.R", "r").read()
old = "in1:nrow"
new = "in1:nrow"
if old in content:
 content = content.replace(old, new)
 open("G:/OmicsWorks/test/metabolism/demo/scripts/module_4_limma_analysis.R", "w").write(content)
 print("Fixed!")
else:
 print("Not found!")

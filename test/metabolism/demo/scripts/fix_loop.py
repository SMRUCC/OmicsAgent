rscript_path = "G:/OmicsWorks/test/metabolism/demo/scripts/module_4_limma_analysis.R"
with open(rscript_path, 'r') as f:
 data = f.read()
# Replace the problematic line
data = data.replace('for (i in1:nrow(combined)) {', 'for (i in1:nrow(combined)) {')
with open(rscript_path, 'w') as f:
 f.write(data)
print("Replacement done")

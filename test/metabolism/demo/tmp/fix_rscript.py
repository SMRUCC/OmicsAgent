with open("G:/OmicsWorks/test/metabolism/demo/tmp/4_limma_differential_analysis/scripts/limma_differential_analysis.R", "r") as f:
 content = f.read()

# Fix the problematic line
content = content.replace("fsize <- if (srn)7 else1", "fsize <- ifelse(srn,7,1)")

with open("G:/OmicsWorks/test/metabolism/demo/tmp/4_limma_differential_analysis/scripts/limma_differential_analysis.R", "w") as f:
 f.write(content)

print("Fixed successfully")

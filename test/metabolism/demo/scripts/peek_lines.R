file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_enhanced_analysis.R"
lines <- readLines(file_path, warn = FALSE)
# Check lines354-360
hits <- grep("regression", lines)
cat("Lines with 'regression':\n")
for (h in hits) {
 cat(sprintf("%3d: %s\n", h, substr(lines[h],1,120)))
}

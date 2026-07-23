file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_enhanced_analysis.R"
lines <- readLines(file_path, warn = FALSE)
hits <- grep("splsda|regression", lines)
cat("Lines with 'splsda' or 'regression':\n")
for (h in hits) {
 cat(sprintf("%3d: %s\n", h, lines[h]))
}

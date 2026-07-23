file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_enhanced_analysis.R"
lines <- readLines(file_path, warn = FALSE)
idx <- grep("regression", lines)
cat("Lines with 'regression':\n")
for (i in idx) cat(" ", i, ":", lines[i], "\n")

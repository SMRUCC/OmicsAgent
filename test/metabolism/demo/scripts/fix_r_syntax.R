# Fix R script syntax errors - add spaces after 'for (i in'
file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_enhanced_analysis.R"
lines <- readLines(file_path, warn = FALSE)

# Fix patterns: "for (i in1:" -> "for (i in1:"
# Also: "for (p in1:" -> "for (p in1:"
lines <- gsub("for \\(i in1:", "for (i in1:", lines)
lines <- gsub("for \\(p in1:", "for (p in1:", lines)
lines <- gsub("for \\(i in1:n", "for (i in1:n", lines)

writeLines(lines, file_path)
cat("Fixed syntax errors.\n")

# Verify
lines2 <- readLines(file_path, warn = FALSE)
hits <- grep("in1", lines2)
if (length(hits) >0) {
 cat("WARNING: remaining 'in1' patterns at lines:", hits, "\n")
} else {
 cat("OK: No remaining 'in1' patterns.\n")
}

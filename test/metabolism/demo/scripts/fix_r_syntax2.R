# Fix 'for (i in1:' -> 'for (i in1:' by inserting a space
file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_enhanced_analysis.R"
lines <- readLines(file_path, warn = FALSE)

# Fix all patterns where "in" is followed by a digit without space
lines <- gsub("(for \\([a-z]+ in)([0-9])", "\\1 \\2", lines)

writeLines(lines, file_path)
cat("Fixed syntax errors.\n")

# Verify
lines2 <- readLines(file_path, warn = FALSE)
hits <- grep("in[0-9]", lines2)
if (length(hits) >0) {
 cat("WARNING: remaining 'in<NUMBER>' patterns at lines:", hits, "\n")
 for (h in hits) cat(" Line", h, ":", lines2[h], "\n")
} else {
 cat("OK: No remaining 'in<NUMBER>' patterns.\n")
}

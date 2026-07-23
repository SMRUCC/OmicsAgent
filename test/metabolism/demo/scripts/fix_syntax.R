file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

# The fix R script file had issues - let me just do proper sed replacements
# The pattern is "in1:" or "in1:n" or "in1:n_" etc without space before number
lines <- gsub("for \\(i in1:", "for (i in1:", lines)
lines <- gsub("for \\(p in1:", "for (p in1:", lines)
lines <- gsub("for \\(i in1:n", "for (i in1:n", lines)

writeLines(lines, file_path)
cat("Fixed syntax errors in module_2_pca_plsda_oplsda.R\n")

# Verify
lines2 <- readLines(file_path, warn = FALSE)
hits <- grep("in1", lines2)
if (length(hits) >0) {
 cat("WARNING: remaining 'in1' patterns at lines:", hits, "\n")
 for (h in hits) cat(" Line", h, ":", lines2[h], "\n")
} else {
 cat("OK: No remaining 'in1' patterns.\n")
}

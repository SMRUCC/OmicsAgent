file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

cat("Before fix - lines with 'in1':\n")
hits <- grep("in1", lines)
for (h in hits) cat(" Line", h, ":", lines[h], "\n")

# The REAL fix: replace "in1" with "in1" in for loop contexts
# Wait, I need to actually add a space. Let me do this properly.
# Pattern: "in1:" or "in1:n" or "in1:n_" → add space after "in"
lines <- gsub("(for \\([a-z]+ in)1:", "\\11:", lines)
lines <- gsub("(for \\([a-z]+ in)1:n", "\\11:n", lines)
lines <- gsub("(for \\([a-z]+ in)1:n_", "\\11:n_", lines)

writeLines(lines, file_path)

cat("\nAfter fix:\n")
lines2 <- readLines(file_path, warn = FALSE)
hits2 <- grep("in1", lines2)
if (length(hits2) >0) {
 cat("WARNING: remaining issues at lines:", hits2, "\n")
 for (h in hits2) cat(" Line", h, ":", lines2[h], "\n")
} else {
 cat("All 'in1' patterns fixed!\n")
}

# Also check for "in1" without a following space (to make sure)
hits3 <- grep("in1", lines2)
cat("Lines with 'in1' (correct):", length(hits3), "\n")

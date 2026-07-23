file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

cat("Total lines:", length(lines), "\n")

# Find all lines with "in1" pattern
hits <- grep("in1", lines)
cat("Lines with 'in1':", hits, "\n")
for (h in hits) {
 cat(" Line", h, ":", lines[h], "\n")
}

# Proper fix: replace "in1" with "in1" - but we need to actually change it
# The problem is "for (i in1:n" should be "for (i in1:n"
# Let me just re-read and manually check

# Actually, let me just rewrite the problematic sections
# Find and replace "in1:" with "in1:" - this is NOT a change!

# Let me check the actual content character by character
for (h in hits) {
 line <- lines[h]
 # Find the "in1" position
 pos <- regexpr("in1", line)
 if (pos >0) {
 before <- substr(line, pos-5, pos-1)
 after <- substr(line, pos, pos+10)
 cat(sprintf(" Context around 'in1': '...%s[in1]%s...'\n", before, after))
 }
}

cat("\nThe fix needs: 'in1' -> 'in1' (add space before digit)\n")
cat("Let me do a proper replacement...\n")

# Replace "in1:" with "in1:" (with space!)
# Note: The gsub pattern is regex, replacement is literal
lines <- gsub("for \\(i in1:", "for (i in1:", lines)
lines <- gsub("for \\(p in1:", "for (p in1:", lines)
lines <- gsub("for \\(i in1:n", "for (i in1:n", lines)

writeLines(lines, file_path)

# Verify
lines2 <- readLines(file_path, warn = FALSE)
hits2 <- grep("in1", lines2)
cat("After fix - lines with 'in1':", hits2, "\n")
if (length(hits2) >0) {
 for (h in hits2) cat(" Line", h, ":", lines2[h], "\n")
} else {
 cat("All fixed!\n")
}

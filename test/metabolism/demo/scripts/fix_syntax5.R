# This script fixes the "in1" -> "in1" spacing issue in for loops
file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

cat("BEFORE:\n")
for (h in grep("in1", lines)) cat(" Line", h, ":", lines[h], "\n")

# The pattern is "in1" (no space between 'n' and '1')
# The replacement should be "in1" (space between 'n' and '1')
# In R string literals:
# pattern: "in1" 
# replacement: "in1" (with explicit space character)

# More precise: target only the specific contexts
# Replace "in1:" with "in1:" (adding space)
# Replace "in1:n" with "in1:n" (adding space)
# Replace "in1:n_" with "in1:n_" (adding space)

# Using fixed=TRUE for literal matching
for (i in seq_along(lines)) {
 line <- lines[i]
 new_line <- line
 # Replace "in1:" with "in1:" 
 # Note: the FIRST string has no space, the SECOND has a space
 new_line <- gsub("in1:", "in1:", new_line, fixed = TRUE)
 # If changed, continue to avoid double-processing
 if (new_line != line) {
 lines[i] <- new_line
 cat(" Fixed line", i, ": '", line, "' -> '", new_line, "'\n", sep = "")
 next
 }
 # Try "in1:n" pattern
 new_line <- gsub("in1:n", "in1:n", line, fixed = TRUE)
 if (new_line != line) {
 lines[i] <- new_line
 cat(" Fixed line", i, ": '", line, "' -> '", new_line, "'\n", sep = "")
 next
 }
}

writeLines(lines, file_path)

cat("\nVERIFICATION:\n")
lines2 <- readLines(file_path, warn = FALSE)
hits <- grep("in1", lines2)
if (length(hits) >0) {
 cat("STILL has 'in1' patterns at lines:", hits, "\n")
 for (h in hits) {
 line <- lines2[h]
 # Show exact characters
 chars <- strsplit(line, "")[[1]]
 cat(" Line", h, ": ")
 for (j in seq_along(chars)) {
 if (chars[j] == " ") cat("_", sep = "")
 else cat(chars[j])
 }
 cat("\n")
 }
} else {
 cat("All fixed! No more 'in1' patterns.\n")
}

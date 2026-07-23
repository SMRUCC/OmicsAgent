file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

# Find the problematic section and fix it
# The issue is a missing } to close the else block before "# Extract scores..."

# Find all lines
for (i in300:330) {
 cat("Line", i, ":", lines[i], "\n")
}

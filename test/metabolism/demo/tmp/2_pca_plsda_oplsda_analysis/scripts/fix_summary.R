# Fix summary section in the analysis script using R
lines <- readLines("G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
cat("Total lines:", length(lines), "\n")

# Find the old summary text and replace
old_lines <- grep("opls_params\\$Value", lines)
cat("Lines with old reference:", old_lines, "\n")

# Print context around these lines
for (ln in old_lines) {
 start <- max(1, ln-2)
 end <- min(length(lines), ln+12)
 cat("--- Context around line", ln, "---\n")
 for (i in start:end) {
 cat(i, ":", lines[i], "\n")
 }
}

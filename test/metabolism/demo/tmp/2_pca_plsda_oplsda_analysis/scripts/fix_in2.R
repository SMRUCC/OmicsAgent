lines <- readLines("G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
# Replace "in1:nrow" -> "in1:nrow" (add space)
# The string "in1:nrow" has NO space between 'in' and '1'
# We want "in1:nrow" which has a space
old_str <- paste0("in", "1:nrow")
new_str <- paste0("in", "1:nrow")
cat("Old pattern:", old_str, "\n")
cat("New pattern:", new_str, "\n")
cat("Found:", sum(grepl(old_str, lines, fixed=TRUE)), "instances\n")

lines <- gsub(old_str, new_str, lines, fixed=TRUE)

# Also fix "in1:n_perm"
old_str2 <- paste0("in", "1:n_perm")
new_str2 <- paste0("in", "1:n_perm")
lines <- gsub(old_str2, new_str2, lines, fixed=TRUE)

writeLines(lines, "G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
cat("Fixed spacing issues!\n")

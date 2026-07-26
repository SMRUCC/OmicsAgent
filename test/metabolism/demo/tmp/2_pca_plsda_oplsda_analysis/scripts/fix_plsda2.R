lines <- readLines("G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")

# Fix the variance extraction section (around line145-148)
# Replace the buggy4 lines with proper code
old_lines <- grep("plsda_var <- rep", lines)
cat("Found at lines around", old_lines, "\n")

# The old code: plsda_var[1] <- mean(plsda_model$explained_variance$X[1, ])
# Replace with proper prop_expl_var extraction
target_lines <- old_lines:(old_lines+3)
cat("Old lines:\n")
for (i in target_lines) cat(i, ":", lines[i], "\n")

lines[old_lines] <- "plsda_var <- plsda_model$prop_expl_var$X"
lines[old_lines+1] <- "cat(\" Comp1 var:\", round(plsda_var[1]*100,1),"
lines[old_lines+2] <- " \"%, Comp2 var:\", round(plsda_var[2]*100,1), \"%\")"
lines[old_lines+3] <- "# Remove this line now unused"

cat("New lines:\n")
for (i in old_lines:(old_lines+3)) cat(i, ":", lines[i], "\n")

writeLines(lines, "G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
cat("Fixed.\n")

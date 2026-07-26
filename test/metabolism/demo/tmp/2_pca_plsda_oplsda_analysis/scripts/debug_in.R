lines <- readLines("G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
# Fix "in1" -> "in1" (add space)
count1 <- sum(grepl("in1:nrow", lines))
count2 <- sum(grepl("in1:n_perm", lines))
cat("Found", count1, "instances of 'in1:nrow'\n")
cat("Found", count2, "instances of 'in1:n_perm'\n")

lines <- gsub("in1:nrow", "in1:nrow", lines) # placeholder
lines <- gsub("in1:n_perm", "in1:n_perm", lines) # placeholder
# Hmm, that's still the same. Let me check the actual content.
for (i in seq_along(lines)) {
 if (grepl("in1:nrow", lines[i])) cat(i, ":", lines[i], "\n")
 if (grepl("in1:n_perm", lines[i])) cat(i, ":", lines[i], "\n")
}

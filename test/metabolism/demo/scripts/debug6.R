file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

# Count braces
open_braces <- sum(nchar(gsub("[^{]", "", lines)))
close_braces <- sum(nchar(gsub("[^}]", "", lines)))
cat("Open braces:", open_braces, "\n")
cat("Close braces:", close_braces, "\n")
cat("Balance:", open_braces - close_braces, "\n")

if (open_braces != close_braces) {
 cat("\nLooking for imbalance around OPLSDA section...\n")
 # Check around the OPLSDA section
 start_idx <-275
 end_idx <- min(340, length(lines))
 cum_balance <-0
 for (i in seq(from = start_idx, to = end_idx, by =1)) {
 line <- lines[i]
 cum_balance <- cum_balance + nchar(gsub("[^{]", "", line)) - nchar(gsub("[^}]", "", line))
 if (abs(nchar(gsub("[^{]", "", line)) - nchar(gsub("[^}]", "", line))) >0 || i %%10 ==0) {
 cat(sprintf("Line %d (bal=%+d): %s\n", i, cum_balance, substr(line,1,80)))
 }
 }
 cat("\nFinal cumulative balance at line", end_idx, ":", cum_balance, "\n")
}

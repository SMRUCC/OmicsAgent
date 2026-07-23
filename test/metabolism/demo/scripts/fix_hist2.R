file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

# Fix: insert df definition before ggplot(df, ...)
# Line409 has: p <- ggplot(df, aes(x = ratio)) +
# Change to: df <- data.frame(ratio = perm_res$permuted_ratios)
# p <- ggplot(df, aes(x = ratio)) +

# Find the exact line
target_line <- grep('p <- ggplot\\(df, aes', lines)
cat("Target line:", target_line, "\n")

if (length(target_line) >0) {
 # Replace the line
 old_line <- lines[target_line]
 lines[target_line] <- ' df <- data.frame(ratio = perm_res$permuted_ratios)'
 lines <- c(lines[1:target_line], old_line, lines[(target_line+1):length(lines)])
 cat("Fixed. Inserted df definition.\n")
}

writeLines(lines, file_path)
cat("Done.\n")

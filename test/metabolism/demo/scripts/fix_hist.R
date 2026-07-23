file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

# Find and fix plot_perm_hist function
# Find the function
func_start <- grep("plot_perm_hist <- function", lines)
cat("Function at line:", func_start, "\n")

# Show lines around it
for (i in seq(from = func_start, to = min(func_start+15, length(lines)), by =1)) {
 cat("Line", i, ":", lines[i], "\n")
}

# The issue: the function has the NA check but lost the `df <-` line
# Find where `ggplot(df, aes(x = ratio))` is
ggplot_line <- grep("ggplot\\(df, aes", lines[func_start:min(func_start+15, length(lines))]) + func_start -1
cat("ggplot line:", ggplot_line, "\n")

# The line before ggplot should define df
# Currently it has `p <- ggplot(df, aes(x = ratio)) +`
# It should have `df <- data.frame(ratio = perm_res$permuted_ratios)`

# Insert the df definition line before the ggplot line
new_line <- " df <- data.frame(ratio = perm_res$permuted_ratios)"
lines <- c(lines[1:(ggplot_line-1)], new_line, lines[ggplot_line:length(lines)])

writeLines(lines, file_path)
cat("Inserted df definition at line", ggplot_line, "\n")

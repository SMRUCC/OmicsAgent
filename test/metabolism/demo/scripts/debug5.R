file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

# Fix the histogram function - the df definition was inserted in the wrong place
# Let me find the function and check
func_start <- grep("plot_perm_hist <- function", lines)
cat("Function at line:", func_start, "\n")

for (i in seq(from = func_start, to = min(func_start+20, length(lines)), by =1)) {
 cat("Line", i, ":", lines[i], "\n")
}

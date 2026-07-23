file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

start_idx <-305
end_idx <- min(325, length(lines))
for (i in seq(from = start_idx, to = end_idx, by =1)) {
 cat("Line", i, ":", lines[i], "\n")
}

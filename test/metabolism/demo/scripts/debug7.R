file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

# Show lines284-295
for (i in seq(from =284, to = min(295, length(lines)), by =1)) {
 cat("Line", i, ":", lines[i], "\n")
}

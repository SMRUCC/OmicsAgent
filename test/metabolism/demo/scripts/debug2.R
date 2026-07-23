file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

# Find lines300 to330
for (i in300:min(330, length(lines))) {
 cat("Line", i, ":", lines[i], "\n")
}

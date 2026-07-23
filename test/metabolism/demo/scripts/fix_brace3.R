file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

# Insert } after line291 to close the else block
new_lines <- c(lines[1:291], "}", lines[292:length(lines)])
writeLines(new_lines, file_path)
cat("Inserted closing } at line292. File has", length(new_lines), "lines.\n")

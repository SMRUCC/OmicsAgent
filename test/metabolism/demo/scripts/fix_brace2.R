file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

# Show lines285-295
start_idx <-285
end_idx <-295
for (i in seq(from = start_idx, to = end_idx, by =1)) {
 cat("Line", i, ":", lines[i], "\n")
}

# Insert a } at position314 (after line313, before line314 blank)
cat("\nInserting closing brace...\n")
new_lines <- c(lines[1:313], "}", lines[314:length(lines)])
writeLines(new_lines, file_path)
cat("Done. New total lines:", length(new_lines), "\n")

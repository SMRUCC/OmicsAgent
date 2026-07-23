# Fix the saveWidget line by wrapping in tryCatch
file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_enhanced_analysis.R"
lines <- readLines(file_path, warn = FALSE)

# Find line with saveWidget and wrap it
idx <- grep("htmlwidgets::saveWidget", lines)
if (length(idx) >0) {
 for (i in rev(idx)) {
 lines[i] <- paste0("tryCatch({", lines[i], "}, error = function(e) cat('Warning: Could not save interactive3D plot:', e$message, '\\n'))")
 }
 writeLines(lines, file_path)
 cat("Fixed", length(idx), "saveWidget calls.\n")
} else {
 cat("No saveWidget calls found.\n")
}

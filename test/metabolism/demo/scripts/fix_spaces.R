file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

# Fix "in1" -> "in1" (add space after 'n' and before '1')
cat("Before fix - 'in1' patterns:\n")
hits <- grep("in1", lines)
for (h in hits) cat(" Line", h, ":", lines[h], "\n")

# Use regex: replace "(in)(1)" with "in1" (space between)
lines <- gsub("(in)(1)", "\\1 \\2", lines, perl = TRUE)

writeLines(lines, file_path)

cat("\nAfter fix:\n")
hits2 <- grep("in1", lines)
if (length(hits2) >0) {
 cat("WARNING: remaining at lines:", hits2, "\n")
 for (h in hits2) cat(" Line", h, ":", lines[h], "\n")
} else {
 cat("All 'in1' patterns fixed!\n")
}

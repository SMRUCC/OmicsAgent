# Fix "in1" -> "in1" spacing issue in for loop syntax
file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_pca_plsda_oplsda.R"
lines <- readLines(file_path, warn = FALSE)

cat("BEFORE:\n")
for (h in grep("in1", lines)) cat(" Line", h, ":", lines[h], "\n")

# Use regex with backreferences to add space
# Replace "in1" (no space) with "in1" (space) using capture groups
# Pattern: "(in)(1)" captures "in" as group1 and "1" as group2
# Replacement: "\\1 \\2" = group1 + space + group2

for (i in seq_along(lines)) {
 line <- lines[i]
 # Only modify lines that have the pattern
 if (grepl("in1", line, fixed = TRUE)) {
 new_line <- gsub("(in)(1)", "\\1 \\2", line, perl = TRUE)
 if (new_line != line) {
 lines[i] <- new_line
 cat(" Fixed line", i, ": '", line, "' -> '", new_line, "'\n", sep = "")
 }
 }
}

writeLines(lines, file_path)

cat("\nVERIFICATION:\n")
lines2 <- readLines(file_path, warn = FALSE)
hits <- grep("in1", lines2)
if (length(hits) >0) {
 cat("STILL has 'in1' patterns at lines:", hits, "\n")
 for (h in hits) {
 line <- lines2[h]
 chars <- strsplit(line, "")[[1]]
 cat(" Line", h, ": ")
 for (j in seq_along(chars)) {
 if (chars[j] == " ") cat("_", sep = "")
 else cat(chars[j])
 }
 cat("\n")
 }
} else {
 cat("All fixed! No more 'in1' patterns.\n")
}

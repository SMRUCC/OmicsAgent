library(stringi)
path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_4_limma_analysis.R"
txt <- readLines(path, warn=FALSE)
# Find and fix the problematic line
idx <- grep("for.*in1:nrow", txt)
if (length(idx) >0) {
 cat("Found problematic line:", txt[idx[1]], "\n")
 txt[idx[1]] <- gsub("in1:nrow\\(combined\\)", "in1:nrow(combined)", txt[idx[1]])
 writeLines(txt, path)
 cat("Fixed!\n")
} else {
 cat("Pattern not found. Checking for 'for (i in':\n")
 idx2 <- grep("for.*in.*nrow", txt)
 print(txt[idx2])
}

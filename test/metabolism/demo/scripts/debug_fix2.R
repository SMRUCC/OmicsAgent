path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_4_limma_analysis.R"
txt <- readLines(path, warn = FALSE)
idx <- grep("for.*nrow.*combined", txt)
if (length(idx) >0) {
 cat("Found line:", txt[idx[1]], "\n")
 cat("Char codes around 'in1':\n")
 line_chars <- strsplit(txt[idx[1]], "")[[1]]
 for (i in grep("in1", txt[idx[1]])[1]:min(grep("in1", txt[idx[1]])[1]+5, nchar(txt[idx[1]]))) {
 cat(sprintf(" pos %d: '%s' (0x%x)\n", i, substr(txt[idx[1]], i, i), utf8ToInt(substr(txt[idx[1]], i, i))))
 }
}

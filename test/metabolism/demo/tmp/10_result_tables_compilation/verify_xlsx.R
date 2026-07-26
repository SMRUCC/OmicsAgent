# Verify the generated XLSX file
library(openxlsx)

xlsx_path <- "G:/OmicsWorks/test/metabolism/demo/analysis/5_kegg_functional_analysis/5_kegg_functional_analysis.xlsx"

cat("=== Verifying XLSX: ", xlsx_path, " ===\n\n")

# Get sheet names
wb <- loadWorkbook(xlsx_path)
sheets <- names(wb)
cat("Number of sheets:", length(sheets), "\n")
cat("Sheet names:\n")
for (s in sheets) {
 cat(" - '", s, "' (", nchar(s), " chars)\n", sep = "")
}

cat("\n--- Sheet details ---\n")
for (s in sheets) {
 cat("\n[", s, "]\n", sep = "")
 
 # Read the data
 df <- readWorkbook(wb, sheet = s, startRow =3, colNames = FALSE)
 cat(" Data rows:", nrow(df), ", cols:", ncol(df), "\n")
 
 # Read header
 hdr <- readWorkbook(wb, sheet = s, startRow =2, rows =2, colNames = FALSE)
 cat(" Headers:", paste(unlist(hdr[1,]), collapse = ", "), "\n")
 
 # Read annotation
 ann <- readWorkbook(wb, sheet = s, startRow =1, rows =1, colNames = FALSE)
 ann_text <- as.character(ann[1,1])
 cat(" Annotation (first80 chars):", substr(ann_text,1,80), "...\n")
}

cat("\n=== Verification complete ===\n")

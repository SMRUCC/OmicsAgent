################################################################################
# Module4: LIMMA Differential Analysis - Results Compilation
# Generate a structured, styled XLSX workbook from CSV result tables
# using openxlsx and jsonlite.
#
# Input JSON: G:/OmicsWorks/test/metabolism/demo/analysis/4_limma_differential_analysis/table_descriptions.json
# Output XLSX: G:/OmicsWorks/test/metabolism/demo/analysis/4_limma_differential_analysis/4_limma_differential_analysis.xlsx
################################################################################

# ----1. Load / Install Required Packages ----
if (!require(openxlsx)) install.packages('openxlsx', quiet = TRUE)
if (!require(jsonlite)) install.packages('jsonlite', quiet = TRUE)
library(openxlsx)
library(jsonlite)

cat("============================================================\n")
cat("Module4: LIMMA Differential Analysis - Results Compilation\n")
cat("============================================================\n\n")

# ----2. Paths ----
json_path <- "G:/OmicsWorks/test/metabolism/demo/analysis/4_limma_differential_analysis/table_descriptions.json"
out_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis/4_limma_differential_analysis"
xlsx_name <- "4_limma_differential_analysis.xlsx"
xlsx_path <- file.path(out_dir, xlsx_name)

# ----3. Read JSON Description ----
cat("Reading JSON: ", json_path, "\n")
if (!file.exists(json_path)) {
 stop("JSON file not found: ", json_path)
}

# The JSON file uses unescaped backslashes in paths (invalid JSON).
# Read raw text, convert all backslashes to forward slashes, then parse.
json_text <- readLines(json_path, warn = FALSE, encoding = "UTF-8")
json_text <- paste(json_text, collapse = "\n")
# Replace backslash with forward slash in path values
json_text <- gsub("\\\\", "/", json_text)

desc <- fromJSON(json_text, simplifyVector = FALSE)

cat("Module name: ", desc$module_name, "\n")
cat("Sheets count: ", length(desc$sheets), "\n\n")

# ----4. Create Workbook ----
wb <- createWorkbook()

# ----5. Define Styles (all use 'Cambria Math', size11) ----
font_name <- "Cambria Math"
font_size <-11

# defaultStyle: Cambria Math11, white background
defaultStyle <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 fgFill = "#FFFFFF",
 halign = "left",
 valign = "top",
 wrapText = TRUE
)

# annotStyle: forest green (#228B22) font
annotStyle <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 fontColour = "#228B22",
 halign = "left",
 valign = "top",
 wrapText = TRUE
)

# headerStyle: deep blue (#1F4E79) background, white (#FFFFFF) bold font
headerStyle <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 fontColour = "#FFFFFF",
 fgFill = "#1F4E79",
 textDecoration = "bold",
 halign = "center",
 valign = "center",
 wrapText = TRUE
)

# idStyle: light gray (#D9D9D9) background, italic, black (#000000) font
idStyle <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 fgFill = "#D9D9D9",
 fontColour = "#000000",
 textDecoration = "italic",
 halign = "left",
 valign = "top",
 wrapText = TRUE
)

# ----6. Process Each Sheet ----
n_sheets <- length(desc$sheets)
sheets_ok <-0
sheets_skip <-0

for (i in seq_len(n_sheets)) {
 sh <- desc$sheets[[i]]
 csv_path <- sh$csv
 sheet_raw <- sh$sheet_name
 annotation <- if (is.null(sh$annotation)) "" else sh$annotation

 cat(sprintf(" [%02d/%02d] Processing: %s\n", i, n_sheets, basename(csv_path)))

 # ---6a. Check CSV file ---
 if (is.null(csv_path) || !file.exists(csv_path)) {
 warning(sprintf("[SKIP] CSV file not found: %s", csv_path))
 sheets_skip <- sheets_skip +1
 next
 }

 # ---6b. Read CSV (preserve column names exactly) ---
 df <- tryCatch(
 read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE),
 error = function(e) {
 warning(sprintf("[SKIP] Failed to read CSV: %s - %s", csv_path, conditionMessage(e)))
 return(NULL)
 }
 )
 if (is.null(df) || nrow(df) ==0 || ncol(df) ==0) {
 warning(sprintf("[SKIP] Empty CSV: %s", csv_path))
 sheets_skip <- sheets_skip +1
 next
 }

 nrow_df <- nrow(df)
 ncol_df <- ncol(df)

 # ---6c. Sanitize sheet name (<=31 chars, no [ ] : \\ / ? *) ---
 sheet_name <- sheet_raw
 sheet_name <- gsub("[\\[\\]:\\\\/\\?\\*]", "_", sheet_name)
 sheet_name <- substr(sheet_name,1,31)

 # ---6d. Add worksheet (with zoom=90) ---
 addWorksheet(wb, sheetName = sheet_name, zoom =90)

 # ---6e. Write annotation (row1, col1) ---
 writeData(wb, sheet = sheet_name,
 x = annotation,
 startRow =1, startCol =1,
 colNames = FALSE, rowNames = FALSE)

 # ---6f. Write column headers (row2) ---
 header_row <- as.data.frame(t(colnames(df)),
 stringsAsFactors = FALSE,
 check.names = FALSE)
 writeData(wb, sheet = sheet_name,
 x = header_row,
 startRow =2, startCol =1,
 colNames = FALSE, rowNames = FALSE)

 # ---6g. Write data (starting row3) ---
 writeData(wb, sheet = sheet_name,
 x = df,
 startRow =3, startCol =1,
 colNames = FALSE, rowNames = FALSE)

 # ---6h. Apply styles ---
 last_data_row <- nrow_df +2

 #1) defaultStyle: entire used area
 addStyle(wb, sheet = sheet_name,
 style = defaultStyle,
 rows =1:last_data_row, cols =1:ncol_df,
 gridExpand = TRUE, stack = FALSE)

 #2) annotStyle: row1, all columns
 addStyle(wb, sheet = sheet_name,
 style = annotStyle,
 rows =1, cols =1:ncol_df,
 gridExpand = TRUE, stack = FALSE)

 #3) headerStyle: row2, all columns
 addStyle(wb, sheet = sheet_name,
 style = headerStyle,
 rows =2, cols =1:ncol_df,
 gridExpand = TRUE, stack = FALSE)

 #4) idStyle: column1 (A), rows3 to last_data_row
 if (nrow_df >=1) {
 addStyle(wb, sheet = sheet_name,
 style = idStyle,
 rows =3:last_data_row, cols =1,
 gridExpand = TRUE, stack = FALSE)
 }

 # ---6i. Freeze pane at B3 ---
 # firstActiveRow=3 and firstActiveCol=2 freezes first2 rows and first column
 freezePane(wb, sheet = sheet_name,
 firstActiveRow =3, firstActiveCol =2)

 cat(sprintf(" -> Written: %d rows x %d cols\n", nrow_df, ncol_df))
 sheets_ok <- sheets_ok +1
}

# ----7. Save Workbook ----
cat("\n------------------------------------------------------------\n")
cat(sprintf("Sheets processed: %d\n", sheets_ok))
if (sheets_skip >0) {
 cat(sprintf("Sheets skipped (missing/empty): %d\n", sheets_skip))
}
cat("Saving workbook: ", xlsx_path, "\n")

saveWorkbook(wb, file = xlsx_path, overwrite = TRUE)

# ----8. Verify Output ----
if (file.exists(xlsx_path)) {
 file_size <- file.info(xlsx_path)$size
 cat(sprintf("SUCCESS: %s generated (%.2f KB)\n", xlsx_name, file_size /1024))
} else {
 stop("FAILED: XLSX file was not created.")
}

cat("============================================================\n")
cat("Module4 compilation complete.\n")
cat("============================================================\n")

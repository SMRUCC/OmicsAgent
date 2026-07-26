# ==============================================================================
# Module7: CMeans Fuzzy Clustering Analysis - Results Compilation
# ==============================================================================
# This script reads CSV result tables and compiles them into a structured,
# styled XLSX workbook using openxlsx.
#
# JSON Input: table_descriptions.json (contains sheet metadata)
# CSV Input: Multiple CSV files (one per worksheet)
# Output:7_cmeans_fuzzy_clustering_analysis.xlsx
#
# Dependencies: openxlsx, jsonlite
# ==============================================================================

# ----1. Load and install required packages ----
if (!require(openxlsx)) install.packages('openxlsx')
if (!require(jsonlite)) install.packages('jsonlite')
library(openxlsx)
library(jsonlite)

cat("============================================================\n")
cat("Module7: CMeans Fuzzy Clustering Analysis\n")
cat("Compiling XLSX from CSV result tables\n")
cat("============================================================\n\n")

# ----2. Configuration ----
json_path <- "G:/OmicsWorks/test/metabolism/demo/analysis/7_cmeans_fuzzy_clustering_analysis/table_descriptions.json"
output_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis/7_cmeans_fuzzy_clustering_analysis"
xlsx_name <- "7_cmeans_fuzzy_clustering_analysis.xlsx"
xlsx_path <- file.path(output_dir, xlsx_name)

FONT_NAME <- "Cambria Math"
FONT_SIZE <-11
ZOOM_PCT <-90

# ----3. Read JSON description ----
if (!file.exists(json_path)) {
 stop("JSON description file not found: ", json_path)
}

cat("Reading JSON description:", json_path, "\n")
desc <- jsonlite::fromJSON(json_path, simplifyVector = FALSE)

cat("Module name:", desc$module_name, "\n")
cat("Number of sheets:", length(desc$sheets), "\n\n")

# ----4. Create styles ----
# Default style: Cambria Math11, white background
default_style <- createStyle(
 fontName = FONT_NAME,
 fontSize = FONT_SIZE,
 fontColour = "#000000",
 fgFill = "#FFFFFF",
 halign = "left",
 valign = "top",
 wrapText = TRUE
)

# Annotation style: green font #228B22, default background
annot_style <- createStyle(
 fontName = FONT_NAME,
 fontSize = FONT_SIZE,
 fontColour = "#228B22",
 halign = "left",
 valign = "top",
 wrapText = TRUE
)

# Header style: dark blue background #1F4E79, white font #FFFFFF, bold
header_style <- createStyle(
 fontName = FONT_NAME,
 fontSize = FONT_SIZE,
 fontColour = "#FFFFFF",
 fgFill = "#1F4E79",
 textDecoration = "bold",
 halign = "center",
 valign = "center",
 wrapText = TRUE
)

# ID column style: light gray background #D9D9D9, italic, black font #000000
id_style <- createStyle(
 fontName = FONT_NAME,
 fontSize = FONT_SIZE,
 fontColour = "#000000",
 fgFill = "#D9D9D9",
 textDecoration = "italic",
 halign = "left",
 valign = "top",
 wrapText = TRUE
)

# ----5. Create workbook ----
wb <- createWorkbook()

# ----6. Helper function to sanitize sheet names ----
sanitize_sheet_name <- function(raw_name, max_length =31L) {
 if (is.null(raw_name) || is.na(raw_name) || nchar(raw_name) ==0) {
 return("Sheet1")
 }
 # Replace illegal Excel sheet name characters: : \\ / ? * [ ]
 cleaned <- gsub("[:\\\\/\\?\\*\\[\\]]", "_", raw_name)
 cleaned <- substr(cleaned,1, max_length)
 cleaned
}

# ----7. Process each sheet ----
sheets_processed <-0L
sheets_skipped <-0L
n_sheets <- length(desc$sheets)

for (i in seq_len(n_sheets)) {
 sh <- desc$sheets[[i]]
 csv_path <- sh$csv
 sheet_name <- sh$sheet_name
 annotation <- if (is.null(sh$annotation)) "" else sh$annotation
 
 cat(sprintf(" [%02d/%02d] Processing: %s\n", i, n_sheets, basename(csv_path)))
 
 # ----7a. Check CSV file existence ----
 if (is.null(csv_path) || !file.exists(csv_path)) {
 warning(sprintf(" [SKIP] CSV file not found: %s", csv_path))
 sheets_skipped <- sheets_skipped +1L
 next
 }
 
 # ----7b. Read CSV ----
 df <- tryCatch(
 read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE),
 error = function(e) {
 warning(sprintf(" [SKIP] Failed to read CSV: %s - %s", csv_path, conditionMessage(e)))
 return(NULL)
 }
 )
 
 if (is.null(df) || nrow(df) ==0 || ncol(df) ==0) {
 warning(sprintf(" [SKIP] CSV is empty or has no data: %s", csv_path))
 sheets_skipped <- sheets_skipped +1L
 next
 }
 
 # ----7c. Sanitize sheet name and add worksheet (with zoom) ----
 clean_name <- sanitize_sheet_name(sheet_name)
 addWorksheet(wb, sheetName = clean_name, zoom = ZOOM_PCT)
 
 ncol_df <- ncol(df)
 nrow_df <- nrow(df)
 last_data_row <- nrow_df +2 # row1 = annotation, row2 = headers, row3+ = data
 
 # ----7d. Write annotation (row1, cell A1) ----
 writeData(
 wb, sheet = clean_name,
 x = annotation,
 startRow =1, startCol =1,
 colNames = FALSE, rowNames = FALSE
 )
 
 # Merge annotation cell across all columns for clean appearance
 if (ncol_df >1 && nchar(annotation) >0) {
 mergeCells(wb, sheet = clean_name, cols =1:ncol_df, rows =1)
 }
 
 # ----7e. Write column headers (row2) ----
 header_df <- as.data.frame(t(colnames(df)), stringsAsFactors = FALSE,
 check.names = FALSE)
 writeData(
 wb, sheet = clean_name,
 x = header_df,
 startRow =2, startCol =1,
 colNames = FALSE, rowNames = FALSE
 )
 
 # ----7f. Write data (from row3) ----
 writeData(
 wb, sheet = clean_name,
 x = df,
 startRow =3, startCol =1,
 colNames = FALSE, rowNames = FALSE
 )
 
 # ----7g. Apply styles (order matters: default first, then specific) ----
 #1) Default style: entire used range
 addStyle(
 wb, sheet = clean_name,
 style = default_style,
 rows =1:last_data_row,
 cols =1:ncol_df,
 gridExpand = TRUE,
 stack = FALSE
 )
 
 #2) Annotation style: row1, all columns
 addStyle(
 wb, sheet = clean_name,
 style = annot_style,
 rows =1,
 cols =1:ncol_df,
 gridExpand = TRUE,
 stack = FALSE
 )
 
 #3) Header style: row2, all columns
 addStyle(
 wb, sheet = clean_name,
 style = header_style,
 rows =2,
 cols =1:ncol_df,
 gridExpand = TRUE,
 stack = FALSE
 )
 
 #4) ID column style: column A (col1), rows3 to last data row
 if (nrow_df >=1) {
 addStyle(
 wb, sheet = clean_name,
 style = id_style,
 rows =3:last_data_row,
 cols =1,
 gridExpand = TRUE,
 stack = FALSE
 )
 }
 
 # ----7h. Freeze panes: firstRow=3, firstCol=2 ----
 # Freezes rows1-2 and column A; B3 is the first active cell
 freezePane(wb, sheet = clean_name, firstActiveRow =3, firstActiveCol =2)
 
 cat(sprintf(" -> Written: %d rows x %d cols\n", nrow_df, ncol_df))
 sheets_processed <- sheets_processed +1L
}

# ----8. Save workbook ----
cat("\n============================================================\n")
cat(sprintf("Sheets processed: %d\n", sheets_processed))
if (sheets_skipped >0) {
 cat(sprintf("Sheets skipped (missing/empty): %d\n", sheets_skipped))
}
cat(sprintf("Saving workbook: %s\n", xlsx_path))

saveWorkbook(wb, file = xlsx_path, overwrite = TRUE)

# ----9. Verification ----
if (file.exists(xlsx_path)) {
 file_size <- file.info(xlsx_path)$size
 cat(sprintf("SUCCESS: %s generated (%.2f KB)\n", xlsx_name, file_size /1024))
} else {
 stop("FAILURE: XLSX file was not created.")
}

cat("============================================================\n")
cat("Module7 compilation complete.\n")
cat("============================================================\n")

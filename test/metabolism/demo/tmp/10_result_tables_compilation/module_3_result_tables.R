################################################################################
# Module3: Comparison Group Design — Results Compilation
# Generates a structured, styled XLSX file from CSV result tables.
################################################################################

# ----1. Load required packages ----
if (!require(openxlsx)) install.packages('openxlsx', quiet = TRUE)
if (!require(jsonlite)) install.packages('jsonlite', quiet = TRUE)
library(openxlsx)
library(jsonlite)

cat("============================================================\n")
cat("Module3: Comparison Group Design - Results Compilation\n")
cat("============================================================\n\n")

# ----2. Path configuration ----
json_path <- "G:/OmicsWorks/test/metabolism/demo/analysis/3_comparison_group_design/table_descriptions.json"
output_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis/3_comparison_group_design"
xlsx_name <- "3_comparison_group_design.xlsx"
xlsx_path <- file.path(output_dir, xlsx_name)

# ----3. Read JSON description ----
cat(sprintf("Reading JSON description: %s\n", json_path))

if (!file.exists(json_path)) {
 stop("JSON description file not found: ", json_path)
}

# Read raw JSON text and normalize backslashes to forward slashes
# (the JSON file may contain Windows backslash paths which are invalid JSON)
json_text <- readLines(json_path, warn = FALSE, encoding = "UTF-8")
json_text <- paste(json_text, collapse = "\n")
# Replace backslashes with forward slashes to make JSON valid
json_text <- gsub("\\\\", "/", json_text)

# Parse the cleaned JSON
desc <- jsonlite::fromJSON(json_text, simplifyVector = FALSE)

cat(sprintf("Module Index : %d\n", desc$module_index))
cat(sprintf("Module Name : %s\n", desc$module_name))
cat(sprintf("XLSX File : %s\n", desc$xlsx_file))
cat(sprintf("Number of sheets: %d\n\n", length(desc$sheets)))

# ----4. Create new workbook ----
wb <- createWorkbook()
cat("Workbook created.\n\n")

# ----5. Define styles ----
# All using 'Cambria Math' font, size11

default_style <- createStyle(
 fontName = "Cambria Math",
 fontSize =11,
 fgFill = "#FFFFFF", # white background
 valign = "top",
 halign = "left",
 wrapText = TRUE
)

annot_style <- createStyle(
 fontName = "Cambria Math",
 fontSize =11,
 fontColour = "#228B22", # forest green
 valign = "top",
 halign = "left",
 wrapText = TRUE
)

header_style <- createStyle(
 fontName = "Cambria Math",
 fontSize =11,
 fontColour = "#FFFFFF", # white
 fgFill = "#1F4E79", # deep blue
 textDecoration = "bold",
 valign = "center",
 halign = "center",
 wrapText = TRUE
)

id_style <- createStyle(
 fontName = "Cambria Math",
 fontSize =11,
 fontColour = "#000000", # black
 fgFill = "#D9D9D9", # light gray
 textDecoration = "italic",
 valign = "top",
 halign = "left",
 wrapText = TRUE
)

cat("Styles defined (Cambria Math,11 pt).\n\n")

# ----6. Helper: sanitize sheet name ----
sanitize_sheet_name <- function(raw_name, max_length =31L) {
 if (is.null(raw_name) || is.na(raw_name) || nchar(raw_name) ==0) {
 return("Sheet1")
 }
 # Replace illegal Excel characters: : \\ / ? * [ ]
 cleaned <- gsub("[:\\\\/\\?\\*\\[\\]]", "_", raw_name)
 # Truncate to max length
 cleaned <- substr(cleaned,1, max_length)
 cleaned
}

# ----7. Process each sheet ----
sheets_processed <-0L
sheets_skipped <-0L
n_sheets <- length(desc$sheets)

for (j in seq_len(n_sheets)) {
 sh <- desc$sheets[[j]]
  
 # Normalize CSV path: replace any remaining backslashes with forward slashes
 csv_path <- sh$csv
 csv_path <- gsub("\\\\", "/", csv_path)
  
 raw_sheet <- sh$sheet_name
 annotation <- if (is.null(sh$annotation)) "" else sh$annotation
  
 cat(sprintf(" [%02d/%02d] Processing: %s\n", j, n_sheets, basename(csv_path)))
  
 # ----7a. Check CSV file existence ----
 if (is.null(csv_path) || !file.exists(csv_path)) {
 warning(sprintf("[SKIP] CSV file not found: %s", csv_path))
 sheets_skipped <- sheets_skipped +1L
 next
 }
  
 # ----7b. Read CSV ----
 df <- tryCatch(
 read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE),
 error = function(e) {
 warning(sprintf("[SKIP] CSV read failed: %s - %s", csv_path, conditionMessage(e)))
 return(NULL)
 }
 )
  
 if (is.null(df) || nrow(df) ==0 || ncol(df) ==0) {
 warning(sprintf("[SKIP] CSV is empty or has no data: %s", csv_path))
 sheets_skipped <- sheets_skipped +1L
 next
 }
  
 ncol_df <- ncol(df)
 nrow_df <- nrow(df)
 last_col <- ncol_df
 last_data_row <- nrow_df +2 # row1 = annotation, row2 = header, row3+ = data
  
 # ----7c. Sanitize sheet name and add worksheet ----
 clean_sheet <- sanitize_sheet_name(raw_sheet)
 # Set zoom via addWorksheet parameter (more compatible across versions)
 addWorksheet(wb, sheetName = clean_sheet, zoom =90)
  
 cat(sprintf(" Sheet: '%s' (%d rows, %d cols)\n", clean_sheet, nrow_df, ncol_df))
  
 # ----7d. Write annotation to row1, column1 ----
 writeData(wb, sheet = clean_sheet,
 x = annotation,
 startRow =1, startCol =1,
 colNames = FALSE, rowNames = FALSE)
  
 # ----7e. Write column headers to row2 ----
 header_df <- as.data.frame(t(colnames(df)),
 stringsAsFactors = FALSE,
 check.names = FALSE)
 writeData(wb, sheet = clean_sheet,
 x = header_df,
 startRow =2, startCol =1,
 colNames = FALSE, rowNames = FALSE)
  
 # ----7f. Write data from row3 ----
 writeData(wb, sheet = clean_sheet,
 x = df,
 startRow =3, startCol =1,
 colNames = FALSE, rowNames = FALSE)
  
 # ----7g. Apply styles (default first, then overlay specific styles) ----
 #1) defaultStyle: entire used range
 addStyle(wb, sheet = clean_sheet,
 style = default_style,
 rows =1:last_data_row,
 cols =1:ncol_df,
 gridExpand = TRUE, stack = FALSE)
  
 #2) annotStyle: row1, all used columns
 addStyle(wb, sheet = clean_sheet,
 style = annot_style,
 rows =1,
 cols =1:ncol_df,
 gridExpand = TRUE, stack = FALSE)
  
 #3) headerStyle: row2, all used columns
 addStyle(wb, sheet = clean_sheet,
 style = header_style,
 rows =2,
 cols =1:ncol_df,
 gridExpand = TRUE, stack = FALSE)
  
 #4) idStyle: column A, rows3 to last data row
 if (nrow_df >=1) {
 addStyle(wb, sheet = clean_sheet,
 style = id_style,
 rows =3:last_data_row,
 cols =1,
 gridExpand = TRUE, stack = FALSE)
 }
  
 # ----7h. Freeze pane: B3 (freeze first2 rows and first column) ----
 # In openxlsx, freezePane uses firstActiveRow and firstActiveCol
 # to specify the top-left visible cell after freezing.
 # Setting firstActiveRow=3, firstActiveCol=2 means B3 is the
 # top-left visible cell, effectively freezing rows1-2 and column A.
 freezePane(wb, sheet = clean_sheet,
 firstActiveRow =3, firstActiveCol =2)
  
 # ----7i. Auto-adjust column widths ----
 col_widths <- vapply(seq_len(ncol_df), function(k) {
 header_len <- nchar(as.character(colnames(df)[k]))
 if (nrow_df >0) {
 cell_lens <- vapply(df[[k]], function(v) {
 s <- tryCatch(as.character(v), error = function(e) "")
 lines <- unlist(strsplit(s, "\n", fixed = TRUE))
 max(nchar(lines),0)
 }, numeric(1))
 data_len <- max(cell_lens,0)
 } else {
 data_len <-0
 }
 w <- max(header_len, data_len) +3
 min(max(w,10),60)
 }, numeric(1))
  
 setColWidths(wb, sheet = clean_sheet,
 cols = seq_len(ncol_df), widths = col_widths)
  
 sheets_processed <- sheets_processed +1L
 cat(sprintf(" -> Written: %d rows x %d cols\n", nrow_df, ncol_df))
}

# ----8. Save workbook ----
cat("\n============================================================\n")
cat(sprintf("Sheets processed: %d\n", sheets_processed))
if (sheets_skipped >0) {
 cat(sprintf("Sheets skipped (missing/empty): %d\n", sheets_skipped))
}
cat(sprintf("Saving workbook to: %s\n", xlsx_path))

saveWorkbook(wb, file = xlsx_path, overwrite = TRUE)

# ----9. Verify output ----
if (file.exists(xlsx_path)) {
 file_size <- file.info(xlsx_path)$size
 cat(sprintf("SUCCESS: %s generated (%.2f KB)\n", xlsx_name, file_size /1024))
} else {
 stop("FAILED: XLSX file was not generated.")
}

cat("============================================================\n")
cat("Module3 compilation complete.\n")
cat("============================================================\n")

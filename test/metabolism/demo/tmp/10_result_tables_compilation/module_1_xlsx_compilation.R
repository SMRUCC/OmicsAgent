# ============================================================================
# Module1: Expression Matrix Preprocessing - Results Compilation to XLSX
# ============================================================================
# Description:
# Reads CSV results from the Expression Matrix Preprocessing module and
# compiles them into a single structured XLSX file with professional
# formatting (styled header, annotation row, ID column, frozen panes, etc.)
#
# Input:
# JSON: G:/OmicsWorks/test/metabolism/demo/analysis/1_expression_matrix_preprocessing/table_descriptions.json
# Output:
# G:/OmicsWorks/test/metabolism/demo/analysis/1_expression_matrix_preprocessing/1_expression_matrix_preprocessing.xlsx
# ============================================================================

# ----1. Load / Install Required Packages ----
if (!require(openxlsx)) install.packages('openxlsx', quiet = TRUE)
if (!require(jsonlite)) install.packages('jsonlite', quiet = TRUE)
library(openxlsx)
library(jsonlite)

cat("============================================================\n")
cat("Module1: Expression Matrix Preprocessing - XLSX Compilation\n")
cat("============================================================\n\n")

# ----2. Define File Paths ----
json_path <- "G:/OmicsWorks/test/metabolism/demo/analysis/1_expression_matrix_preprocessing/table_descriptions.json"
out_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis/1_expression_matrix_preprocessing"
xlsx_name <- "1_expression_matrix_preprocessing.xlsx"
xlsx_path <- file.path(out_dir, xlsx_name)

cat("JSON descriptor :", json_path, "\n")
cat("Output XLSX :", xlsx_path, "\n\n")

# ----3. Read JSON Descriptor ----
if (!file.exists(json_path)) {
 stop("[FATAL] JSON descriptor not found: ", json_path)
}

desc <- jsonlite::fromJSON(json_path, simplifyVector = FALSE)
cat("Module name :", desc$module_name, "\n")
cat("Number of sheets:", length(desc$sheets), "\n\n")

# ----4. Define Styles ----
# All use 'Cambria Math', size11

# Default style: Cambria Math11, white background (no fill), basic format
default_style <- openxlsx::createStyle(
 fontName = "Cambria Math",
 fontSize =11,
 fontColour = "#000000",
 fgFill = "#FFFFFF",
 valign = "top",
 halign = "left",
 wrapText = TRUE
)

# Annotation style: green font '#228B22', default background
annot_style <- openxlsx::createStyle(
 fontName = "Cambria Math",
 fontSize =11,
 fontColour = "#228B22",
 valign = "top",
 halign = "left",
 wrapText = TRUE
)

# Header style: dark blue background '#1F4E79', white font '#FFFFFF', bold
header_style <- openxlsx::createStyle(
 fontName = "Cambria Math",
 fontSize =11,
 fontColour = "#FFFFFF",
 fgFill = "#1F4E79",
 textDecoration = "bold",
 valign = "center",
 halign = "center",
 wrapText = TRUE
)

# ID column style: light gray background '#D9D9D9', italic, black font '#000000'
id_style <- openxlsx::createStyle(
 fontName = "Cambria Math",
 fontSize =11,
 fontColour = "#000000",
 fgFill = "#D9D9D9",
 textDecoration = "italic",
 valign = "top",
 halign = "left",
 wrapText = TRUE
)

# ----5. Sanitize Sheet Name Function ----
sanitize_sheet_name <- function(raw_name, max_length =31L) {
 if (is.null(raw_name) || is.na(raw_name) || nchar(raw_name) ==0) {
 return("Sheet1")
 }
 # Replace illegal characters: : \ / ? * [ ]
 cleaned <- gsub("[:\\\\/\\?\\*\\[\\]]", "_", raw_name)
 # Truncate to max length
 cleaned <- substr(cleaned,1, max_length)
 cleaned
}

# ----6. Create Workbook ----
wb <- openxlsx::createWorkbook()

sheets_processed <-0L
sheets_skipped <-0L
n_sheets <- length(desc$sheets)

# ----7. Process Each Sheet ----
for (j in seq_len(n_sheets)) {
 sh <- desc$sheets[[j]]
 csv_path <- sh$csv
 sheet_name_raw <- sh$sheet_name
 annotation_text <- if (is.null(sh$annotation) || is.na(sh$annotation)) "" else sh$annotation
  
 cat(sprintf(" [%02d/%02d] Processing: %s\n", j, n_sheets, basename(csv_path)))
  
 # ----7a. Check CSV file exists ----
 if (is.null(csv_path) || !file.exists(csv_path)) {
 warning(sprintf(" [SKIP] CSV file not found: %s", csv_path))
 sheets_skipped <- sheets_skipped +1L
 next
 }
  
 # ----7b. Read CSV ----
 df <- tryCatch(
 read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE),
 error = function(e) {
 warning(sprintf(" [SKIP] Failed to read CSV: %s — %s", csv_path, conditionMessage(e)))
 return(NULL)
 }
 )
 if (is.null(df) || nrow(df) ==0 || ncol(df) ==0) {
 warning(sprintf(" [SKIP] CSV is empty or has no data: %s", csv_path))
 sheets_skipped <- sheets_skipped +1L
 next
 }
  
 # ----7c. Sanitize sheet name ----
 clean_sheet <- sanitize_sheet_name(sheet_name_raw)
  
 # ----7d. Add worksheet with zoom=90 ----
 openxlsx::addWorksheet(wb, sheetName = clean_sheet, zoom =90)
 cat(sprintf(" Sheet name: '%s'\n", clean_sheet))
  
 ncol_df <- ncol(df)
 nrow_df <- nrow(df)
 last_data_row <- nrow_df +2 # row1 = annotation, row2 = header, row3+ = data
  
 # ----7e. Write Annotation (Row1, Column A1) ----
 openxlsx::writeData(
 wb, sheet = clean_sheet,
 x = annotation_text,
 startRow =1, startCol =1,
 colNames = FALSE, rowNames = FALSE
 )
  
 # ----7f. Write Column Headers (Row2) ----
 header_df <- as.data.frame(
 t(colnames(df)),
 stringsAsFactors = FALSE,
 check.names = FALSE
 )
 openxlsx::writeData(
 wb, sheet = clean_sheet,
 x = header_df,
 startRow =2, startCol =1,
 colNames = FALSE, rowNames = FALSE
 )
  
 # ----7g. Write Data (from Row3) ----
 openxlsx::writeData(
 wb, sheet = clean_sheet,
 x = df,
 startRow =3, startCol =1,
 colNames = FALSE, rowNames = FALSE
 )
  
 # ----7h. Apply Styles (order matters: default first, then override) ----
  
 #1) Default style to entire used range
 openxlsx::addStyle(
 wb, sheet = clean_sheet,
 style = default_style,
 rows =1:last_data_row,
 cols =1:ncol_df,
 gridExpand = TRUE, stack = FALSE
 )
  
 #2) Annotation style to Row1 (all used columns)
 openxlsx::addStyle(
 wb, sheet = clean_sheet,
 style = annot_style,
 rows =1,
 cols =1:ncol_df,
 gridExpand = TRUE, stack = FALSE
 )
  
 #3) Header style to Row2 (all used columns)
 openxlsx::addStyle(
 wb, sheet = clean_sheet,
 style = header_style,
 rows =2,
 cols =1:ncol_df,
 gridExpand = TRUE, stack = FALSE
 )
  
 #4) ID column style to Column A, Rows3 to last data row
 if (nrow_df >=1) {
 openxlsx::addStyle(
 wb, sheet = clean_sheet,
 style = id_style,
 rows =3:last_data_row,
 cols =1,
 gridExpand = TRUE, stack = FALSE
 )
 }
  
 # ----7i. Freeze Panes: B3 (firstActiveRow=3, firstActiveCol=2) ----
 openxlsx::freezePane(wb, sheet = clean_sheet,
 firstActiveRow =3, firstActiveCol =2)
  
 cat(sprintf(" Written: %d rows x %d columns\n", nrow_df, ncol_df))
 sheets_processed <- sheets_processed +1L
}

# ----8. Save Workbook ----
cat("\n============================================================\n")
cat(sprintf("Sheets processed: %d\n", sheets_processed))
if (sheets_skipped >0) {
 cat(sprintf("Sheets skipped (missing/empty): %d\n", sheets_skipped))
}
cat("Saving workbook to:", xlsx_path, "\n")

# Ensure output directory exists
if (!dir.exists(out_dir)) {
 dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
}

openxlsx::saveWorkbook(wb, file = xlsx_path, overwrite = TRUE)

# ----9. Verify Output ----
if (file.exists(xlsx_path)) {
 file_size_kb <- file.info(xlsx_path)$size /1024
 cat(sprintf("SUCCESS: %s generated successfully (%.2f KB)\n",
 xlsx_name, file_size_kb))
} else {
 stop("[FATAL] XLSX file was not generated at: ", xlsx_path)
}

cat("============================================================\n")
cat("Module1 XLSX compilation complete.\n")
cat("============================================================\n")

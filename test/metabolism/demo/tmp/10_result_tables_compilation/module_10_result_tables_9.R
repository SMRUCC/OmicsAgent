# =============================================================================
# Module9: PLS-PM Causal Path Analysis - Results Compilation
# Generates a styled XLSX workbook from CSV result tables
# =============================================================================

# ----1. Load required packages ----
if (!require(openxlsx)) install.packages('openxlsx')
if (!require(jsonlite)) install.packages('jsonlite')
library(openxlsx)
library(jsonlite)

cat("============================================================\n")
cat("Module9: PLS-PM Causal Path Analysis - Results Compilation\n")
cat("============================================================\n\n")

# ----2. Configuration ----
json_path <- "G:/OmicsWorks/test/metabolism/demo/analysis/9_pls_pm_causal_path_analysis/table_descriptions.json"
output_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis/9_pls_pm_causal_path_analysis"
xlsx_name <- "9_pls_pm_causal_path_analysis.xlsx"

# ----3. Read JSON description ----
cat("Reading JSON description file:", json_path, "\n")
if (!file.exists(json_path)) {
 stop("JSON description file not found: ", json_path)
}

# Read raw JSON text and fix backslashes (invalid JSON escape sequences)
json_text <- readLines(json_path, warn = FALSE)
json_text <- paste(json_text, collapse = "\n")
# Replace single backslashes with forward slashes
json_text <- gsub("\\\\", "/", json_text)

desc <- jsonlite::fromJSON(json_text, simplifyVector = TRUE)

cat("Module name:", desc$module_name, "\n")
cat("XLSX file:", desc$xlsx_file, "\n")
cat("Number of sheets:", nrow(desc$sheets), "\n\n")

# ----4. Create output directory if needed ----
if (!dir.exists(output_dir)) {
 dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
 cat("Created output directory:", output_dir, "\n")
}

# ----5. Define styles ----
font_name <- "Cambria Math"
font_size <-11

# Default style: Cambria Math11, default white background
default_style <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 fgFill = "#FFFFFF"
)

# Annotation style: default background, forest green font '#228B22'
annot_style <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 fontColour = "#228B22"
)

# Header style: deep blue background '#1F4E79', white font '#FFFFFF', bold
header_style <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 fgFill = "#1F4E79",
 fontColour = "#FFFFFF",
 textDecoration = "bold"
)

# ID style: light gray background '#D9D9D9', italic, black font '#000000'
id_style <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 fgFill = "#D9D9D9",
 textDecoration = "italic",
 fontColour = "#000000"
)

# ----6. Create workbook ----
wb <- createWorkbook()

# ----7. Process each sheet ----
sheets_processed <-0L
sheets_skipped <-0L
total_sheets <- nrow(desc$sheets)

for (j in seq_len(total_sheets)) {
 sh_csv <- desc$sheets$csv[j]
 sh_sheet_name <- desc$sheets$sheet_name[j]
 sh_annotation <- desc$sheets$annotation[j]
  
 cat(sprintf(" [%02d/%02d] Processing: %s\n", j, total_sheets, basename(sh_csv)))
  
 # ----7a. Check CSV file existence ----
 if (is.null(sh_csv) || is.na(sh_csv) || !file.exists(sh_csv)) {
 warning(sprintf("[SKIP] CSV file not found: %s", sh_csv))
 sheets_skipped <- sheets_skipped +1L
 next
 }
  
 # ----7b. Read CSV ----
 df <- tryCatch(
 read.csv(sh_csv, stringsAsFactors = FALSE, check.names = FALSE),
 error = function(e) {
 warning(sprintf("[SKIP] Failed to read CSV: %s - %s", sh_csv, conditionMessage(e)))
 return(NULL)
 }
 )
  
 if (is.null(df) || nrow(df) ==0 || ncol(df) ==0) {
 warning(sprintf("[SKIP] CSV is empty or has no data: %s", sh_csv))
 sheets_skipped <- sheets_skipped +1L
 next
 }
  
 # ----7c. Sanitize sheet name (Excel: <=31 chars, no : \\ / ? * [ ]) ----
 clean_sheet <- gsub("[:\\\\/\\?\\*\\[\\]]", "_", sh_sheet_name)
 clean_sheet <- substr(clean_sheet,1,31)
 if (is.null(clean_sheet) || is.na(clean_sheet) || nchar(clean_sheet) ==0) {
 clean_sheet <- paste0("Sheet", j)
 }
  
 # ----7d. Add worksheet (with zoom=90) ----
 addWorksheet(wb, sheetName = clean_sheet, zoom =90)
 cat(sprintf(" Sheet name: %s\n", clean_sheet))
  
 ncol_df <- ncol(df)
 nrow_df <- nrow(df)
 last_data_row <- nrow_df +2 # row1=annotation, row2=header, row3+=data
  
 # ----7e. Write annotation (row1, col1) ----
 annotation_text <- if (is.null(sh_annotation) || is.na(sh_annotation)) "" else sh_annotation
 writeData(wb, clean_sheet,
 x = annotation_text,
 startRow =1, startCol =1,
 colNames = FALSE, rowNames = FALSE)
  
 # ----7f. Write column headers (row2) ----
 header_df <- as.data.frame(t(colnames(df)),
 stringsAsFactors = FALSE,
 check.names = FALSE)
 writeData(wb, clean_sheet,
 x = header_df,
 startRow =2, startCol =1,
 colNames = FALSE, rowNames = FALSE)
  
 # ----7g. Write data (from row3) ----
 writeData(wb, clean_sheet,
 x = df,
 startRow =3, startCol =1,
 colNames = FALSE, rowNames = FALSE)
  
 # ----7h. Apply styles (order: default -> annot -> header -> id) ----
 #1) Default style: entire used range
 addStyle(wb, clean_sheet,
 style = default_style,
 rows =1:last_data_row,
 cols =1:ncol_df,
 gridExpand = TRUE,
 stack = FALSE)
  
 #2) Annotation style: row1, all used columns (overlay)
 addStyle(wb, clean_sheet,
 style = annot_style,
 rows =1,
 cols =1:ncol_df,
 gridExpand = TRUE,
 stack = TRUE)
  
 #3) Header style: row2, all used columns (overlay)
 addStyle(wb, clean_sheet,
 style = header_style,
 rows =2,
 cols =1:ncol_df,
 gridExpand = TRUE,
 stack = TRUE)
  
 #4) ID style: column A (col1), rows3 to last data row (overlay)
 if (nrow_df >=1) {
 addStyle(wb, clean_sheet,
 style = id_style,
 rows =3:last_data_row,
 cols =1,
 gridExpand = TRUE,
 stack = TRUE)
 }
  
 # ----7i. Freeze pane: firstActiveRow=3, firstActiveCol=2 (cell B3) ----
 freezePane(wb, clean_sheet,
 firstActiveRow =3,
 firstActiveCol =2)
  
 sheets_processed <- sheets_processed +1L
 cat(sprintf(" -> Done: %d rows x %d columns\n", nrow_df, ncol_df))
}

# ----8. Save workbook ----
xlsx_path <- file.path(output_dir, xlsx_name)
cat("\n============================================================\n")
cat(sprintf("Sheets processed: %d\n", sheets_processed))
if (sheets_skipped >0) {
 cat(sprintf("Sheets skipped (missing/empty): %d\n", sheets_skipped))
}
cat("Saving workbook to:", xlsx_path, "\n")

saveWorkbook(wb, file = xlsx_path, overwrite = TRUE)

# ----9. Verify output ----
if (file.exists(xlsx_path)) {
 file_size <- file.info(xlsx_path)$size
 cat(sprintf("Success: %s generated (%.2f KB)\n", xlsx_name, file_size /1024))
} else {
 stop("Failure: XLSX file was not generated.")
}

cat("============================================================\n")
cat("Module9: PLS-PM Causal Path Analysis compilation complete.\n")
cat("============================================================\n")

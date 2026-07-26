# =============================================================================
# Module2: PCA/PLSDA/OPLSDA Analysis - Results Compilation to XLSX
# =============================================================================
# Description:
# Reads a JSON descriptor file listing CSV results, and compiles them into
# a single structured, styled XLSX workbook using openxlsx.
#
# Task Requirements:
#1. Font: Cambria Math, size11
#2. Row1: annotation text (green font #228B22)
#3. Row2: column headers (dark blue bg #1F4E79, white bold font)
#4. Rows3+: data; first column (ID col) gets light gray bg #D9D9D9, italic
#5. Freeze pane at B3 (firstActiveRow=3, firstActiveCol=2)
#6. Zoom90%
#7. Gracefully skip missing/empty CSV files with warnings
# =============================================================================

# ----1. Load / Install Required Packages ----
if (!require(openxlsx)) install.packages('openxlsx', quiet = TRUE)
if (!require(jsonlite)) install.packages('jsonlite', quiet = TRUE)
library(openxlsx)
library(jsonlite)

# ----2. Configuration ----
json_path <- "G:/OmicsWorks/test/metabolism/demo/analysis/2_pca_plsda_oplsda_analysis/table_descriptions.json"
out_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis/2_pca_plsda_oplsda_analysis"
xlsx_name <- "2_pca_plsda_oplsda_analysis.xlsx"
xlsx_path <- file.path(out_dir, xlsx_name)

font_name <- "Cambria Math"
font_size <-11

cat("============================================================\n")
cat("Module2: PCA/PLSDA/OPLSDA Analysis - Results Compilation\n")
cat("============================================================\n")
cat("JSON file :", json_path, "\n")
cat("Output :", xlsx_path, "\n\n")

# ----3. Read JSON Descriptor ----
if (!file.exists(json_path)) {
 stop("[FATAL] JSON descriptor file not found: ", json_path)
}
desc <- jsonlite::fromJSON(json_path, simplifyVector = FALSE)

cat("Module name:", desc$module_name, "\n")
cat("Sheet count:", length(desc$sheets), "\n\n")

# ----4. Create Workbook ----
wb <- createWorkbook()

# ----5. Create Styles ----
# Default style: Cambria Math11, white background, left-top align, wrap text
defaultStyle <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 fgFill = "#FFFFFF",
 fontColour = "#000000",
 valign = "top",
 halign = "left",
 wrapText = TRUE,
 border = "TopBottomLeftRight",
 borderColour = "#BFBFBF",
 borderStyle = "thin"
)

# Annotation style: forest green font, default (white) background
annotStyle <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 fontColour = "#228B22", # forest green
 valign = "top",
 halign = "left",
 wrapText = TRUE,
 border = "TopBottomLeftRight",
 borderColour = "#BFBFBF",
 borderStyle = "thin"
)

# Header style: dark blue background, white bold font, centered
headerStyle <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 fgFill = "#1F4E79", # dark blue
 fontColour = "#FFFFFF", # white
 textDecoration = "bold",
 valign = "center",
 halign = "center",
 wrapText = TRUE,
 border = "TopBottomLeftRight",
 borderColour = "#BFBFBF",
 borderStyle = "thin"
)

# ID column style: light gray background, italic, black font
idStyle <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 fgFill = "#D9D9D9", # light gray
 fontColour = "#000000",
 textDecoration = "italic",
 valign = "top",
 halign = "left",
 wrapText = TRUE,
 border = "TopBottomLeftRight",
 borderColour = "#BFBFBF",
 borderStyle = "thin"
)

# ----6. Helper: Sanitize sheet names ----
sanitize_sheet_name <- function(raw_name, max_length =31L) {
 if (is.null(raw_name) || is.na(raw_name) || nchar(raw_name) ==0) {
 return("Sheet1")
 }
 cleaned <- gsub("[:\\\\/\\?\\*\\[\\]]", "_", raw_name)
 cleaned <- substr(cleaned,1, max_length)
 cleaned
}

# ----7. Process Each Sheet ----
sheets_processed <-0L
sheets_skipped <-0L

for (i in seq_along(desc$sheets)) {
 sh <- desc$sheets[[i]]
 csv_path <- sh$csv
 sheet_name <- sh$sheet_name
 annotation <- if (is.null(sh$annotation) || is.na(sh$annotation)) "" else sh$annotation

 cat(sprintf(" [%02d/%02d] %s\n", i, length(desc$sheets), basename(csv_path)))

 # ---7a. Check CSV existence ---
 if (is.null(csv_path) || !file.exists(csv_path)) {
 warning(sprintf("[SKIP] CSV file not found: %s", csv_path))
 sheets_skipped <- sheets_skipped +1L
 next
 }

 # ---7b. Read CSV ---
 df <- tryCatch(
 read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE),
 error = function(e) {
 warning(sprintf("[SKIP] Failed to read CSV: %s - %s", csv_path, conditionMessage(e)))
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
 last_data_row <- nrow_df +2 # row1 = annotation, row2 = header, rows3+ = data

 # ---7c. Clean sheet name & add worksheet (zoom set here) ---
 clean_sheet <- sanitize_sheet_name(sheet_name)
 addWorksheet(wb, sheetName = clean_sheet, zoom =90)

 # ---7d. Write annotation (row1, cell A1) ---
 writeData(wb, sheet = clean_sheet,
 x = annotation,
 startRow =1, startCol =1,
 colNames = FALSE, rowNames = FALSE)

 # ---7e. Write column headers (row2) ---
 header_row <- as.data.frame(t(colnames(df)),
 stringsAsFactors = FALSE,
 check.names = FALSE)
 writeData(wb, sheet = clean_sheet,
 x = header_row,
 startRow =2, startCol =1,
 colNames = FALSE, rowNames = FALSE)

 # ---7f. Write data (from row3) ---
 writeData(wb, sheet = clean_sheet,
 x = df,
 startRow =3, startCol =1,
 colNames = FALSE, rowNames = FALSE)

 # ---7g. Compute column widths ---
 col_widths <- vapply(seq_len(ncol_df), function(k) {
 header_len <- nchar(as.character(colnames(df)[k]))
 if (nrow(df) >0) {
 cell_lens <- vapply(df[[k]], function(v) {
 s <- tryCatch(as.character(v), error = function(e) "")
 lines <- unlist(strsplit(s, "\n", fixed = TRUE))
 max(nchar(lines),0)
 }, numeric(1))
 data_len <- max(cell_lens,0)
 } else {
 data_len <-0
 }
 w <- max(header_len, data_len) +2
 min(max(w,10),50)
 }, numeric(1))

 setColWidths(wb, sheet = clean_sheet,
 cols = seq_len(ncol_df), widths = col_widths)

 # ---7h. Apply styles (order: default -> annot -> header -> id) ---

 #1) Default style to entire used range first
 addStyle(wb, sheet = clean_sheet,
 style = defaultStyle,
 rows =1:last_data_row, cols =1:ncol_df,
 gridExpand = TRUE, stack = FALSE)

 #2) Annotation style to row1 (overrides default)
 addStyle(wb, sheet = clean_sheet,
 style = annotStyle,
 rows =1, cols =1:ncol_df,
 gridExpand = TRUE, stack = FALSE)

 #3) Header style to row2 (overrides default)
 addStyle(wb, sheet = clean_sheet,
 style = headerStyle,
 rows =2, cols =1:ncol_df,
 gridExpand = TRUE, stack = FALSE)

 #4) ID column style to column A, rows3 to last data row (overrides default)
 if (nrow_df >=1) {
 addStyle(wb, sheet = clean_sheet,
 style = idStyle,
 rows =3:last_data_row, cols =1,
 gridExpand = TRUE, stack = FALSE)
 }

 # ---7i. Freeze pane (B3: top-left visible cell) ---
 freezePane(wb, sheet = clean_sheet,
 firstActiveRow =3, firstActiveCol =2)

 cat(sprintf(" -> Done: %d rows x %d cols, sheet='%s'\n",
 nrow_df, ncol_df, clean_sheet))
 sheets_processed <- sheets_processed +1L
}

# ----8. Save Workbook ----
cat("\n============================================================\n")
cat(sprintf("Sheets processed: %d\n", sheets_processed))
cat(sprintf("Sheets skipped : %d\n", sheets_skipped))
cat("Saving workbook:", xlsx_path, "\n")

# Ensure output directory exists
if (!dir.exists(out_dir)) {
 dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
}

saveWorkbook(wb, file = xlsx_path, overwrite = TRUE)

# ----9. Verification ----
if (file.exists(xlsx_path)) {
 file_size <- file.info(xlsx_path)$size
 cat(sprintf("SUCCESS: %s generated (%.2f KB)\n",
 xlsx_name, file_size /1024))
} else {
 stop("[FATAL] XLSX file was not created!")
}

cat("============================================================\n")
cat("Module2 compilation complete.\n")
cat("============================================================\n")

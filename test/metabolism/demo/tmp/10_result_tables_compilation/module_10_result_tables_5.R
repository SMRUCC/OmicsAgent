# ==============================================================================
# Module5: KEGG Functional Analysis — Results Compilation to Styled XLSX
# ==============================================================================
# This script reads a JSON description file listing CSV result tables,
# then compiles them into a single structured, styled XLSX workbook.
#
# Output:5_kegg_functional_analysis.xlsx
# ==============================================================================

# ----1. Load / Install Required Packages ----
if (!require(openxlsx)) install.packages('openxlsx', quiet = TRUE)
if (!require(jsonlite)) install.packages('jsonlite', quiet = TRUE)
library(openxlsx)
library(jsonlite)

cat("============================================================\n")
cat("Module5: KEGG Functional Analysis - Results Compilation\n")
cat("============================================================\n")

# ----2. Configuration ----
json_path <- "G:/OmicsWorks/test/metabolism/demo/analysis/5_kegg_functional_analysis/table_descriptions.json"
output_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis/5_kegg_functional_analysis"
xlsx_name <- "5_kegg_functional_analysis.xlsx"
xlsx_path <- file.path(output_dir, xlsx_name)

# ----3. Read JSON Description ----
cat("Reading JSON:", json_path, "\n")
if (!file.exists(json_path)) {
 stop("JSON description file not found: ", json_path)
}

desc <- jsonlite::fromJSON(json_path, simplifyVector = FALSE)

cat(" Module index:", desc$module_index, "\n")
cat(" Module name :", desc$module_name, "\n")
cat(" Sheets count:", length(desc$sheets), "\n\n")

# ----4. Create Output Directory (if needed) ----
if (!dir.exists(output_dir)) {
 dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
 cat("Created output directory:", output_dir, "\n")
}

# ----5. Define Styles ----
# All using font 'Cambria Math', size11
font_name <- "Cambria Math"
font_size <-11

# --- Default style: Cambria Math11, default white background ---
defaultStyle <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 valign = "top",
 halign = "left",
 wrapText = TRUE
)

# --- Annotation style: default background, forest green font '#228B22' ---
annotStyle <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 fontColour = "#228B22",
 valign = "top",
 halign = "left",
 wrapText = TRUE
)

# --- Header style: dark blue bg '#1F4E79', white font '#FFFFFF', bold ---
headerStyle <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 fgFill = "#1F4E79",
 fontColour = "#FFFFFF",
 textDecoration = "bold",
 valign = "center",
 halign = "center",
 wrapText = TRUE
)

# --- ID style: light gray bg '#D9D9D9', italic, black font '#000000' ---
idStyle <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 fgFill = "#D9D9D9",
 textDecoration = "italic",
 fontColour = "#000000",
 valign = "top",
 halign = "left",
 wrapText = TRUE
)

# ----6. Create Workbook ----
wb <- createWorkbook()

sheets_processed <-0L
sheets_skipped <-0L
n_sheets <- length(desc$sheets)

# ----7. Process Each Sheet ----
for (j in seq_len(n_sheets)) {
 sh <- desc$sheets[[j]]

 csv_path <- sh$csv
 sheet_name <- sh$sheet_name
 annotation <- sh$annotation

 cat(sprintf(" [%02d/%02d] Processing: %s\n", j, n_sheets, basename(csv_path)))

 # ---7a. Validate CSV file ---
 if (is.null(csv_path) || !file.exists(csv_path)) {
 warning(paste0(" [SKIP] CSV file not found: ", csv_path))
 sheets_skipped <- sheets_skipped +1L
 next
 }

 # ---7b. Read CSV ---
 df <- tryCatch(
 read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE),
 error = function(e) {
 warning(paste0(" [SKIP] Failed to read CSV: ", csv_path, " — ", conditionMessage(e)))
 return(NULL)
 }
 )
 if (is.null(df) || nrow(df) ==0 || ncol(df) ==0) {
 warning(paste0(" [SKIP] CSV is empty: ", csv_path))
 sheets_skipped <- sheets_skipped +1L
 next
 }

 ncol_df <- ncol(df)
 nrow_df <- nrow(df)
 last_data_row <- nrow_df +2 # row1 = annotation, row2 = header, row3.. = data

 # ---7c. Sanitize sheet name (Excel limitations) ---
 # Max31 chars, no : \\ / ? * [ ]
 clean_name <- gsub("[:\\\\/\\?\\*\\[\\]]", "_", sheet_name)
 clean_name <- substr(clean_name,1,31)
 if (is.null(clean_name) || is.na(clean_name) || nchar(clean_name) ==0) {
 clean_name <- paste0("Sheet", j)
 }

 # ---7d. Add worksheet (zoom set to90 via addWorksheet parameter) ---
 addWorksheet(wb, sheetName = clean_name, zoom =90)

 # ---7e. Write annotation text to row1, column A ---
 writeData(wb, sheet = clean_name,
 x = annotation,
 startRow =1, startCol =1,
 colNames = FALSE, rowNames = FALSE)

 # ---7f. Write CSV column headers to row2 ---
 header_df <- as.data.frame(t(colnames(df)),
 stringsAsFactors = FALSE,
 check.names = FALSE)
 writeData(wb, sheet = clean_name,
 x = header_df,
 startRow =2, startCol =1,
 colNames = FALSE, rowNames = FALSE)

 # ---7g. Write CSV data (without header) from row3 ---
 writeData(wb, sheet = clean_name,
 x = df,
 startRow =3, startCol =1,
 colNames = FALSE, rowNames = FALSE)

 # ---7h. Apply styles (order: default first, then specific overlays) ---

 #1) Default style to entire used range
 addStyle(wb, sheet = clean_name,
 style = defaultStyle,
 rows =1:last_data_row,
 cols =1:ncol_df,
 gridExpand = TRUE, stack = FALSE)

 #2) Annotation style to row1 (all used columns)
 addStyle(wb, sheet = clean_name,
 style = annotStyle,
 rows =1,
 cols =1:ncol_df,
 gridExpand = TRUE, stack = FALSE)

 #3) Header style to row2 (all used columns)
 addStyle(wb, sheet = clean_name,
 style = headerStyle,
 rows =2,
 cols =1:ncol_df,
 gridExpand = TRUE, stack = FALSE)

 #4) ID style to column A, rows3 to last data row
 if (nrow_df >=1) {
 addStyle(wb, sheet = clean_name,
 style = idStyle,
 rows =3:last_data_row,
 cols =1,
 gridExpand = TRUE, stack = FALSE)
 }

 # ---7i. Freeze panes: first column and first two rows (B3 visible) ---
 # firstActiveRow =3, firstActiveCol =2 means cell B3 is top-left visible
 freezePane(wb, sheet = clean_name,
 firstActiveRow =3, firstActiveCol =2)

 cat(sprintf(" -> Written: %d rows x %d cols, sheet='%s'\n",
 nrow_df, ncol_df, clean_name))
 sheets_processed <- sheets_processed +1L
}

# ----8. Save Workbook ----
cat("\n============================================================\n")
cat(sprintf("Sheets processed: %d\n", sheets_processed))
if (sheets_skipped >0) {
 cat(sprintf("Sheets skipped (missing/empty): %d\n", sheets_skipped))
}
cat("Saving workbook to:", xlsx_path, "\n")

saveWorkbook(wb, file = xlsx_path, overwrite = TRUE)

# ----9. Verification ----
if (file.exists(xlsx_path)) {
 file_size <- file.info(xlsx_path)$size
 cat(sprintf("SUCCESS: %s generated (%.2f KB)\n", xlsx_name, file_size /1024))
} else {
 stop("FAILURE: XLSX file was not generated.")
}

cat("============================================================\n")
cat("Module5: KEGG Functional Analysis compilation complete.\n")
cat("============================================================\n")

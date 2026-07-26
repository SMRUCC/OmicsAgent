################################################################################
# Module6: WGCNA Trait Association Analysis
# Compile CSV result tables into a structured, styled XLSX workbook
# Using openxlsx package
################################################################################

# ----1. Load / install required packages ----
if (!require(openxlsx)) install.packages('openxlsx')
if (!require(jsonlite)) install.packages('jsonlite')
library(openxlsx)
library(jsonlite)

cat("============================================================\n")
cat("Module6: WGCNA Trait Association Analysis - Results Compilation\n")
cat("============================================================\n")

# ----2. Paths ----
json_path <- "G:/OmicsWorks/test/metabolism/demo/analysis\\6_wgcna_trait_association_analysis\\table_descriptions.json"
output_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis\\6_wgcna_trait_association_analysis"
xlsx_name <- "6_wgcna_trait_association_analysis.xlsx"
xlsx_path <- file.path(output_dir, xlsx_name)

# ----3. Read JSON description ----
cat("Reading JSON description:", json_path, "\n")
if (!file.exists(json_path)) {
 stop("JSON description file not found: ", json_path)
}
desc <- fromJSON(json_path, simplifyVector = FALSE)

cat("Module name:", desc$module_name, "\n")
cat("Number of sheets:", length(desc$sheets), "\n\n")

# ----4. Create workbook ----
wb <- createWorkbook()

# ----5. Define styles (font: Cambria Math, size:11) ----
font_name <- "Cambria Math"
font_size <-11

# defaultStyle: Cambria Math11, no special fill
defaultStyle <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 valign = "top",
 halign = "left",
 wrapText = TRUE
)

# annotStyle: green font '#228B22', default background
annotStyle <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 fontColour = "#228B22",
 valign = "top",
 halign = "left",
 wrapText = TRUE
)

# headerStyle: dark blue background '#1F4E79', white font '#FFFFFF', bold
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

# idStyle: light gray background '#D9D9D9', italic, black font '#000000'
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

# ----6. Iterate over each sheet ----
sheets_processed <-0L
sheets_skipped <-0L

for (i in seq_along(desc$sheets)) {
 sh <- desc$sheets[[i]]
 csv_path <- sh$csv
 sheet_name_raw <- sh$sheet_name
 annotation_txt <- if (is.null(sh$annotation)) "" else sh$annotation

 cat(sprintf(" [%02d/%02d] Processing: %s\n", i, length(desc$sheets),
 basename(csv_path)))

 # --- Check CSV file ---
 if (is.null(csv_path) || !file.exists(csv_path)) {
 warning("[SKIP] CSV file not found: ", csv_path)
 sheets_skipped <- sheets_skipped +1L
 next
 }

 # --- Read CSV ---
 df <- tryCatch(
 read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE),
 error = function(e) {
 warning("[SKIP] Failed to read CSV: ", csv_path, " - ", conditionMessage(e))
 return(NULL)
 }
 )
 if (is.null(df) || nrow(df) ==0 || ncol(df) ==0) {
 warning("[SKIP] Empty or invalid CSV: ", csv_path)
 sheets_skipped <- sheets_skipped +1L
 next
 }

 ncol_df <- ncol(df)
 nrow_df <- nrow(df)
 last_data_row <- nrow_df +2 # row1 = annotation, row2 = header, row3+ = data

 # --- Sanitize sheet name (Excel: max31 chars, no : \\ / ? * [ ]) ---
 sheet_name <- gsub("[:\\\\/\\?\\*\\[\\]]", "_", sheet_name_raw)
 sheet_name <- substr(sheet_name,1,31)

 # --- Add worksheet with zoom =90 ---
 addWorksheet(wb, sheetName = sheet_name, zoom =90)

 # --- Write annotation (row1, column A) ---
 writeData(wb, sheet = sheet_name,
 x = annotation_txt,
 startRow =1, startCol =1,
 colNames = FALSE, rowNames = FALSE)

 # --- Write column headers (row2) ---
 header_row <- as.data.frame(t(colnames(df)),
 stringsAsFactors = FALSE,
 check.names = FALSE)
 writeData(wb, sheet = sheet_name,
 x = header_row,
 startRow =2, startCol =1,
 colNames = FALSE, rowNames = FALSE)

 # --- Write data (from row3) ---
 writeData(wb, sheet = sheet_name,
 x = df,
 startRow =3, startCol =1,
 colNames = FALSE, rowNames = FALSE)

 # --- Apply styles (order: default -> annot -> header -> id) ---
 #1) defaultStyle: entire used range (rows1:last_data_row, cols1:ncol_df)
 addStyle(wb, sheet = sheet_name,
 style = defaultStyle,
 rows =1:last_data_row, cols =1:ncol_df,
 gridExpand = TRUE, stack = FALSE)

 #2) annotStyle: row1, all used columns
 addStyle(wb, sheet = sheet_name,
 style = annotStyle,
 rows =1, cols =1:ncol_df,
 gridExpand = TRUE, stack = TRUE)

 #3) headerStyle: row2, all used columns
 addStyle(wb, sheet = sheet_name,
 style = headerStyle,
 rows =2, cols =1:ncol_df,
 gridExpand = TRUE, stack = TRUE)

 #4) idStyle: column A (col1), rows3 to last_data_row
 if (nrow_df >=1) {
 addStyle(wb, sheet = sheet_name,
 style = idStyle,
 rows =3:last_data_row, cols =1,
 gridExpand = TRUE, stack = TRUE)
 }

 # --- Freeze pane: firstRow=3, firstCol=2 (B3 is the top-left visible cell) ---
 freezePane(wb, sheet = sheet_name,
 firstActiveRow =3, firstActiveCol =2)

 sheets_processed <- sheets_processed +1L
 cat(sprintf(" -> Done: %d rows x %d cols, sheet='%s'\n",
 nrow_df, ncol_df, sheet_name))
}

# ----7. Save workbook ----
cat("\n============================================================\n")
cat(sprintf("Sheets processed: %d\n", sheets_processed))
if (sheets_skipped >0) {
 cat(sprintf("Sheets skipped (missing/empty): %d\n", sheets_skipped))
}
cat("Saving workbook to:", xlsx_path, "\n")

# Ensure output directory exists
if (!dir.exists(output_dir)) {
 dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
}

saveWorkbook(wb, file = xlsx_path, overwrite = TRUE)

# ----8. Verify ----
if (file.exists(xlsx_path)) {
 file_size <- file.info(xlsx_path)$size
 cat(sprintf("SUCCESS: %s generated (%.2f KB)\n", xlsx_name, file_size /1024))
} else {
 stop("FAILURE: XLSX file was not generated.")
}

cat("============================================================\n")
cat("Module6 (WGCNA Trait Association Analysis) compilation complete.\n")
cat("============================================================\n")

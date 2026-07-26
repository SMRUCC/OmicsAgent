# ============================================================================
# Module8: Dynamic Bayesian Network Analysis — Results Compilation Script
# 
# Description:
# Reads table_descriptions.json (module8), loads each referenced CSV file
# into a formatted XLSX worksheet, and applies professional styling.
#
# Output:
# G:/OmicsWorks/test/metabolism/demo/analysis/8_dynamic_bayesian_network_analysis/
#8_dynamic_bayesian_network_analysis.xlsx
# ============================================================================

cat("============================================================\n")
cat("Module8: Dynamic Bayesian Network Analysis\n")
cat("Goal: Compile CSV results into a structured, styled XLSX workbook\n")
cat("============================================================\n\n")

# ---------------------------------------------------------------------------
#1. Load / install required packages
# ---------------------------------------------------------------------------
if (!require(openxlsx)) install.packages('openxlsx', quiet = TRUE)
if (!require(jsonlite)) install.packages('jsonlite', quiet = TRUE)
library(openxlsx)
library(jsonlite)

# ---------------------------------------------------------------------------
#2. Path configuration (absolute paths)
# ---------------------------------------------------------------------------
json_path <- "G:/OmicsWorks/test/metabolism/demo/analysis/8_dynamic_bayesian_network_analysis/table_descriptions.json"
output_dir <- "G:/OmicsWorks/test/metabolism/demo/analysis/8_dynamic_bayesian_network_analysis"
xlsx_name <- "8_dynamic_bayesian_network_analysis.xlsx"
xlsx_path <- file.path(output_dir, xlsx_name)

cat(" JSON file :", json_path, "\n")
cat(" Output dir :", output_dir, "\n")
cat(" XLSX file :", xlsx_path, "\n\n")

# ---------------------------------------------------------------------------
#3. Read JSON description
# ---------------------------------------------------------------------------
if (!file.exists(json_path)) {
 stop("[FATAL] JSON description file not found: ", json_path)
}

desc <- fromJSON(json_path, simplifyVector = FALSE)

cat(" Module index:", desc$module_index, "\n")
cat(" Module name :", desc$module_name, "\n")
cat(" Sheets :", length(desc$sheets), "\n\n")

# ---------------------------------------------------------------------------
#4. Create workbook
# ---------------------------------------------------------------------------
wb <- createWorkbook()

# ---------------------------------------------------------------------------
#5. Define styles (all using Cambria Math, size11)
# ---------------------------------------------------------------------------
font_name <- "Cambria Math"
font_size <-11

#5a. defaultStyle — white background, Cambria Math11
defaultStyle <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 fgFill = "#FFFFFF",
 halign = "left",
 valign = "top",
 wrapText = TRUE
)

#5b. annotStyle — forest green font '#228B22', default background
annotStyle <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 fontColour = "#228B22",
 halign = "left",
 valign = "top",
 wrapText = TRUE
)

#5c. headerStyle — dark blue bg '#1F4E79', white font '#FFFFFF', bold
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

#5d. idStyle — light gray bg '#D9D9D9', italic, black font '#000000'
idStyle <- createStyle(
 fontName = font_name,
 fontSize = font_size,
 fontColour = "#000000",
 fgFill = "#D9D9D9",
 textDecoration = "italic",
 halign = "left",
 valign = "top",
 wrapText = TRUE
)

# ---------------------------------------------------------------------------
# Helper: set worksheet zoom by manipulating sheetViews XML
# ---------------------------------------------------------------------------
set_worksheet_zoom <- function(wb, sheet_index, zoom =90) {
 ws <- wb$worksheets[[sheet_index]]
 sv <- ws$sheetViews
 if (is.character(sv) && nchar(sv) >0) {
 sv_new <- gsub('zoomScale="\\d+"', sprintf('zoomScale="%d"', zoom), sv)
 ws$sheetViews <- sv_new
 }
 invisible(TRUE)
}

# ---------------------------------------------------------------------------
#6. Process each sheet entry
# ---------------------------------------------------------------------------
n_sheets <- length(desc$sheets)
processed <-0L
skipped <-0L

for (i in seq_len(n_sheets)) {
 sh <- desc$sheets[[i]]

 csv_path <- sh$csv
 sheet_name <- sh$sheet_name
 annotation <- sh$annotation

 cat(sprintf(" [%02d/%02d] %s\n", i, n_sheets, basename(csv_path)))

 # ----6a. Check CSV file existence ----
 if (is.null(csv_path) || !file.exists(csv_path)) {
 warning(sprintf(" [SKIP] CSV not found: %s", csv_path))
 skipped <- skipped +1L
 next
 }

 # ----6b. Read CSV ----
 df <- tryCatch(
 read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE),
 error = function(e) {
 warning(sprintf(" [SKIP] Failed to read CSV: %s — %s", csv_path, e$message))
 return(NULL)
 }
 )

 if (is.null(df) || nrow(df) ==0 || ncol(df) ==0) {
 warning(sprintf(" [SKIP] Empty CSV: %s", csv_path))
 skipped <- skipped +1L
 next
 }

 ncol_df <- ncol(df)
 nrow_df <- nrow(df)

 # ----6c. Sanitize sheet name (Excel restrictions) ----
 # Max31 chars, no : \\ / ? * [ ]
 sanitized <- sheet_name
 sanitized <- gsub("[:\\\\/\\?\\*\\[\\]]", "_", sanitized)
 sanitized <- substr(sanitized,1,31)
 if (nchar(sanitized) ==0) sanitized <- paste0("Sheet", i)

 cat(sprintf(" Sheet: '%s' (%d rows x %d cols)\n", sanitized, nrow_df, ncol_df))

 # ----6d. Add worksheet ----
 addWorksheet(wb, sheetName = sanitized)
 sheet_idx <- length(wb$worksheets) # index of the sheet we just added

 # ----6e. Write annotation text to row1, column A ----
 writeData(wb, sanitized,
 x = annotation,
 startRow =1, startCol =1,
 colNames = FALSE, rowNames = FALSE)

 # ----6f. Write column headers to row2 ----
 header_row <- as.data.frame(t(colnames(df)),
 stringsAsFactors = FALSE, check.names = FALSE)
 writeData(wb, sanitized,
 x = header_row,
 startRow =2, startCol =1,
 colNames = FALSE, rowNames = FALSE)

 # ----6g. Write data (without headers) starting from row3 ----
 writeData(wb, sanitized,
 x = df,
 startRow =3, startCol =1,
 colNames = FALSE, rowNames = FALSE)

 # ----6h. Apply default style to entire used range ----
 last_data_row <- nrow_df +2 # row1=annotation, row2=header, row3+=data
 addStyle(wb, sanitized,
 style = defaultStyle,
 rows =1:last_data_row,
 cols =1:ncol_df,
 gridExpand = TRUE,
 stack = FALSE)

 # ----6i. Overlay annotation style on row1 ----
 addStyle(wb, sanitized,
 style = annotStyle,
 rows =1,
 cols =1:ncol_df,
 gridExpand = TRUE,
 stack = TRUE)

 # ----6j. Overlay header style on row2 ----
 addStyle(wb, sanitized,
 style = headerStyle,
 rows =2,
 cols =1:ncol_df,
 gridExpand = TRUE,
 stack = TRUE)

 # ----6k. Overlay ID column style on column A (rows3 to last) ----
 if (nrow_df >=1) {
 addStyle(wb, sanitized,
 style = idStyle,
 rows =3:last_data_row,
 cols =1,
 gridExpand = TRUE,
 stack = TRUE)
 }

 # ----6l. Freeze pane at B3 (firstActiveRow=3, firstActiveCol=2) ----
 freezePane(wb, sanitized,
 firstActiveRow =3,
 firstActiveCol =2)

 # ----6m. Set zoom to90% via sheetViews XML manipulation ----
 set_worksheet_zoom(wb, sheet_idx, zoom =90)

 processed <- processed +1L
 cat(" Done.\n")
}

# ---------------------------------------------------------------------------
#7. Summary and save
# ---------------------------------------------------------------------------
cat("\n============================================================\n")
cat(sprintf("Sheets processed: %d\n", processed))
if (skipped >0) {
 cat(sprintf("Sheets skipped : %d (missing / empty CSV)\n", skipped))
}
cat("Saving workbook...\n")

saveWorkbook(wb, file = xlsx_path, overwrite = TRUE)

# ---------------------------------------------------------------------------
#8. Verify output
# ---------------------------------------------------------------------------
if (file.exists(xlsx_path)) {
 file_size_kb <- file.info(xlsx_path)$size /1024
 cat(sprintf("SUCCESS: %s generated (%.2f KB)\n", xlsx_name, file_size_kb))
} else {
 stop("FAILURE: XLSX file was not created.")
}

cat("============================================================\n")
cat("Module8 compilation completed.\n")
cat("============================================================\n")

# ============================================================
# compile_csv_to_xlsx.R
# Generic function: compile multiple CSV result tables into a
# structured, styled XLSX workbook with merged annotation row.
# ============================================================

#' Compile multiple CSV files into a styled XLSX workbook
#'
#' @param csv_paths   Character vector of absolute CSV file paths.
#' @param output_xlsx Character scalar; absolute path of output XLSX.
#' @param json_path   Character scalar; path to table_descriptions.json
#'                    used to look up sheet_name and annotation text.
#'
#' @return Invisibly returns the path to the generated XLSX file.
#' @export
compile_csv_to_xlsx <- function(csv_paths, output_xlsx, json_path) {

  # ---- 1. Ensure required packages ----
  if (!require(openxlsx, quietly = TRUE)) {
    install.packages("openxlsx", repos = "https://cloud.r-project.org")
    library(openxlsx)
  }
  if (!require(jsonlite, quietly = TRUE)) {
    install.packages("jsonlite", repos = "https://cloud.r-project.org")
    library(jsonlite)
  }

  # ---- 2. Validate inputs ----
  if (!is.character(csv_paths) || length(csv_paths) == 0L)
    stop("'csv_paths' must be a non-empty character vector.")
  if (!is.character(output_xlsx) || length(output_xlsx) != 1L)
    stop("'output_xlsx' must be a single character string.")
  if (!is.character(json_path) || length(json_path) != 1L)
    stop("'json_path' must be a single character string.")
  if (!file.exists(json_path))
    stop("JSON description file not found: ", json_path)

  out_dir <- dirname(output_xlsx)
  if (!dir.exists(out_dir)) {
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    cat("Created output directory:", out_dir, "\n")
  }

  # ---- 3. Read JSON description ----
  desc      <- jsonlite::fromJSON(json_path, simplifyVector = TRUE)
  sheets_df <- desc$sheets

  cat("============================================================\n")
  if (!is.null(desc$goal))        cat("Goal        :", desc$goal, "\n")
  if (!is.null(desc$folder_name)) cat("Folder name :", desc$folder_name, "\n")
  if (!is.null(desc$xlsx_file))   cat("Target xlsx :", desc$xlsx_file, "\n")
  cat("Input CSVs  :", length(csv_paths), "\n")
  cat("JSON sheets :", nrow(sheets_df), "\n")
  cat("============================================================\n\n")

  # ---- 4. Helpers ----
  sanitize_sheet_name <- function(name) {
    name <- gsub("[:\\\\/?*\\[\\]]", "_", name)
    substr(name, 1, 31)
  }

  lookup_sheet_meta <- function(csv_path) {
    idx <- match(csv_path, sheets_df$csv)
    if (is.na(idx)) {
      norm_csv  <- normalizePath(csv_path, mustWork = FALSE)
      norm_json <- vapply(sheets_df$csv, normalizePath,
                          character(1), mustWork = FALSE)
      idx <- match(norm_csv, norm_json)
    }
    if (is.na(idx)) {
      list(
        sheet_name = sanitize_sheet_name(
          tools::file_path_sans_ext(basename(csv_path))
        ),
        annotation = paste("Data imported from:", basename(csv_path))
      )
    } else {
      list(
        sheet_name = sanitize_sheet_name(sheets_df$sheet_name[idx]),
        annotation = as.character(sheets_df$annotation[idx])
      )
    }
  }

  # ---- 5. Cell styles (Cambria Math, 11) ----
  defaultStyle <- createStyle(
    fontName = "Cambria Math", fontSize = 11,
    fontColour = "#000000", bgFill = "#FFFFFF"
  )
  annotStyle <- createStyle(
    fontName = "Cambria Math", fontSize = 11,
    fontColour = "#228B22", wrapText = TRUE, valign = "top"
  )
  headerStyle <- createStyle(
    fontName = "Cambria Math", fontSize = 11,
    fontColour = "#FFFFFF", bgFill = "#1F4E79",
    textDecoration = "bold", halign = "center", valign = "center"
  )
  idStyle <- createStyle(
    fontName = "Cambria Math", fontSize = 11,
    fontColour = "#000000", bgFill = "#D9D9D9",
    textDecoration = "italic"
  )

  # ---- 6. Workbook setup ----
  wb         <- createWorkbook()
  used_names <- character(0)
  processed  <- 0L
  n_csvs     <- length(csv_paths)

  # ---- 7. Iterate over CSV paths ----
  for (i in seq_len(n_csvs)) {
    csv_path   <- csv_paths[i]
    meta       <- lookup_sheet_meta(csv_path)
    sheet_name <- meta$sheet_name
    annotation <- meta$annotation

    # Ensure unique sheet name
    orig <- sheet_name; k <- 1L
    while (sheet_name %in% used_names) {
      suffix <- sprintf("_%d", k)
      sheet_name <- paste0(substr(orig, 1, 31 - nchar(suffix)), suffix)
      k <- k + 1L
    }
    used_names <- c(used_names, sheet_name)

    cat(sprintf("[%d/%d] Sheet '%s'\n", i, n_csvs, sheet_name))

    if (!file.exists(csv_path)) {
      warning(sprintf("  CSV not found, skipping: %s", csv_path))
      next
    }
    df <- tryCatch(
      read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE),
      error = function(e) {
        warning(sprintf("  Failed to read CSV (%s): %s",
                        csv_path, e$message)); NULL
      }
    )
    if (is.null(df) || ncol(df) == 0L) {
      warning(sprintf("  Empty or unreadable data frame: %s", csv_path))
      next
    }

    n_rows <- nrow(df); n_cols <- ncol(df)
    cat(sprintf("  Rows: %d, Cols: %d\n", n_rows, n_cols))

    addWorksheet(wb, sheetName = sheet_name)

    # Row 1: annotation
    writeData(wb, sheet_name, x = annotation,
              startRow = 1, startCol = 1,
              colNames = FALSE, rowNames = FALSE)
              
    # ---- Merge cells in Row 1 across all used columns ----
    if (n_cols > 1) {
      mergeCells(wb, sheet_name, cols = c(1, n_cols), rows = 1)
    }

    # Row 2: headers
    hdr_df <- as.data.frame(t(colnames(df)), stringsAsFactors = FALSE)
    writeData(wb, sheet_name, x = hdr_df,
              startRow = 2, startCol = 1,
              colNames = FALSE, rowNames = FALSE)
    # Row 3+: data
    writeData(wb, sheet_name, x = df,
              startRow = 3, startCol = 1,
              colNames = FALSE, rowNames = FALSE)

    last_row <- 2L + n_rows
    last_col <- n_cols

    # Apply defaultStyle to entire used range
    addStyle(wb, sheet_name, style = defaultStyle,
             rows = 1:last_row, cols = 1:last_col,
             gridExpand = TRUE, stack = FALSE)
             
    # Apply annotStyle on row 1 (will apply to the active top-left cell of merge)
    addStyle(wb, sheet_name, style = annotStyle,
             rows = 1, cols = 1:last_col,
             gridExpand = TRUE, stack = TRUE)
             
    # Apply headerStyle on row 2
    addStyle(wb, sheet_name, style = headerStyle,
             rows = 2, cols = 1:last_col,
             gridExpand = TRUE, stack = TRUE)
             
    # Apply idStyle on column A, rows 3 to last data row
    if (n_rows >= 1L) {
      addStyle(wb, sheet_name, style = idStyle,
               rows = 3:(2L + n_rows), cols = 1,
               gridExpand = TRUE, stack = TRUE)
    }

    # Set column widths
    setColWidths(wb, sheet_name, cols = 1, widths = 30)
    if (n_cols > 1L) {
      setColWidths(wb, sheet_name,
                   cols = 2:n_cols,
                   widths = rep(18, n_cols - 1L))
    }
    
    # Set row heights (increased row 1 height for merged long text)
    setRowHeights(wb, sheet_name, rows = 1, heights = 120)
    setRowHeights(wb, sheet_name, rows = 2, heights = 22)

    # Freeze panes and zoom
    freezePane(wb, sheet_name, firstRow = TRUE, firstCol = TRUE)
    # setZoom(wb, sheet_name, zoom = 90)

    processed <- processed + 1L
    cat(sprintf("  -> Sheet '%s' completed.\n", sheet_name))
  }

  cat(sprintf("\nProcessed %d/%d sheets.\n", processed, n_csvs))
  if (processed == 0L) stop("No sheets were processed. XLSX not generated.")

  cat(sprintf("Saving workbook to: %s\n", output_xlsx))
  saveWorkbook(wb, file = output_xlsx, overwrite = TRUE)
  cat("XLSX file successfully generated.\n")

  invisible(output_xlsx)
}


# ============================================================
# Example usage (uncomment to run end-to-end)
# ============================================================
# json_path   <- "F:/datapool/20260715-spatial/analysis_2/limma/result/analysis/1_multiplevar_test/table_descriptions.json"
# output_xlsx <- "F:/datapool/20260715-spatial/analysis_2/limma/result/analysis/1_multiplevar_test/1_multiplevar_test.xlsx"
#
# desc <- jsonlite::fromJSON(json_path, simplifyVector = TRUE)
# csv_paths <- desc$sheets$csv   # use all CSVs listed in JSON
#
# compile_csv_to_xlsx(
#   csv_paths   = csv_paths,
#   output_xlsx = output_xlsx,
#   json_path   = json_path
# )

# ---- 1. 加载依赖包 ----
if (!require(openxlsx)) install.packages('openxlsx')
if (!require(jsonlite)) install.packages('jsonlite')
library(openxlsx)
library(jsonlite)


################################################################################
# 一、样式构建函数
################################################################################

#' 创建 XLSX 单元格样式集合
#'
#' 创建一组 openxlsx 样式对象，用于格式化差异分析结果工作簿。
#'
#' 本函数集中管理所有单元格样式，便于统一调整字体、颜色、对齐方式、
#' 边框等属性。返回的样式列表将被后续的 \code{add_sheet_from_csv()} 等
#' 函数引用。
#'
#' @param font_name 字符串。字体名称，所有样式统一使用该字体。
#'   默认为 \code{"Cambria Math"}，适合显示数学符号与中英文字符。
#' @param font_size 数值。字体大小（磅），默认为 11。
#' @param header_fill 字符串。表头背景色（十六进制颜色码），默认为
#'   \code{"#1F4E79"}（深蓝色）。
#' @param header_font 字符串。表头字体颜色，默认为 \code{"#FFFFFF"}
#'   （白色）。
#' @param annot_font 字符串。注释文字颜色，默认为 \code{"#228B22"}
#'   （森林绿）。
#' @param id_fill 字符串。ID 列背景色，默认为 \code{"#D9D9D9"}
#'   （浅灰色）。
#' @param border_color 字符串。表格边框颜色，默认为 \code{"#BFBFBF"}
#'   （浅灰色边框）。
#'
#' @return 列表，包含以下元素：
#'   \item{default}{数据区默认样式：指定字体、顶端对齐、自动换行、边框}
#'   \item{annotation}{注释行样式：森林绿字体、顶端左对齐、自动换行、边框}
#'   \item{header}{表头样式：白字加粗、深蓝底、水平垂直居中、自动换行、边框}
#'   \item{id_column}{ID 列样式：浅灰底、斜体、左对齐、边框}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' styles <- create_xlsx_styles(font_name = "Cambria Math", font_size = 11)
#' }
create_xlsx_styles <- function(font_name      = "Cambria Math",
                              font_size      = 11,
                              header_fill    = "#1F4E79",
                              header_font    = "#FFFFFF",
                              annot_font     = "#228B22",
                              id_fill        = "#D9D9D9",
                              border_color   = "#BFBFBF") {

  # 公共边框颜色与样式通过 createStyle 的 border / borderColour / borderStyle
  # 参数直接指定，无需单独创建 border 对象。

  # --- 默认数据样式 ---
  # 顶端对齐 + 自动换行，避免长文本被截断；附加四边边框以构建表格结构
  default_style <- openxlsx::createStyle(
    fontName       = font_name,
    fontSize       = font_size,
    valign         = "top",
    halign         = "left",
    wrapText       = TRUE,
    border         = "TopBottomLeftRight",
    borderColour   = border_color,
    borderStyle    = "thin"
  )

  # --- 注释行样式 ---
  # 森林绿字体 + 顶端左对齐 + 自动换行 + 边框
  annotation_style <- openxlsx::createStyle(
    fontName       = font_name,
    fontSize       = font_size,
    fontColour     = annot_font,
    valign         = "top",
    halign         = "left",
    wrapText       = TRUE,
    border         = "TopBottomLeftRight",
    borderColour   = border_color,
    borderStyle    = "thin"
  )

  # --- 表头样式 ---
  # 白字加粗 + 深蓝底 + 水平垂直居中 + 自动换行 + 边框
  header_style <- openxlsx::createStyle(
    fontName       = font_name,
    fontSize       = font_size,
    fontColour     = header_font,
    fgFill         = header_fill,
    textDecoration = "bold",
    valign         = "center",
    halign         = "center",
    wrapText       = TRUE,
    border         = "TopBottomLeftRight",
    borderColour   = border_color,
    borderStyle    = "thin"
  )

  # --- ID 列样式 ---
  # 浅灰底 + 斜体 + 左对齐 + 边框（用于第一列标识列）
  id_style <- openxlsx::createStyle(
    fontName       = font_name,
    fontSize       = font_size,
    fgFill         = id_fill,
    textDecoration = "italic",
    fontColour     = "#000000",
    valign         = "top",
    halign         = "left",
    wrapText       = TRUE,
    border         = "TopBottomLeftRight",
    borderColour   = border_color,
    borderStyle    = "thin"
  )

  list(
    default     = default_style,
    annotation  = annotation_style,
    header      = header_style,
    id_column   = id_style
  )
}


################################################################################
# 二、表名清洗函数
################################################################################

#' 清洗 Excel 工作表名称
#'
#' 将原始工作表名称清洗为符合 Excel 命名规则的字符串。
#'
#' Excel 对工作表名称有以下限制：
#'   \itemize{
#'     \item 长度不超过 31 个字符
#'     \item 不能包含字符：\code{: \\ / ? * [ ] }
#'     \item 不能为空
#'   }
#'
#' 本函数将非法字符替换为下划线，并截断至最大长度。
#'
#' @param raw_name 字符串。原始工作表名称。
#' @param max_length 整数。最大允许长度，默认为 31（Excel 上限）。
#' @return 字符串。清洗后的工作表名称。
#' @export
#'
#' @examples
#' sanitize_sheet_name("limma_HighFe+CDI_vs_CDI")     # "limma_HighFe+CDI_vs_CDI"
#' sanitize_sheet_name("a:b/c?d*e[f]")                  # "a_b_c_d_e_f_"
sanitize_sheet_name <- function(raw_name, max_length = 31L) {
  if (is.null(raw_name) || is.na(raw_name) || nchar(raw_name) == 0) {
    return("Sheet1")
  }
  # 替换非法字符 : \ / ? * [ ] 为下划线
  cleaned <- gsub("[:\\\\/\\?\\*\\[\\]]", "_", raw_name)
  # 截断至最大长度
  cleaned <- substr(cleaned, 1, max_length)
  cleaned
}


################################################################################
# 三、列宽计算函数
################################################################################

#' 计算自适应列宽
#'
#' 根据数据框内容与表头文字估算每列的合适宽度。
#'
#' 对每一列，取表头字符数与所有数据单元格字符数的最大值，
#' 加上一定填充量，并限制在 \code{min_width} 与 \code{max_width} 之间。
#'
#' @param df 数据框。用于计算列宽的数据。
#' @param min_width 数值。最小列宽（字符数），默认为 10。
#' @param max_width 数值。最大列宽（字符数），默认为 50。
#'   超过此宽度的列将截断，避免单列过宽影响阅读。
#' @param padding 数值。每列额外填充字符数，默认为 2。
#' @return 数值向量。每列对应的宽度（与 \code{ncol(df)} 等长）。
#' @export
#'
#' @examples
#' df <- data.frame(Feature = c("A", "BB", "CCC"), logFC = c(1.2, 0.5, -0.8))
#' compute_column_widths(df)
compute_column_widths <- function(df,
                                  min_width = 10,
                                  max_width = 50,
                                  padding   = 2) {
  if (ncol(df) == 0) return(numeric(0))

  widths <- vapply(seq_len(ncol(df)), function(k) {
    # 表头字符数
    header_len <- nchar(as.character(colnames(df)[k]))
    # 数据单元格字符数（取最大值；为空则取 0）
    if (nrow(df) > 0) {
      cell_lens <- vapply(df[[k]], function(v) {
        s <- tryCatch(as.character(v), error = function(e) "")
        # 处理多行文本（按最长单行计）
        lines <- unlist(strsplit(s, "\n", fixed = TRUE))
        max(nchar(lines), 0)
      }, numeric(1))
      data_len <- max(cell_lens, 0)
    } else {
      data_len <- 0
    }
    # 取表头与数据的最大值，加填充
    w <- max(header_len, data_len) + padding
    # 限制在 [min_width, max_width]
    min(max(w, min_width), max_width)
  }, numeric(1))

  widths
}


################################################################################
#四、注释行高计算函数
################################################################################

#' 估算注释行所需行高
#'
#' 根据注释文本长度与表格总宽度，估算注释行所需的行高（像素）。
#'
#' 算法：将注释按总宽度（字符数）拆分为多行，每行约 15 像素，
#' 加上上下内边距，得到总行高。最低不低于 30 像素。
#'
#' @param annotation 字符串。注释文本。
#' @param total_width_chars 数值。表格所有列宽之和（字符数），
#'   用于估算每行可容纳的字符数。
#' @param px_per_line 数值。每行高度（像素），默认为 15。
#' @param padding_px 数值。上下内边距（像素），默认为 8。
#' @param min_height 数值。最小行高（像素），默认为 30。
#' @param max_height 数值。最大行高（像素），默认为 240，
#'   避免注释过长导致单行过高影响阅读。
#' @return 数值。估算的行高（像素）。
#' @export
#'
#' @examples
#' compute_annotation_row_height("This is a long annotation...", 80)
compute_annotation_row_height <- function(annotation,
                                          total_width_chars,
                                          px_per_line = 15,
                                          padding_px  = 8,
                                          min_height  = 30,
                                          max_height  = 240) {
  if (is.null(annotation) || is.na(annotation) || nchar(annotation) == 0) {
    return(min_height)
  }
  # 每行可容纳字符数（保守估计，考虑中英文混排）
  chars_per_line <- max(total_width_chars, 10)
  # 估算所需行数
  n_lines <- ceiling(nchar(annotation) / chars_per_line)
  # 同时考虑显式换行符
  n_explicit <- length(unlist(strsplit(annotation, "\n", fixed = TRUE)))
  n_lines <- max(n_lines, n_explicit)
  # 计算行高并限制范围
  height <- n_lines * px_per_line + padding_px
  height <- max(height, min_height)
  height <- min(height, max_height)
  height
}


################################################################################
# 五、单表写入函数
################################################################################

#' 从 CSV 添加一个格式化工作表
#'
#' 读取 CSV 数据，将其写入工作簿的一个新工作表，并应用完整的格式化：
#'   第一行：注释（合并单元格、自动换行、行高自适应）
#'   第二行：表头（深蓝底白字加粗居中）
#'   第三行起：数据（默认样式，第一列为 ID 列样式）
#'   冻结窗格：B3（保留注释行、表头行与 ID 列）
#'   自动筛选：表头行起启用列筛选，便于数据探索
#'
#' @param wb openxlsx 工作簿对象（\code{createWorkbook()} 的返回值）。
#' @param sheet_desc 列表。描述单个工作表的元数据，须包含字段：
#'   \itemize{
#'     \item \code{csv}：CSV 文件路径
#'     \item \code{sheet_name}：工作表名称（原始，会被自动清洗）
#'     \item \code{annotation}：注释文本（写入第一行）
#'   }
#' @param styles 列表。\code{\link{create_xlsx_styles}} 返回的样式集合。
#' @param zoom 整数。工作表缩放百分比，默认为 90。
#' @param min_col_width 数值。最小列宽，默认为 10。
#' @param max_col_width 数值。最大列宽，默认为 50。
#' @return 逻辑值。成功写入返回 \code{TRUE}；CSV 不存在或为空返回
#'   \code{FALSE}（并发出 \code{warning}）。
#' @export
#'
#' @examples
#' \dontrun{
#' wb <- createWorkbook()
#' styles <- create_xlsx_styles()
#' add_sheet_from_csv(wb, sheet_desc, styles)
#' }
add_sheet_from_csv <- function(wb,
                              sheet_desc,
                              styles,
                              zoom          = 90,
                              min_col_width = 10,
                              max_col_width = 50) {

  # --- 校验 CSV 文件存在性 ---
  csv_path <- sheet_desc$csv
  if (is.null(csv_path) || !file.exists(csv_path)) {
    warning(paste0("[SKIP] CSV 文件未找到: ", csv_path))
    return(invisible(FALSE))
  }

  # --- 读取 CSV ---
  df <- tryCatch(
    read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE),
    error = function(e) {
      warning(paste0("[SKIP] CSV 读取失败: ", csv_path, " — ", conditionMessage(e)))
      return(NULL)
    }
  )
  if (is.null(df) || nrow(df) == 0 || ncol(df) == 0) {
    warning(paste0("[SKIP] CSV 为空或无数据: ", csv_path))
    return(invisible(FALSE))
  }

  # --- 清洗工作表名称 ---
  raw_sheet   <- sheet_desc$sheet_name
  clean_sheet <- sanitize_sheet_name(raw_sheet)

  # --- 添加工作表 ---
  openxlsx::addWorksheet(wb, sheetName = clean_sheet, zoom = zoom)

  ncol_df       <- ncol(df)
  nrow_df       <- nrow(df)
  last_col      <- ncol_df
  last_data_row <- nrow_df + 2   # 第1行注释, 第2行表头, 第3行起数据

  # --- 写入注释（第1行 A1） ---
  annotation_text <- if (is.null(sheet_desc$annotation)) "" else sheet_desc$annotation
  openxlsx::writeData(
    wb, sheet = clean_sheet,
    x         = annotation_text,
    startRow  = 1, startCol = 1,
    colNames  = FALSE, rowNames = FALSE
  )

  # --- 合并注释行单元格（A1:<lastcol>1） ---
  if (last_col > 1) {
    openxlsx::mergeCells(wb, sheet = clean_sheet, cols = 1:last_col, rows = 1)
  }

  # --- 写入表头（第2行） ---
  header_df <- as.data.frame(t(colnames(df)), stringsAsFactors = FALSE,
                             check.names = FALSE)
  openxlsx::writeData(
    wb, sheet = clean_sheet,
    x         = header_df,
    startRow  = 2, startCol = 1,
    colNames  = FALSE, rowNames = FALSE
  )

  # --- 写入数据（第3行起） ---
  openxlsx::writeData(
    wb, sheet = clean_sheet,
    x         = df,
    startRow  = 3, startCol = 1,
    colNames  = FALSE, rowNames = FALSE
  )

  # --- 计算并设置列宽 ---
  col_widths <- compute_column_widths(df,
                                       min_width = min_col_width,
                                       max_width = max_col_width)
  openxlsx::setColWidths(wb, sheet = clean_sheet,
                          cols = seq_len(ncol_df), widths = col_widths)

  # --- 计算并设置注释行高 ---
  total_width_chars <- sum(col_widths)
  annot_height <- compute_annotation_row_height(annotation_text,
                                                total_width_chars)
  openxlsx::setRowHeights(wb, sheet = clean_sheet,
                          rows = 1, heights = annot_height)

  # --- 设置表头行高 ---
  openxlsx::setRowHeights(wb, sheet = clean_sheet,
                          rows = 2, heights = 30)

  # --- 应用样式（顺序：默认 -> 注释 -> 表头 -> ID 列） ---
  # 1) 默认样式覆盖整个使用区域
  openxlsx::addStyle(
    wb, sheet = clean_sheet,
    style     = styles$default,
    rows      = 1:last_data_row, cols = 1:ncol_df,
    gridExpand = TRUE, stack = FALSE
  )
  # 2) 注释样式覆盖第1行所有列（合并单元格需对所有单元格设置样式，
  #    以保证边框正确渲染）
  openxlsx::addStyle(
    wb, sheet = clean_sheet,
    style     = styles$annotation,
    rows      = 1, cols = 1:ncol_df,
    gridExpand = TRUE, stack = FALSE
  )
  # 3) 表头样式覆盖第2行
  openxlsx::addStyle(
    wb, sheet = clean_sheet,
    style     = styles$header,
    rows      = 2, cols = 1:ncol_df,
    gridExpand = TRUE, stack = FALSE
  )
  # 4) ID 列样式覆盖第3行至末行（仅第1列）
  if (nrow_df >= 1) {
    openxlsx::addStyle(
      wb, sheet = clean_sheet,
      style     = styles$id_column,
      rows      = 3:last_data_row, cols = 1,
      gridExpand = TRUE, stack = FALSE
    )
  }

  # --- 冻结窗格：B3（保留注释行、表头行与 ID 列） ---
  openxlsx::freezePane(wb, sheet = clean_sheet,
                       firstActiveRow = 3, firstActiveCol = 2)

  # --- 添加自动筛选（表头行 + 数据区） ---
  # 便于在 Excel 中按列筛选数据
  openxlsx::addFilter(wb, sheet = clean_sheet,
                      rows = 2:last_data_row, cols = 1:ncol_df)

  # --- 返回成功标志 ---
  cat(sprintf("    -> 写入完成: %d 行 x %d 列, 注释行高 %.0f px\n",
              nrow_df, ncol_df, annot_height))
  invisible(TRUE)
}


################################################################################
# 六、整体构建函数
################################################################################

#' 从 JSON 描述文件构建格式化 XLSX 工作簿
#'
#' 读取 \code{table_descriptions.json} 元数据文件，遍历其中每个 sheet
#' 描述，将对应的 CSV 文件合并为一个带完整格式的 XLSX 工作簿。
#'
#' JSON 文件结构示例：
#' \preformatted{
#' {
#'   "module_name": "LIMMA Differential Analysis",
#'   "xlsx_file": "4_limma_differential_analysis.xlsx",
#'   "sheets": [
#'     {
#'       "csv": "path/to/limma_CDI_vs_Control.csv",
#'       "sheet_name": "limma_CDI_vs_Control",
#'       "annotation": "This sheet contains ..."
#'     }
#'   ]
#' }
#' }
#'
#' @param json_path 字符串。\code{table_descriptions.json} 文件路径。
#' @param out_dir 字符串。输出目录路径。若不存在会自动创建。
#' @param xlsx_name 字符串。输出 XLSX 文件名。
#'   若为 \code{NULL}，则尝试从 JSON 的 \code{xlsx_file} 字段读取。
#' @param font_name 字符串。统一字体名称，默认为 \code{"Cambria Math"}。
#' @param font_size 数值。字体大小（磅），默认为 11。
#' @param zoom 整数。工作表缩放百分比，默认为 90。
#' @param min_col_width 数值。最小列宽，默认为 10。
#' @param max_col_width 数值。最大列宽，默认为 50。
#' @param overwrite 逻辑值。是否覆盖已存在的 XLSX 文件，默认为 \code{TRUE}。
#' @return 字符串。生成的 XLSX 文件完整路径（成功时）；
#'   失败时抛出错误。
#' @export
#'
#' @examples
#' \dontrun{
#' build_xlsx_from_descriptions(
#'   json_path = "G:/OmicsWorks/.../table_descriptions.json",
#'   out_dir   = "G:/OmicsWorks/.../4_limma_differential_analysis",
#'   xlsx_name = "4_limma_differential_analysis.xlsx"
#' )
#' }
build_xlsx_from_descriptions <- function(json_path,
                                         out_dir,
                                         xlsx_name     = NULL,
                                         font_name     = "Cambria Math",
                                         font_size     = 11,
                                         zoom          = 90,
                                         min_col_width = 10,
                                         max_col_width = 50,
                                         overwrite     = TRUE) {

  cat("============================================================\n")
  cat("Module 4: LIMMA Differential Analysis - Results Compilation\n")
  cat("读取 JSON 描述文件:", json_path, "\n")

  # --- 校验 JSON 文件存在 ---
  if (!file.exists(json_path)) {
    stop("JSON 描述文件未找到: ", json_path)
  }

  # --- 读取 JSON ---
  desc <- jsonlite::fromJSON(json_path, simplifyVector = FALSE)

  cat("模块名称:", desc$module_name, "\n")
  n_sheets <- length(desc$sheets)
  cat("工作表数量 (CSV 文件):", n_sheets, "\n\n")

  # --- 确定输出文件名 ---
  if (is.null(xlsx_name)) {
    xlsx_name <- if (!is.null(desc$xlsx_file)) desc$xlsx_file
                 else "output.xlsx"
  }
  xlsx_path <- file.path(out_dir, xlsx_name)

  # --- 创建输出目录 ---
  if (!dir.exists(out_dir)) {
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    cat("已创建输出目录:", out_dir, "\n")
  }

  # --- 创建样式集合 ---
  styles <- create_xlsx_styles(font_name = font_name, font_size = font_size)

  # --- 创建工作簿 ---
  wb <- openxlsx::createWorkbook()

  sheets_processed <- 0L
  sheets_skipped   <- 0L

  # --- 遍历每个 sheet 描述 ---
  for (j in seq_along(desc$sheets)) {
    sh <- desc$sheets[[j]]
    cat(sprintf(" [%02d/%02d] 处理: %s\n", j, n_sheets, basename(sh$csv)))
    ok <- add_sheet_from_csv(
      wb           = wb,
      sheet_desc   = sh,
      styles       = styles,
      zoom         = zoom,
      min_col_width = min_col_width,
      max_col_width = max_col_width
    )
    if (isTRUE(ok)) {
      sheets_processed <- sheets_processed + 1L
    } else {
      sheets_skipped <- sheets_skipped + 1L
    }
  }

  # --- 保存工作簿 ---
  cat("\n============================================================\n")
  cat(sprintf("已处理工作表: %d\n", sheets_processed))
  if (sheets_skipped > 0) {
    cat(sprintf("已跳过工作表 (缺失/空): %d\n", sheets_skipped))
  }
  cat("保存工作簿至:", xlsx_path, "\n")

  openxlsx::saveWorkbook(wb, file = xlsx_path, overwrite = overwrite)

  # --- 最终校验 ---
  if (file.exists(xlsx_path)) {
    file_size <- file.info(xlsx_path)$size
    cat(sprintf("成功: %s 已生成 (%.2f KB)\n",
                xlsx_name, file_size / 1024))
  } else {
    stop("失败: XLSX 文件未生成。")
  }

  cat("============================================================\n")
  cat("Module 4 编译完成。\n")
  cat("============================================================\n")

  invisible(xlsx_path)
}


################################################################################
# 七、主流程入口
################################################################################

#' Module 4 结果编译主入口
#'
#' 配置路径并调用 \code{\link{build_xlsx_from_descriptions}} 完成编译。
#'
#' 本函数封装了路径配置，便于在不同环境下复用。
#' 修改 \code{json_path} 与 \code{out_dir} 即可适配新项目。
#'
#' @param json_path 字符串。JSON 描述文件路径。
#' @param out_dir 字符串。输出目录。
#' @param xlsx_name 字符串。输出文件名。
#' @return 字符串。生成的 XLSX 文件路径。
#' @export
#'
#' @examples
#' \dontrun{
#' compile_module4_results(
#'   json_path = "G:/OmicsWorks/test/metabolism/demo/analysis/4_limma_differential_analysis/table_descriptions.json",
#'   out_dir   = "G:/OmicsWorks/test/metabolism/demo/analysis/4_limma_differential_analysis",
#'   xlsx_name = "4_limma_differential_analysis.xlsx"
#' )
#' }
compile_module4_results <- function(json_path = "G:/OmicsWorks/test/metabolism/demo/analysis/4_limma_differential_analysis/table_descriptions.json",
                                    out_dir   = "G:/OmicsWorks/test/metabolism/demo/analysis/4_limma_differential_analysis",
                                    xlsx_name = "4_limma_differential_analysis.xlsx") {
  build_xlsx_from_descriptions(
    json_path = json_path,
    out_dir   = out_dir,
    xlsx_name = xlsx_name
  )
}

# ---- 8. 执行主流程 ----
# 直接运行本脚本时自动执行；作为 source 引入时不执行。
if (sys.nframe() == 0L) {
  compile_module4_results()
}

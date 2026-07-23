#' @title Load Expression Matrix from CSV File
#'
#' @description
#' 从CSV文件中读取表达矩阵数据。表达矩阵的行代表feature（基因/蛋白/代谢物等），
#' 列代表样本。第一行为样本ID列名，第一列为feature ID。
#'
#' 该函数是OmicsAnalyzer包的基础数据输入函数，所有下游分析模块均接受
#' 该函数返回的表达矩阵作为输入。函数会自动处理行名设置和类型转换。
#'
#' @param file_path 字符串，CSV文件的路径
#' @param sep 字符串，CSV分隔符，默认为","
#' @param quote 字符串，引用字符，默认为"\""
#' @param check_names 逻辑值，是否对列名做语法检查，默认为FALSE以保留原始样本ID
#'
#' @return 返回一个数值矩阵，行名为feature ID，列名为样本ID
#'
#' @examples
#' \dontrun{
#' # 从CSV文件加载表达矩阵
#' expr_matrix <- load_expression_matrix("expression_matrix.csv")
#'
#' # 使用自定义分隔符
#' expr_matrix <- load_expression_matrix("data.txt", sep = "\t")
#'
#' # 查看矩阵维度
#' dim(expr_matrix)
#' head(expr_matrix[, 1:5])
#' }
#'
#' @export
load_expression_matrix <- function(file_path, sep = ",", quote = "\"",
                                   check_names = FALSE) {
  if (!file.exists(file_path)) {
    stop("Input file does not exist: ", file_path)
  }

  raw_data <- utils::read.csv(file_path, sep = sep, quote = quote,
                              check.names = check_names,
                              stringsAsFactors = FALSE)

  if (ncol(raw_data) < 2) {
    stop("Expression matrix must contain at least one sample column and one feature ID column.")
  }

  feature_ids <- as.character(raw_data[, 1])
  sample_ids <- colnames(raw_data)[-1]

  expr_data <- as.matrix(raw_data[, -1])
  rownames(expr_data) <- feature_ids
  colnames(expr_data) <- sample_ids

  mode(expr_data) <- "numeric"

  if (any(is.na(expr_data))) {
    na_count <- sum(is.na(expr_data))
    message("Note: ", na_count, " NA values detected in expression matrix.")
  }

  return(expr_data)
}


#' @title Load Sample Metadata from CSV File
#'
#' @description
#' 从CSV文件中读取样本元数据。元数据文件必须包含以下三列：
#' \itemize{
#'   \item ID: 表达矩阵中的样本ID，用于与表达矩阵对应
#'   \item sample_name: 用于绘图和论文展示的样本显示标签
#'   \item sample_info: 样本的分组标签
#' }
#' 其他列作为补充元数据保留。
#'
#' @param file_path 字符串，CSV文件路径
#' @param sep 字符串，分隔符，默认为","
#'
#' @return 返回一个数据框，包含ID、sample_name、sample_info三列必须字段
#'         以及其他补充元数据列。sample_info列被自动转换为因子。
#'
#' @examples
#' \dontrun{
#' # 加载样本元数据
#' sample_meta <- load_sample_metadata("sample_metadata.csv")
#'
#' # 查看分组信息
#' table(sample_meta$sample_info)
#'
#' # 获取样本显示名称映射
#' name_map <- setNames(sample_meta$sample_name, sample_meta$ID)
#' }
#'
#' @export
load_sample_metadata <- function(file_path, sep = ",") {
  if (!file.exists(file_path)) {
    stop("Input file does not exist: ", file_path)
  }

  meta_data <- utils::read.csv(file_path, sep = sep,
                               stringsAsFactors = FALSE,
                               check.names = FALSE)

  required_cols <- c("ID", "sample_name", "sample_info")
  missing_cols <- setdiff(required_cols, colnames(meta_data))
  if (length(missing_cols) > 0) {
    stop("Sample metadata file is missing required columns: ",
         paste(missing_cols, collapse = ", "))
  }

  meta_data$ID <- as.character(meta_data$ID)
  meta_data$sample_name <- as.character(meta_data$sample_name)
  meta_data$sample_info <- as.factor(meta_data$sample_info)

  return(meta_data)
}


#' @title Load Feature Annotation from CSV File
#'
#' @description
#' 从CSV文件中读取feature注释信息。注释文件必须包含以下四列：
#' \itemize{
#'   \item ID: feature的ID，与表达矩阵第一列对应
#'   \item name: feature的英文俗名
#'   \item type: feature的类别，可能的标签包括：
#'     gene/rna（转录组）、protein（蛋白质组）、metabolite（代谢组）、
#'     lipid（脂质组）、organism/bacterial/taxonomy（微生物组）
#'   \item kegg: KEGG通路注释，用于通路分析
#' }
#' 可选列包括pfam（分号分隔的Pfam结构域集合）和family（分类家族或ontology信息）。
#'
#' @param file_path 字符串，CSV文件路径
#' @param sep 字符串，分隔符，默认为","
#'
#' @return 返回一个数据框，包含ID、name、type、kegg四列必须字段，
#'         以及pfam、family等可选字段。type列被标准化并转为因子。
#'
#' @examples
#' \dontrun{
#' # 加载feature注释
#' feature_anno <- load_feature_annotation("feature_annotation.csv")
#'
#' # 查看feature类型分布
#' table(feature_anno$type)
#'
#' # 标准化feature类型
#' feature_anno$type <- normalize_feature_type(feature_anno$type)
#' }
#'
#' @export
load_feature_annotation <- function(file_path, sep = ",") {
  if (!file.exists(file_path)) {
    stop("Input file does not exist: ", file_path)
  }

  anno_data <- utils::read.csv(file_path, sep = sep,
                               stringsAsFactors = FALSE,
                               check.names = FALSE)

  required_cols <- c("ID", "name", "type", "kegg")
  missing_cols <- setdiff(required_cols, colnames(anno_data))
  if (length(missing_cols) > 0) {
    stop("Feature annotation file is missing required columns: ",
         paste(missing_cols, collapse = ", "))
  }

  anno_data$ID <- as.character(anno_data$ID)
  anno_data$name <- as.character(anno_data$name)
  anno_data$type <- normalize_feature_type(anno_data$type)
  anno_data$kegg <- as.character(anno_data$kegg)

  if ("pfam" %in% colnames(anno_data)) {
    anno_data$pfam <- as.character(anno_data$pfam)
  }
  if ("family" %in% colnames(anno_data)) {
    anno_data$family <- as.character(anno_data$family)
  }

  return(anno_data)
}


#' @title Normalize Feature Type Labels
#'
#' @description
#' 将feature类型标签标准化为统一的类别名称。该函数处理不同别名，
#' 将其映射到标准的组学类型：transcriptome、proteome、metabolome、
#' lipidome、microbiome。
#'
#' 别名映射规则：
#' \itemize{
#'   \item gene, rna -> transcriptome
#'   \item protein -> proteome
#'   \item metabolite -> metabolome
#'   \item lipid -> lipidome
#'   \item organism, bacterial, taxonomy -> microbiome
#' }
#'
#' @param type_vec 字符向量，原始的feature类型标签
#'
#' @return 返回标准化后的因子向量
#'
#' @examples
#' types <- c("gene", "rna", "protein", "metabolite", "organism", "bacterial")
#' normalize_feature_type(types)
#' # Returns: transcriptome transcriptome proteome metabolome microbiome microbiome
#'
#' @export
normalize_feature_type <- function(type_vec) {
  type_vec <- tolower(as.character(type_vec))
  type_vec[is.na(type_vec)] <- "unknown"

  mapping <- c(
    "gene" = "transcriptome",
    "rna" = "transcriptome",
    "protein" = "proteome",
    "metabolite" = "metabolome",
    "lipid" = "lipidome",
    "organism" = "microbiome",
    "bacterial" = "microbiome",
    "taxonomy" = "microbiome"
  )

  normalized <- ifelse(type_vec %in% names(mapping),
                       mapping[type_vec],
                       type_vec)
  return(as.factor(normalized))
}


#' @title Validate Data Consistency Across Three Input Files
#'
#' @description
#' 验证表达矩阵、样本元数据和feature注释文件三者之间的ID一致性。
#' 该函数检查样本ID是否在表达矩阵和元数据之间匹配，
#' feature ID是否在表达矩阵和注释文件之间匹配。
#'
#' @param expr_matrix 数值矩阵，表达矩阵（行：feature，列：样本）
#' @param sample_meta 数据框，样本元数据
#' @param feature_anno 数据框，feature注释信息
#'
#' @return 逻辑值，TRUE表示所有ID均一致，FALSE表示存在不一致
#'
#' @examples
#' \dontrun{
#' expr <- load_expression_matrix("expr.csv")
#' meta <- load_sample_metadata("meta.csv")
#' anno <- load_feature_annotation("anno.csv")
#'
#' if (validate_data_consistency(expr, meta, anno)) {
#'   message("All IDs are consistent.")
#' } else {
#'   warning("ID mismatch detected. Please check your input files.")
#' }
#' }
#'
#' @export
validate_data_consistency <- function(expr_matrix, sample_meta, feature_anno) {
  sample_match <- all(colnames(expr_matrix) %in% sample_meta$ID)
  feature_match <- all(rownames(expr_matrix) %in% feature_anno$ID)

  if (!sample_match) {
    missing_samples <- setdiff(colnames(expr_matrix), sample_meta$ID)
    warning("The following samples in expression matrix are not found in metadata: ",
            paste(missing_samples[1:min(5, length(missing_samples))], collapse = ", "),
            if (length(missing_samples) > 5) " ...")
  }

  if (!feature_match) {
    missing_features <- setdiff(rownames(expr_matrix), feature_anno$ID)
    warning("The following features in expression matrix are not found in annotation: ",
            paste(missing_features[1:min(5, length(missing_features))], collapse = ", "),
            if (length(missing_features) > 5) " ...")
  }

  return(sample_match && feature_match)
}


#' @title Save Analysis Result to CSV File
#'
#' @description
#' 将分析结果保存为CSV文件，方便后续查看和共享。
#' 该函数自动处理行名和列名的写入。
#'
#' @param data 数据框或矩阵，待保存的数据
#' @param file_path 字符串，输出文件路径
#' @param row_name_col 字符串，行名列的列名，默认为"ID"
#'
#' @return 不可见地返回输出文件路径
#'
#' @examples
#' \dontrun{
#' # 保存差异分析结果
#' save_result_table(dea_result, "/path/to/dea_result.csv")
#' }
#'
#' @export
save_result_table <- function(data, file_path, row_name_col = "ID") {
  if (is.matrix(data)) {
    data <- as.data.frame(data)
  }

  if (!is.null(rownames(data))) {
    data <- cbind(setNames(data.frame(rownames(data), stringsAsFactors = FALSE),
                            row_name_col), data)
    rownames(data) <- NULL
  }

  utils::write.csv(data, file_path, row.names = FALSE)
  message("Result saved to: ", file_path)
  invisible(file_path)
}

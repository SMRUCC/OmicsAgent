# =============================================================================
# transform.R
# -----------------------------------------------------------------------------
# 数值尺度变换工具：将原始线性尺度（绝对强度/计数）转换为对数尺度，
# 以便后续差异分析（limma logFC 语义）与多元分析（距离度量）正确进行。
#
# 设计要点：
#   - 兼容 matrix / data.frame，统一返回 matrix；
#   - 对 0 或负值自动加伪计数，避免 log(<=0) 产生 -Inf/NaN。
# =============================================================================

#' 对表达/丰度矩阵做 log2(x + pseudo_count) 变换
#'
#' @param expr_matrix 数值矩阵或 data.frame（行=特征，列=样本）
#' @param pseudo_count 伪计数，默认 1（避免 log(0)）
#' @param base 对数底，默认 2（log2）。可选 10 或 exp(1)
#' @return 与输入同维度的 numeric matrix
log2_transform <- function(expr_matrix, pseudo_count = 1, base = 2) {
  if (!is.matrix(expr_matrix)) {
    expr_matrix <- as.matrix(expr_matrix)
    mode(expr_matrix) <- "numeric"
  }
  if (!is.numeric(expr_matrix)) {
    stop("log2_transform: expr_matrix 必须为数值矩阵或 data.frame。")
  }
  if (any(is.na(expr_matrix))) {
    warning("log2_transform: 输入含 NA，变换将保留 NA（建议在变换前完成缺失值填补/过滤）。")
  }
  shifted <- expr_matrix + pseudo_count
  if (base == 2) {
    out <- log2(shifted)
  } else if (base == 10) {
    out <- log10(shifted)
  } else if (base == exp(1) || tolower(base) == "e") {
    out <- log(shifted)
  } else {
    stop("log2_transform: base 仅支持 2 / 10 / e。")
  }
  out
}

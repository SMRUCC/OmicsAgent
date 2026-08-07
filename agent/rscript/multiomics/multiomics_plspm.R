# ==============================================================================
# OmicsFlow：分层多组学 PLS 路径建模（PLS-PM）
# ==============================================================================
# 从生物学注释（EC 编号、KEGG 通路映射、化合物类别、微生物分类学）构建潜变量，
# 并用 plspm 包求解的 PLS 路径模型将它们在组学层级间连接起来。
#
# 典型流程：
#   1. build_multiomics_latent_def()     注释 -> 潜变量块
#   2. build_hierarchical_inner_model()  层排序 -> 下三角路径矩阵
#   3. run_multiomics_plspm()            求解并展开结果
#   4. summarise_plspm_paths()           逐层路径汇总
#
# 与 network/plspm_net.R 中简化的 run_plspm()（PCA 分数加两两 lm）不同，本模块
# 调用 plspm::plspm()，从而联合估计权重、载荷与路径Coefficient。
# ==============================================================================


# ------------------------------------------------------------------------------
# 注释辅助函数
# ------------------------------------------------------------------------------

#' 将 EC 编号规范化并截断到指定层级
#'
#' @description 注释表中的酶学委员会（EC）编号以文本前缀形式存储（如
#'   \code{"EC 1.13.11.71"}）。完整的 EC 编号过于细碎，无法构成可用的潜变量块，
#'   因此将标识符清洗并截断到前 \code{level} 个分量，从而把酶归入有意义的功能类别。
#'
#' @param x 原始 EC 注释的字符向量。
#' @param level 保留的 EC 分量数。默认：2（如 "1.13"）。
#'
#' @return 截断后 EC 类别的字符向量，输入不含可用 EC 编号处为 \code{NA}。
#'
#' @examples
#' \dontrun{
#' clean_ec_number(c("EC 1.13.11.71", "EC 2.7.1.1"), level = 2)
#' # -> c("1.13", "2.7")
#' }
#'
#' @export
clean_ec_number <- function(x, level = 2) {
  x <- as.character(x)
  x <- trimws(gsub("^\\s*EC[:\\s]*", "", x, ignore.case = TRUE, perl = TRUE))
  x[is.na(x) | x == "" | tolower(x) %in% c("na", "-", "none")] <- NA_character_

  keep <- !is.na(x)
  if (any(keep)) {
    parts <- strsplit(x[keep], ".", fixed = TRUE)
    x[keep] <- vapply(parts, function(p) {
      p <- p[p != "" & p != "-"]
      if (length(p) == 0) return(NA_character_)
      paste(p[seq_len(min(level, length(p)))], collapse = ".")
    }, character(1))
  }
  x
}


#' 解析单个组学层的分组向量
#'
#' @param finfo Feature注释 data.frame（行名 = 矩阵行名）。
#' @param features 表达矩阵中出现的Feature ID。
#' @param source 注释列的名称，或 "ec_number" / "kegg"。
#' @param ec_level EC 截断层级。
#'
#' @return 与 \code{features} 对齐的字符向量，不可用处为 NA。
#'
#' @keywords internal
.plspm_group_vector <- function(finfo, features, source, ec_level = 2) {
  if (is.null(finfo) || !source %in% colnames(finfo)) return(NULL)
  vals <- as.character(finfo[[source]])[match(features, rownames(finfo))]
  if (identical(source, "ec_number")) {
    vals <- clean_ec_number(vals, level = ec_level)
  }
  vals[is.na(vals) | vals == "" |
         tolower(vals) %in% c("na", "unknown", "-", "none")] <- NA_character_
  vals
}


#' 候选注释列的覆盖率
#'
#' @param v 由 \code{.plspm_group_vector()} 返回的字符向量。
#'
#' @return 非缺失项所占比例，取值 [0, 1]。
#'
#' @keywords internal
.plspm_coverage <- function(v) {
  if (is.null(v) || length(v) == 0) return(0)
  sum(!is.na(v)) / length(v)
}


# ------------------------------------------------------------------------------
# 潜变量构建
# ------------------------------------------------------------------------------

#' 基于注释构建多组学潜变量定义
#'
#' @description 利用生物学注释，将每个组学层的Feature分组为潜变量。每层可使用不同的
#'   分组来源，这是必需的，因为各层携带的元数据不同：转录组与蛋白质组有 EC 编号
#'   和 KEGG 直系同源，代谢组与挥发组有化合物类别，而 16S 层只有分类学信息。
#'
#'   当所请求的来源覆盖率较低时，函数会自动回退到下一个可用列，而非失败，
#'   因此仅当完全无任何可用注释时层才会被跳过。
#'
#' @param mo 一个 MultiOmicsData 对象。
#' @param layer_sources 映射层名到用于分组的注释列的有名列表，例如
#'   \code{list(transcriptome = "ec_number", metabolome = "super_class",
#'   microbiome = "taxonomy_phylum")}。
#' @param min_size 每个潜变量的最小Feature数。默认：3。
#' @param max_latent_per_layer 每层保留的潜变量数量上限，按总方差选取。默认：NULL（无上限）。
#' @param max_features_per_latent 每个潜变量的显变量数量上限，按方差选取。默认：15。
#' @param ec_level EC 截断层级。默认：2。
#' @param fallback_sources 当所请求来源覆盖率不足时尝试的列。
#' @param min_coverage 接受某来源所需的最小注释Feature比例。默认：0.2。
#' @param verbose 是否打印进度。默认：TRUE。
#'
#' @return 一个列表：
#'   \itemize{
#'     \item \code{latent_def}: latent -> Feature ID 的有名列表。
#'     \item \code{definitions}: 含 \code{latent}、\code{layer}、
#'       \code{source}、\code{group}、\code{n_features} 的数据框。
#'     \item \code{layer_sources_used}: 每层实际使用的来源。
#'   }
#'
#' @examples
#' \dontrun{
#' lat <- build_multiomics_latent_def(
#'   mo, list(transcriptome = "ec_number", metabolome = "super_class"))
#' }
#'
#' @export
build_multiomics_latent_def <- function(mo, layer_sources, min_size = 3,
                                        max_latent_per_layer = NULL,
                                        max_features_per_latent = 15,
                                        ec_level = 2,
                                        fallback_sources = c("super_class",
                                                             "class", "family",
                                                             "taxonomy_phylum",
                                                             "kegg"),
                                        min_coverage = 0.2, verbose = TRUE) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }

  latent_def <- list()
  def_rows <- list()
  used_sources <- character(0)

  for (nm in names(layer_sources)) {
    if (!nm %in% names(mo$omics)) {
      if (verbose) cat(sprintf("  [plspm] layer '%s' not found, skipped.\n", nm))
      next
    }
    mat <- get_omics_matrix(mo, nm)
    finfo <- get_feature_info(mo, nm)
    feats <- rownames(mat)

    # 选择覆盖率达标的第一个来源 --------------------------
    candidates <- unique(c(layer_sources[[nm]], fallback_sources))
    chosen <- NULL
    grp <- NULL
    for (src in candidates) {
      v <- .plspm_group_vector(finfo, feats, src, ec_level = ec_level)
      if (.plspm_coverage(v) >= min_coverage) {
        chosen <- src
        grp <- v
        break
      }
    }
    if (is.null(chosen)) {
      if (verbose) {
        cat(sprintf("  [plspm] layer '%-14s' skipped: no annotation column with >=%.0f%% coverage.\n",
                    nm, 100 * min_coverage))
      }
      next
    }
    if (verbose && !identical(chosen, layer_sources[[nm]])) {
      cat(sprintf("  [plspm] layer '%-14s' fell back from '%s' to '%s'.\n",
                  nm, layer_sources[[nm]], chosen))
    }
    used_sources[nm] <- chosen

    vars <- apply(mat, 1, stats::var, na.rm = TRUE)
    vars[is.na(vars)] <- 0

    groups <- split(feats, grp)
    groups <- groups[vapply(groups, length, integer(1)) >= min_size]
    if (length(groups) == 0) {
      if (verbose) {
        cat(sprintf("  [plspm] layer '%-14s' skipped: no group reaches min_size=%d.\n",
                    nm, min_size))
      }
      next
    }

    # 保留变异最大的块，以及每个块内变异最大的成员 --
    if (!is.null(max_latent_per_layer) &&
        length(groups) > max_latent_per_layer) {
      gv <- vapply(groups, function(f) sum(vars[f], na.rm = TRUE), numeric(1))
      groups <- groups[order(gv, decreasing = TRUE)[
        seq_len(max_latent_per_layer)]]
    }
    groups <- lapply(groups, function(f) {
      if (length(f) <= max_features_per_latent) return(f)
      f[order(vars[f], decreasing = TRUE)[seq_len(max_features_per_latent)]]
    })

    tag <- toupper(substr(nm, 1, 3))
    for (g in names(groups)) {
      lname <- make.names(paste(tag, g, sep = "_"))
      lname <- gsub("\\.+", "_", lname)
      lname <- make.unique(c(names(latent_def), lname))[length(latent_def) + 1]
      latent_def[[lname]] <- groups[[g]]
      def_rows[[length(def_rows) + 1]] <- data.frame(
        latent = lname, layer = nm, source = chosen, group = g,
        n_features = length(groups[[g]]), stringsAsFactors = FALSE)
    }
    if (verbose) {
      cat(sprintf("  [plspm] layer '%-14s' -> %2d latent variable(s) from '%s'\n",
                  nm, length(groups), chosen))
    }
  }

  if (length(latent_def) == 0) {
    stop("No latent variable could be constructed; relax min_size or min_coverage.")
  }

  definitions <- do.call(rbind, def_rows)
  rownames(definitions) <- NULL

  list(latent_def = latent_def, definitions = definitions,
       layer_sources_used = used_sources)
}


# ------------------------------------------------------------------------------
# 分层内模型
# ------------------------------------------------------------------------------

#' 为分层 PLS 路径模型构建下三角内模型矩阵
#'
#' @description 按各潜变量所属组学层的生物学层级对它们排序，并将每个潜变量连接到
#'   所有下游层的潜变量。plspm 要求下三角路径矩阵，而此排序恰好保证这一点。
#'
#' @param definitions 由 \code{build_multiomics_latent_def()} 生成的 \code{definitions}
#'   数据框。
#' @param layer_order 层的字符向量，最上游在前。
#' @param allow_within_layer 同一层的潜变量是否允许相连。默认：FALSE。
#' @param adjacent_only 是否仅连接到 \code{layer_order} 中的下一层，而非所有下游层。
#'   默认：FALSE。
#'
#' @return 一个列表，含 \code{path_matrix}（下三角 0/1 矩阵）与
#'   重新排序以匹配其行顺序的 \code{definitions}。
#'
#' @examples
#' \dontrun{
#' im <- build_hierarchical_inner_model(
#'   lat$definitions,
#'   c("microbiome", "transcriptome", "proteome", "metabolome", "volatilome"))
#' }
#'
#' @export
build_hierarchical_inner_model <- function(definitions, layer_order,
                                           allow_within_layer = FALSE,
                                           adjacent_only = FALSE) {
  if (is.null(definitions) || nrow(definitions) == 0) {
    stop("definitions must be a non-empty data.frame.")
  }
  layer_order <- layer_order[layer_order %in% unique(definitions$layer)]
  extra <- setdiff(unique(definitions$layer), layer_order)
  layer_order <- c(layer_order, extra)
  if (length(layer_order) == 0) stop("No layer in definitions matches layer_order.")

  rank_of <- stats::setNames(seq_along(layer_order), layer_order)
  definitions$layer_rank <- rank_of[definitions$layer]
  definitions <- definitions[order(definitions$layer_rank, definitions$latent), ,
                             drop = FALSE]
  rownames(definitions) <- NULL

  lv <- definitions$latent
  k <- length(lv)
  if (k < 2) stop("At least 2 latent variables are required for a path model.")

  pm <- matrix(0L, nrow = k, ncol = k, dimnames = list(lv, lv))
  lr <- definitions$layer_rank

  for (j in seq_len(k)) {       # predictor (upstream)
    for (i in seq_len(k)) {     # outcome (downstream)
      if (i <= j) next          # keep strictly lower triangular
      same <- lr[i] == lr[j]
      if (same && !allow_within_layer) next
      if (!same && adjacent_only && (lr[i] - lr[j]) != 1) next
      pm[i, j] <- 1L
    }
  }

  list(path_matrix = pm, definitions = definitions)
}


# ------------------------------------------------------------------------------
# 求解路径模型
# ------------------------------------------------------------------------------

#' 拟合分层多组学 PLS 路径模型
#'
#' @description 从所有组学层汇总为一张样本 x 显变量的宽表，将每个潜变量映射到其列索引，
#'   并用 \code{plspm::plspm()} 求解路径模型。零方差与重复的显变量会事先移除，
#'   因为它们会使 PLS 算法不稳定。
#'
#' @param mo 一个 MultiOmicsData 对象。
#' @param latent_def latent -> Feature ID 的有名列表。
#' @param definitions 定义数据框，已按 \code{path_matrix} 排序（即由
#'   \code{build_hierarchical_inner_model()} 返回者）。
#' @param path_matrix 下三角 0/1 内模型矩阵。
#' @param scale 是否对显变量标准化。默认：TRUE。
#' @param boot_val 是否运行自助法验证。默认：FALSE。
#' @param br 当 \code{boot_val} 为 TRUE 时的自助重采样次数。默认：100。
#' @param min_block_size 清洗后每块的最小显变量数。默认：2。
#' @param verbose 是否打印进度。默认：TRUE。
#'
#' @return 一个列表，含 \code{model}、\code{inner_paths}、\code{outer_loadings}、
#'   \code{scores}、\code{fit_summary}、\code{effects}、\code{gof} 与
#'   \code{definitions}。
#'
#' @examples
#' \dontrun{
#' res <- run_multiomics_plspm(mo, lat$latent_def, im$definitions,
#'                             im$path_matrix)
#' }
#'
#' @export
run_multiomics_plspm <- function(mo, latent_def, definitions, path_matrix,
                                 scale = TRUE, boot_val = FALSE, br = 100,
                                 min_block_size = 2, verbose = TRUE) {
  if (!requireNamespace("plspm", quietly = TRUE)) {
    stop("Package 'plspm' is required for PLS path modelling.")
  }
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }

  lv <- rownames(path_matrix)
  definitions <- definitions[match(lv, definitions$latent), , drop = FALSE]

  # --- collect the manifest variables of every latent block -----------------
  samples <- mo$common_samples
  cols <- list()
  blocks <- list()
  block_layer <- character(0)
  col_counter <- 0L
  keep_lv <- character(0)

  for (i in seq_along(lv)) {
    l <- lv[i]
    layer <- definitions$layer[i]
    feats <- latent_def[[l]]
    if (is.null(feats) || length(feats) == 0) next

    mat <- tryCatch(get_omics_matrix(mo, layer), error = function(e) NULL)
    if (is.null(mat)) next
    feats <- intersect(feats, rownames(mat))
    if (length(feats) < min_block_size) next

    sub <- t(mat[feats, samples, drop = FALSE])   # samples x features
    v <- apply(sub, 2, stats::var, na.rm = TRUE)
    sub <- sub[, !is.na(v) & v > 0, drop = FALSE]
    if (ncol(sub) < min_block_size) next

    colnames(sub) <- paste(l, seq_len(ncol(sub)), sep = "__")
    idx <- col_counter + seq_len(ncol(sub))
    col_counter <- col_counter + ncol(sub)

    cols[[l]] <- sub
    blocks[[l]] <- idx
    block_layer[l] <- layer
    keep_lv <- c(keep_lv, l)
  }

  if (length(keep_lv) < 2) {
    stop("Fewer than 2 usable latent blocks remain after cleaning.")
  }

  # --- restrict the path matrix to the surviving latent variables -----------
  pm <- path_matrix[keep_lv, keep_lv, drop = FALSE]
  # 丢弃最终孤立的潜变量
  connected <- (rowSums(pm) + colSums(pm)) > 0
  if (sum(connected) < 2) {
    stop("The inner model has fewer than 2 connected latent variables.")
  }
  if (any(!connected)) {
    keep_lv <- keep_lv[connected]
    pm <- pm[keep_lv, keep_lv, drop = FALSE]
  }

  # --- assemble the wide table and the block column indices ----------------
  offset <- 0L
  reindexed <- list()
  for (l in keep_lv) {
    n <- ncol(cols[[l]])
    reindexed[[l]] <- offset + seq_len(n)
    offset <- offset + n
  }
  wide <- as.data.frame(do.call(cbind, cols[keep_lv]), stringsAsFactors = FALSE)
  colnames(wide) <- make.unique(make.names(colnames(wide)))

  definitions <- definitions[match(keep_lv, definitions$latent), , drop = FALSE]
  rownames(definitions) <- NULL

  if (verbose) {
    cat(sprintf("  [plspm] fitting model: %d latent variable(s), %d manifest variable(s), %d sample(s)\n",
                length(keep_lv), ncol(wide), nrow(wide)))
  }

  model <- plspm::plspm(Data = wide, path_matrix = pm,
                        blocks = unname(reindexed[keep_lv]),
                        modes = rep("A", length(keep_lv)),
                        scaled = scale, boot.val = boot_val, br = br)

  layer_of <- stats::setNames(definitions$layer, definitions$latent)

  # --- flatten the inner model ---------------------------------------------
  inner_rows <- list()
  im <- model$inner_model
  for (target in names(im)) {
    tb <- as.data.frame(im[[target]], stringsAsFactors = FALSE)
    tb$from <- rownames(tb)
    tb <- tb[tb$from != "Intercept", , drop = FALSE]
    if (nrow(tb) == 0) next
    inner_rows[[target]] <- data.frame(
      from = tb$from,
      to = target,
      from_layer = unname(layer_of[tb$from]),
      to_layer = unname(layer_of[target]),
      path_coeff = as.numeric(tb[["Estimate"]]),
      std_error = as.numeric(tb[["Std. Error"]]),
      t_value = as.numeric(tb[["t value"]]),
      p_value = as.numeric(tb[["Pr(>|t|)"]]),
      stringsAsFactors = FALSE)
  }
  inner_paths <- if (length(inner_rows) > 0) do.call(rbind, inner_rows) else
    data.frame(from = character(0), to = character(0),
               from_layer = character(0), to_layer = character(0),
               path_coeff = numeric(0), std_error = numeric(0),
               t_value = numeric(0), p_value = numeric(0),
               stringsAsFactors = FALSE)
  if (nrow(inner_paths) > 0) {
    inner_paths$significant <- inner_paths$p_value < 0.05
    inner_paths$edge_type <- ifelse(
      inner_paths$from_layer == inner_paths$to_layer,
      "within_layer", "cross_layer")
    inner_paths <- inner_paths[order(-abs(inner_paths$path_coeff)), ,
                               drop = FALSE]
    rownames(inner_paths) <- NULL
  }

  # --- outer model ----------------------------------------------------------
  outer <- as.data.frame(model$outer_model, stringsAsFactors = FALSE)
  outer$latent <- as.character(outer$block)
  outer$layer <- unname(layer_of[outer$latent])
  rownames(outer) <- NULL

  # --- fit summary ----------------------------------------------------------
  isum <- as.data.frame(model$inner_summary, stringsAsFactors = FALSE)
  isum$latent <- rownames(isum)
  isum$layer <- unname(layer_of[isum$latent])
  uni <- as.data.frame(model$unidim, stringsAsFactors = FALSE)
  if (!is.null(uni) && nrow(uni) > 0) {
    isum$n_manifest <- uni[["MVs"]][match(isum$latent, rownames(uni))]
    isum$cronbach_alpha <- round(uni[["C.alpha"]][match(isum$latent,
                                                        rownames(uni))], 4)
    isum$dillon_goldstein_rho <- round(uni[["DG.rho"]][match(isum$latent,
                                                             rownames(uni))], 4)
  }
  isum$gof <- round(as.numeric(model$gof), 4)
  rownames(isum) <- NULL

  scores <- as.data.frame(model$scores, stringsAsFactors = FALSE)
  rownames(scores) <- rownames(wide)

  effects <- tryCatch(as.data.frame(model$effects, stringsAsFactors = FALSE),
                      error = function(e) NULL)

  if (verbose) {
    n_sig <- sum(inner_paths$significant, na.rm = TRUE)
    cat(sprintf("  [plspm] %d path(s), %d significant (p<0.05), GoF = %.4f\n",
                nrow(inner_paths), n_sig, as.numeric(model$gof)))
  }

  list(model = model, inner_paths = inner_paths, outer_loadings = outer,
       scores = scores, fit_summary = isum, effects = effects,
       gof = as.numeric(model$gof), path_matrix = pm,
       definitions = definitions)
}


#' 按层间转移汇总 PLS 路径模型结果
#'
#' @description 汇总 PLS-PM 路径分析的所有路径系数、效应和显著性。
#'
#' @param plspm_result \code{run_multiomics_plspm()} 的输出。
#' @param p_threshold 显著性阈值。默认：0.05。
#'
#' @return 每个 (from_layer, to_layer) 转移一行数据框。
#'
#' @examples
#' \dontrun{
#' summarise_plspm_paths(res)
#' }
#'
#' @export
summarise_plspm_paths <- function(plspm_result, p_threshold = 0.05) {
  ip <- plspm_result$inner_paths
  if (is.null(ip) || nrow(ip) == 0) return(NULL)

  key <- paste(ip$from_layer, ip$to_layer, sep = " -> ")
  rows <- lapply(split(seq_len(nrow(ip)), key), function(idx) {
    s <- ip[idx, , drop = FALSE]
    data.frame(
      transition = paste(s$from_layer[1], s$to_layer[1], sep = " -> "),
      from_layer = s$from_layer[1],
      to_layer = s$to_layer[1],
      n_paths = nrow(s),
      n_significant = sum(s$p_value < p_threshold, na.rm = TRUE),
      mean_path_coeff = round(mean(s$path_coeff, na.rm = TRUE), 4),
      mean_abs_path_coeff = round(mean(abs(s$path_coeff), na.rm = TRUE), 4),
      max_abs_path_coeff = round(max(abs(s$path_coeff), na.rm = TRUE), 4),
      n_positive = sum(s$path_coeff > 0, na.rm = TRUE),
      n_negative = sum(s$path_coeff < 0, na.rm = TRUE),
      stringsAsFactors = FALSE)
  })

  out <- do.call(rbind, rows)
  out <- out[order(-out$n_significant, -out$mean_abs_path_coeff), ,
             drop = FALSE]
  rownames(out) <- NULL
  out
}

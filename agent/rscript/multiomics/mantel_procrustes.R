# ==============================================================================
# OmicsFlow：组学层之间的矩阵级一致性分析
# ==============================================================================
# 通过 Mantel 检验与 Procrustes 分析，量化不同组学层以及环境因子对相同样本的
# 排序一致程度。
# ==============================================================================

#' 为一组组学矩阵计算样本距离矩阵
#'
#' @description 为每个组学层构建一个样本对样本的距离矩阵。距离在样本空间上
#'   计算，因此开销与特征数量无关，可以安全地使用全部特征集。所得列表会被
#'   Mantel、Procrustes 与排序函数复用。
#'
#' @param mat_list 数值矩阵的有名列表（特征 x 样本）。
#' @param method 距离方法。"bray" 需要 vegan 包且数据非负；\code{stats::dist()}
#'   支持的任何方法亦可使用。默认："euclidean"。
#' @param verbose 逻辑值，是否打印进度。默认：TRUE。
#'
#' @return 一个 \code{dist} 对象的有名列表，每个组学层对应一个。
#'
#' @examples
#' \dontrun{
#' dists <- compute_omics_distances(get_omics_list(mo), method = "euclidean")
#' }
#'
#' @export
compute_omics_distances <- function(mat_list, method = "euclidean",
                                    verbose = TRUE) {
  if (!is.list(mat_list) || length(mat_list) == 0) {
    stop("mat_list must be a non-empty named list of matrices.")
  }
  if (method == "bray" && !requireNamespace("vegan", quietly = TRUE)) {
    stop("Package 'vegan' is required for Bray-Curtis distances. ",
         "Install it with install.packages('vegan').")
  }

  out <- lapply(names(mat_list), function(nm) {
    mat <- mat_list[[nm]]
    samples_by_features <- t(mat)

    d <- if (method == "bray") {
      m <- samples_by_features
      if (any(m < 0, na.rm = TRUE)) {
        cat(sprintf("[mantel] layer '%s' contains negative values; shifting for Bray-Curtis.\n",
                    nm))
        m <- m - min(m, na.rm = TRUE)
      }
      vegan::vegdist(m, method = "bray")
    } else {
      stats::dist(samples_by_features, method = method)
    }

    if (verbose) {
      cat(sprintf("[mantel] distance matrix for '%s': %d samples (%s)\n",
                  nm, attr(d, "Size"), method))
    }
    d
  })
  names(out) <- names(mat_list)
  return(out)
}


#' 组学层之间及与环境因子的 Mantel 检验
#'
#' @description 检验成对的组学层是否以一致的方式对样本排序，以及该排序是否匹配
#'   温度、湿度或海拔等环境梯度。基于样本距离矩阵运算，因此运行时间与特征数量
#'   无关。
#'
#' @param mat_list 数值矩阵的有名列表（特征 x 样本），或为已计算好的 \code{dist}
#'   对象的有名列表。
#' @param env_data 可选的数据框，包含以样本为行的数值型环境变量。每个变量会被
#'   转换为欧氏距离矩阵，并与每个组学层进行检验。默认：NULL。
#' @param dist_method 组学层的距离方法。默认："euclidean"。
#' @param env_dist_method 环境变量的距离方法。默认："euclidean"。
#' @param method Mantel 相关方法。默认："pearson"。
#' @param permutations 置换次数。默认：999。
#' @param verbose 逻辑值，是否打印进度。默认：TRUE。
#'
#' @return 一个列表：
#'   \itemize{
#'     \item \code{omics_omics}: 数据框，含 layer_x、layer_y、mantel_r、
#'       p_value、significance。
#'     \item \code{omics_env}: 数据框，含 layer、variable、mantel_r、
#'       p_value、significance（env_data 为 NULL 时为空）。
#'     \item \code{distances}: 所用的距离矩阵。
#'   }
#'
#' @examples
#' \dontrun{
#' env <- mo$sample_info[, c("temperature_C", "humidity_pct", "altitude_m")]
#' res <- run_mantel_test(get_omics_list(mo), env_data = env)
#' }
#'
#' @export
run_mantel_test <- function(mat_list, env_data = NULL,
                            dist_method = "euclidean",
                            env_dist_method = "euclidean",
                            method = "pearson",
                            permutations = 999,
                            verbose = TRUE) {
  if (!requireNamespace("vegan", quietly = TRUE)) {
    stop("Package 'vegan' is required for Mantel tests. ",
         "Install it with install.packages('vegan').")
  }
  if (!is.list(mat_list) || length(mat_list) < 1) {
    stop("mat_list must be a non-empty named list.")
  }

  # 接受原始矩阵或预计算的距离
  is_dist <- vapply(mat_list, function(x) inherits(x, "dist"), logical(1))
  if (all(is_dist)) {
    dists <- mat_list
  } else if (!any(is_dist)) {
    dists <- compute_omics_distances(mat_list, method = dist_method,
                                     verbose = verbose)
  } else {
    stop("mat_list must contain either only matrices or only dist objects.")
  }

  layer_names <- names(dists)

  # --- omics vs omics --------------------------------------------------------
  omics_omics <- data.frame(
    layer_x = character(0), layer_y = character(0),
    mantel_r = numeric(0), p_value = numeric(0),
    stringsAsFactors = FALSE
  )

  if (length(layer_names) >= 2) {
    combos <- utils::combn(layer_names, 2, simplify = FALSE)
    for (cb in combos) {
      res <- tryCatch({
        vegan::mantel(dists[[cb[1]]], dists[[cb[2]]],
                      method = method, permutations = permutations)
      }, error = function(e) {
        cat(sprintf("[mantel] %s vs %s failed: %s\n",
                    cb[1], cb[2], conditionMessage(e)))
        NULL
      })
      if (is.null(res)) next

      omics_omics <- rbind(omics_omics, data.frame(
        layer_x = cb[1], layer_y = cb[2],
        mantel_r = as.numeric(res$statistic),
        p_value = as.numeric(res$signif),
        stringsAsFactors = FALSE
      ))
      if (verbose) {
        cat(sprintf("[mantel] %-14s vs %-14s r = %6.3f, p = %.3f\n",
                    cb[1], cb[2], res$statistic, res$signif))
      }
    }
  }

  # --- omics vs environment --------------------------------------------------
  omics_env <- data.frame(
    layer = character(0), variable = character(0),
    mantel_r = numeric(0), p_value = numeric(0),
    stringsAsFactors = FALSE
  )

  if (!is.null(env_data)) {
    env_data <- as.data.frame(env_data)
    numeric_cols <- names(env_data)[vapply(env_data, is.numeric, logical(1))]
    if (length(numeric_cols) == 0) {
      cat("[mantel] env_data contains no numeric column; skipping env tests.\n")
    }

    ref_labels <- labels(dists[[1]])

    for (vr in numeric_cols) {
      vals <- env_data[[vr]]
      names(vals) <- rownames(env_data)
      vals <- vals[ref_labels]

      if (all(is.na(vals)) || stats::var(vals, na.rm = TRUE) == 0) {
        cat(sprintf("[mantel] variable '%s' is constant or missing; skipped.\n", vr))
        next
      }

      env_dist <- stats::dist(matrix(vals, ncol = 1,
                                     dimnames = list(ref_labels, vr)),
                              method = env_dist_method)

      for (nm in layer_names) {
        res <- tryCatch({
          vegan::mantel(dists[[nm]], env_dist,
                        method = method, permutations = permutations)
        }, error = function(e) {
          cat(sprintf("[mantel] %s vs %s failed: %s\n",
                      nm, vr, conditionMessage(e)))
          NULL
        })
        if (is.null(res)) next

        omics_env <- rbind(omics_env, data.frame(
          layer = nm, variable = vr,
          mantel_r = as.numeric(res$statistic),
          p_value = as.numeric(res$signif),
          stringsAsFactors = FALSE
        ))
        if (verbose) {
          cat(sprintf("[mantel] %-14s vs %-14s r = %6.3f, p = %.3f\n",
                      nm, vr, res$statistic, res$signif))
        }
      }
    }
  }

  if (nrow(omics_omics) > 0) {
    omics_omics$significance <- .significance_stars(omics_omics$p_value)
  }
  if (nrow(omics_env) > 0) {
    omics_env$significance <- .significance_stars(omics_env$p_value)
  }

  return(list(
    omics_omics = omics_omics,
    omics_env = omics_env,
    distances = dists
  ))
}


#' 显著性星号辅助函数
#'
#' @param p p 值的数值向量。
#'
#' @return 显著性标记的代码字符向量。
#'
#' @keywords internal
.significance_stars <- function(p) {
  out <- rep("ns", length(p))
  out[!is.na(p) & p <= 0.05] <- "*"
  out[!is.na(p) & p <= 0.01] <- "**"
  out[!is.na(p) & p <= 0.001] <- "***"
  out
}


#' 两个组学层之间的 Procrustes 分析
#'
#' @description 将一个组学层的排序旋转到另一个组学层之上，并用 PROTEST 检验两者
#'   一致性的显著性。返回叠加后的坐标，以便绘制逐样本残差。
#'
#' @param mat_x 第一层的数值矩阵（特征 x 样本），或 \code{dist} 对象。
#' @param mat_y 第二层的数值矩阵（特征 x 样本），或 \code{dist} 对象。
#' @param dist_method 传入矩阵时所用的距离方法。默认："euclidean"。
#' @param ncomp 保留的排序轴数量。默认：2。
#' @param permutations PROTEST 的置换次数。默认：999。
#' @param name_x 第一层的标签。默认："x"。
#' @param name_y 第二层的标签。默认："y"。
#' @param verbose 逻辑值，是否打印进度。默认：TRUE。
#'
#' @return 一个列表：
#'   \itemize{
#'     \item \code{procrustes}: vegan 的 procrustes 对象。
#'     \item \code{protest}: PROTEST 结果。
#'     \item \code{ss}: Procrustes 残差平方和。
#'     \item \code{correlation}: Procrustes 相关系数。
#'     \item \code{p_value}: 置换 p 值。
#'     \item \code{coordinates}: 含 sample、x1、y1、x2、y2 与
#'       residual 的数据框，可直接用于绘图。
#'   }
#'
#' @examples
#' \dontrun{
#' proc <- run_procrustes(get_omics_matrix(mo, "microbiome"),
#'                        get_omics_matrix(mo, "metabolome"))
#' }
#'
#' @export
run_procrustes <- function(mat_x, mat_y,
                           dist_method = "euclidean",
                           ncomp = 2,
                           permutations = 999,
                           name_x = "x",
                           name_y = "y",
                           verbose = TRUE) {
  if (!requireNamespace("vegan", quietly = TRUE)) {
    stop("Package 'vegan' is required for Procrustes analysis. ",
         "Install it with install.packages('vegan').")
  }

  dx <- if (inherits(mat_x, "dist")) mat_x else
    stats::dist(t(as.matrix(mat_x)), method = dist_method)
  dy <- if (inherits(mat_y, "dist")) mat_y else
    stats::dist(t(as.matrix(mat_y)), method = dist_method)

  common <- intersect(labels(dx), labels(dy))
  if (length(common) < 3) {
    stop("At least 3 shared samples are required for Procrustes analysis.")
  }

  pcoa_x <- stats::cmdscale(dx, k = ncomp)
  pcoa_y <- stats::cmdscale(dy, k = ncomp)
  pcoa_x <- pcoa_x[common, , drop = FALSE]
  pcoa_y <- pcoa_y[common, , drop = FALSE]

  proc <- vegan::procrustes(pcoa_x, pcoa_y, symmetric = TRUE)
  prot <- vegan::protest(pcoa_x, pcoa_y, permutations = permutations)

  # residuals() 是 vegan 注册的 S3 方法，而非导出对象，
  # 因此必须通过 stats 中的泛型进行分发。
  resid <- stats::residuals(proc)

  coords <- data.frame(
    sample = common,
    x1 = proc$X[, 1],
    y1 = if (ncomp >= 2) proc$X[, 2] else 0,
    x2 = proc$Yrot[, 1],
    y2 = if (ncomp >= 2) proc$Yrot[, 2] else 0,
    residual = as.numeric(resid),
    stringsAsFactors = FALSE
  )
  rownames(coords) <- NULL

  if (verbose) {
    cat(sprintf("[procrustes] %s vs %s: SS = %.4f, corr = %.3f, p = %.3f\n",
                name_x, name_y, proc$ss, prot$scale, prot$signif))
  }

  return(list(
    procrustes = proc,
    protest = prot,
    ss = as.numeric(proc$ss),
    correlation = as.numeric(prot$t0),
    p_value = as.numeric(prot$signif),
    coordinates = coords,
    params = list(name_x = name_x, name_y = name_y, ncomp = ncomp)
  ))
}


#' 对多个层对运行 Procrustes 分析
#'
#' @param mo 一个 MultiOmicsData 对象。
#' @param layer_pairs 长度为 2 的字符向量组成的列表，用于指定层。
#' @param dist_method 距离方法。默认："euclidean"。
#' @param permutations 置换次数。默认：999。
#' @param verbose 逻辑值，是否打印进度。默认：TRUE。
#'
#' @return 一个列表，含 \code{results}（\code{run_procrustes()} 输出的有名列表）
#'   与 \code{summary}（含 layer_x、layer_y、ss、correlation、p_value、significance
#'   的数据框）。
#'
#' @examples
#' \dontrun{
#' pr <- run_all_procrustes(mo, list(c("microbiome", "metabolome")))
#' }
#'
#' @export
run_all_procrustes <- function(mo, layer_pairs,
                               dist_method = "euclidean",
                               permutations = 999,
                               verbose = TRUE) {
  if (!inherits(mo, "MultiOmicsData")) {
    stop("mo must be a MultiOmicsData object.")
  }

  results <- list()
  summary_df <- data.frame(
    layer_x = character(0), layer_y = character(0),
    ss = numeric(0), correlation = numeric(0), p_value = numeric(0),
    stringsAsFactors = FALSE
  )

  for (lp in layer_pairs) {
    if (length(lp) != 2) next
    key <- paste(lp[1], lp[2], sep = "__")

    res <- tryCatch({
      run_procrustes(
        mat_x = get_omics_matrix(mo, lp[1]),
        mat_y = get_omics_matrix(mo, lp[2]),
        dist_method = dist_method,
        permutations = permutations,
        name_x = lp[1], name_y = lp[2],
        verbose = verbose
      )
    }, error = function(e) {
      cat(sprintf("[procrustes] pair %s failed: %s\n", key, conditionMessage(e)))
      NULL
    })

    if (is.null(res)) next
    results[[key]] <- res
    summary_df <- rbind(summary_df, data.frame(
      layer_x = lp[1], layer_y = lp[2],
      ss = res$ss, correlation = res$correlation, p_value = res$p_value,
      stringsAsFactors = FALSE
    ))
  }

  if (nrow(summary_df) > 0) {
    summary_df$significance <- .significance_stars(summary_df$p_value)
  }

  return(list(results = results, summary = summary_df))
}

# ==============================================================================
# OmicsFlow: KEGG 通路映射与分析
# ==============================================================================
# 将 KEGG 化合物 ID 映射到 KEGG 通路，再进行通路层面的
# 富集分析与 GSVA。此举纠正了把化合物 ID 当作通路 ID 的科学性错误。
# ==============================================================================

#' 将 KEGG 化合物 ID 映射到 KEGG 通路
#'
#' @description 查询 KEGG REST API，将化合物 ID（如 C02845）映射到
#'   其关联的代谢通路（如 map00010）。一个化合物可关联多条通路。
#'   返回包含化合物-通路配对关系的数据框。
#'
#' @param kegg_ids KEGG 化合物 ID 的字符向量（如 "C02845"）。
#' @param cache_file 用于缓存/读取映射结果的缓存文件路径（可选）。默认：NULL。
#' @param batch_size 每次 API 请求的化合物数量（最多 10）。默认：10。
#' @param delay 两次 API 调用之间的间隔秒数。默认：0.3。
#'
#' @return 一个数据框，包含以下列：
#'   \itemize{
#'     \item \code{compound_id}：KEGG 化合物 ID。
#'     \item \code{pathway_id}：KEGG 通路 ID（如 "map00010"）。
#'     \item \code{pathway_name}：通路名称（如 "Glycolysis / Gluconeogenesis"）。
#'   }
#'
#' @examples
#' \dontrun{
#' mapping <- map_kegg_compound_to_pathway(c("C00022", "C00135"))
#' head(mapping)
#' }
#'
#' @export
map_kegg_compound_to_pathway <- function(kegg_ids, cache_dir = NULL,
                                          batch_size = 10, delay = 0.3) {
  # 清洗输入
  kegg_ids <- unique(kegg_ids[!is.na(kegg_ids) & kegg_ids != "" &
                                kegg_ids != "NULL" & kegg_ids != "NA"])
  if (length(kegg_ids) == 0) {
    warning("No valid KEGG compound IDs provided.")
    return(data.frame(
      compound_id = character(),
      pathway_id = character(),
      pathway_name = character(),
      stringsAsFactors = FALSE
    ))
  }

  # 保留调用方请求的完整 ID 集合：后续 kegg_ids 会被缩减为"未缓存的新 ID"，
  # 而最终返回值必须按原始请求集合过滤。
  orig_ids <- kegg_ids

  # 检查缓存
  cache_file <- if (!is.null(cache_dir)) file.path(cache_dir, "kegg_pathway_mapping.csv") else NULL
  if (!is.null(cache_file) && file.exists(cache_file)) {
    cached <- utils::read.csv(cache_file, stringsAsFactors = FALSE)
    # 已查询过的 ID = 有通路的 ID + 确认无通路的 ID（负结果）。
    # 若只记录前者，那些本就没有通路的化合物会在每次运行时被反复查询，
    # 既拖慢速度，又会触发"本批为空"的分支。
    queried_ids <- .kegg_queried_ids(cached, cache_file)
    new_ids <- setdiff(kegg_ids, queried_ids)
    cached <- cached[!is.na(cached$compound_id), , drop = FALSE]
    if (length(new_ids) == 0) {
      cat("  Using cached KEGG pathway mapping\n")
      return(cached[cached$compound_id %in% orig_ids, , drop = FALSE])
    }
    kegg_ids <- new_ids
    cached_data <- cached
  } else {
    cached_data <- NULL
  }

  # 归一化 KEGG ID 前缀：KO 号（ko:Kxxxx 或 Kxxxx）走 ko: 端点，
  # 化合物（cpd:Cxxxx 或 Cxxxx）走 cpd: 端点；两者均使用通用的
  # rest.kegg.jp/link/pathway/<id> 接口，端点由 ID 前缀决定。
  # 这是通用能力补全：此前仅支持化合物，KO 号被错误地加上 cpd: 前缀。
  query_ids <- character(length(kegg_ids))
  for (i in seq_along(kegg_ids)) {
    id <- kegg_ids[i]
    if (grepl("^ko:", id)) query_ids[i] <- id
    else if (grepl("^K\\d+$", id)) query_ids[i] <- paste0("ko:", id)
    else if (grepl("^cpd:", id)) query_ids[i] <- id
    else if (grepl("^C\\d+$", id)) query_ids[i] <- paste0("cpd:", id)
    else query_ids[i] <- id
  }

  # 分批查询 KEGG API
  all_links <- character()
  n_batches <- ceiling(length(query_ids) / batch_size)

  for (b in seq_len(n_batches)) {
    start_idx <- (b - 1) * batch_size + 1
    end_idx <- min(b * batch_size, length(query_ids))
    batch <- query_ids[start_idx:end_idx]

    url <- paste0("https://rest.kegg.jp/link/pathway/", paste(batch, collapse = "+"))

    tryCatch({
      tmp <- tempfile()
      system2("curl", args = c("-s", url), stdout = tmp, stderr = NULL)
      lines <- readLines(tmp, warn = FALSE)
      unlink(tmp)
      if (length(lines) > 0 && any(nchar(lines) > 0)) {
        all_links <- c(all_links, lines[nchar(lines) > 0])
      }
    }, error = function(e) {
      warning("KEGG API query failed (batch ", b, "）")
    })

    if (b %% 10 == 0) cat("  KEGG API: batch", b, "/", n_batches, "\n")
    if (delay > 0) Sys.sleep(delay)
  }

  if (length(all_links) == 0) {
    # 本批查询无任何通路关联。注意：这不代表整体结果为空——若已有缓存，
    # 缓存中的历史映射必须原样保留，否则"命中缓存但新 ID 全部无通路"的
    # 场景会把已缓存的全部映射一并丢弃（实测：74 个化合物中 57 个有通路、
    # 17 个无通路，第二次运行时这 17 个被当作新 ID 重查，返回空后
    # 导致 889 行缓存全部丢失）。
    if (!is.null(cached_data) && nrow(cached_data) > 0) {
      # 同时把本轮确认"无通路"的 ID 记为负结果，避免后续每次运行都重查
      .kegg_write_cache(cached_data, cache_file, kegg_ids)
      return(cached_data[cached_data$compound_id %in% orig_ids, , drop = FALSE])
    }
    warning("No pathway associations found for any compound.")
    return(data.frame(
      compound_id = character(),
      pathway_id = character(),
      pathway_name = character(),
      stringsAsFactors = FALSE
    ))
  }

  # 解析链接
  links <- strsplit(all_links, "\t")
  # 剥离 KEGG ID 前缀（ko: 或 cpd:），使 compound_id 与 feature_info 中的
  # 原始 KO 号/化合物号（如 K01610、C00022）保持一致，便于下游按 kegg 列回连。
  compound_ids <- sub("^(ko|cpd):", "", sapply(links, `[`, 1))
  pathway_ids <- sapply(links, `[`, 2)

  # 获取通路名称
  unique_pathways <- unique(pathway_ids)
  cat("  Found", length(unique(compound_ids)), "pathways for", length(unique_pathways), "unique pathways\n")

  pathway_names <- character(length(unique_pathways))
  names(pathway_names) <- unique_pathways

  for (i in seq_along(unique_pathways)) {
    pw <- unique_pathways[i]
    tryCatch({
      tmp <- tempfile()
      system2("curl", args = c("-s", paste0("https://rest.kegg.jp/get/", pw)),
              stdout = tmp, stderr = NULL)
      lines <- readLines(tmp, warn = FALSE)
      unlink(tmp)
      name_line <- grep("^NAME", lines, value = TRUE)[1]
      if (!is.na(name_line)) {
        pathway_names[pw] <- gsub("^NAME\\s+", "", name_line)
      } else {
        pathway_names[pw] <- pw
      }
    }, error = function(e) {
      pathway_names[pw] <- pw
    })
    if (i %% 20 == 0) cat("  Pathway names: ", i, "/", length(unique_pathways), "\n")
    if (delay > 0) Sys.sleep(delay)
  }

  result <- data.frame(
    compound_id = compound_ids,
    pathway_id = pathway_ids,
    pathway_name = pathway_names[pathway_ids],
    stringsAsFactors = FALSE
  )

  # 与历史缓存合并
  if (!is.null(cached_data)) {
    result <- rbind(cached_data, result)
    result <- result[!duplicated(result[, c("compound_id", "pathway_id")]), ,
                     drop = FALSE]
  }

  # 缓存（含本轮已查询过的 ID，用于记录负结果）
  if (!is.null(cache_file)) {
    .kegg_write_cache(result, cache_file, kegg_ids)
    cat("  KEGG mapping cached at: ", cache_file, "\n")
  }

  # 只返回调用方请求的化合物，避免把历史缓存中的无关记录一并带出
  rownames(result) <- NULL
  return(result[result$compound_id %in% orig_ids, , drop = FALSE])
}


# ------------------------------------------------------------------------------
# KEGG 缓存内部辅助函数
# ------------------------------------------------------------------------------
# 负结果（某化合物确认无任何通路关联）与映射表分开存放：映射表保持
# compound_id/pathway_id/pathway_name 三列的原有结构不变（向后兼容，
# 旧缓存文件可直接读取），负结果另存同目录下的 sidecar 文件。

.kegg_negative_file <- function(cache_file) {
  file.path(dirname(cache_file), "kegg_no_pathway_ids.txt")
}

# 返回"已经查询过"的化合物 ID：缓存命中的 + 已知无通路的
.kegg_queried_ids <- function(cached, cache_file) {
  ids <- unique(cached$compound_id)
  neg_file <- .kegg_negative_file(cache_file)
  if (file.exists(neg_file)) {
    neg <- readLines(neg_file, warn = FALSE)
    neg <- trimws(neg)
    ids <- unique(c(ids, neg[nzchar(neg)]))
  }
  ids
}

# 写出映射缓存，并把本轮查询中未获得任何通路的 ID 追加到负结果文件
.kegg_write_cache <- function(result, cache_file, queried_ids) {
  dir.create(dirname(cache_file), showWarnings = FALSE, recursive = TRUE)
  utils::write.csv(result, cache_file, row.names = FALSE)

  no_hit <- setdiff(queried_ids, unique(result$compound_id))
  if (length(no_hit) > 0) {
    neg_file <- .kegg_negative_file(cache_file)
    prev <- if (file.exists(neg_file)) readLines(neg_file, warn = FALSE) else character()
    all_neg <- sort(unique(c(trimws(prev), no_hit)))
    writeLines(all_neg[nzchar(all_neg)], neg_file)
  }
  invisible(NULL)
}


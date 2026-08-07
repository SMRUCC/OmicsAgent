# ==============================================================================
# OmicsFlow：动态贝叶斯网络、虚拟扰动与分层 PLS 路径模型可视化
# ==============================================================================
# 布局坐标在需要力导向排布时由 igraph 计算，再使用 ggplot2 渲染，使图形与本项目中
# 其他 plot_* 函数风格一致，并可直接传入 export_plot()。
#
# 每个函数都能优雅降级：当无可绘制内容时，返回一个带有说明信息的合法 ggplot，
# 而非报错，从而避免流水线步骤因网络恰好为空而中断。
# ==============================================================================


#' Palette used to colour omics layers consistently across all figures
#' @keywords internal
.dbn_omics_palette <- c(
  microbiome    = "#8c6bb1",
  transcriptome = "#4a90d9",
  proteome      = "#41ab5d",
  metabolome    = "#fe9929",
  volatilome    = "#e34a33"
)


#' 为一组组学层解析颜色
#'
#' @param layers 层名称的字符向量。
#'
#' @return 颜色的有名字符向量。
#'
#' @keywords internal
.dbn_layer_colors <- function(layers) {
  layers <- unique(layers[!is.na(layers)])
  if (length(layers) == 0) return(character(0))
  known <- intersect(layers, names(.dbn_omics_palette))
  unknown <- setdiff(layers, known)
  cols <- .dbn_omics_palette[known]
  if (length(unknown) > 0) {
    extra <- grDevices::hcl.colors(length(unknown), palette = "Dark 3")
    cols <- c(cols, stats::setNames(extra, unknown))
  }
  cols[layers]
}


#' 携带说明信息的占位空图
#'
#' @param msg 要显示的提示信息。
#' @param title 可选图标题。
#'
#' @return 一个 ggplot 对象。
#'
#' @keywords internal
.dbn_empty_plot <- function(msg, title = NULL) {
  ggplot2::ggplot() +
    ggplot2::annotate("text", x = 0, y = 0, label = msg, size = 4.5,
                      colour = "grey30") +
    ggplot2::labs(title = title) +
    ggplot2::theme_void() +
    ggplot2::theme(plot.title = ggplot2::element_text(size = 14,
                                                      face = "bold"))
}


#' 截断过长的标签以保持图形可读性
#'
#' @param x 字符向量。
#' @param n 最大字符数。
#'
#' @return 截断后的标签字符向量。
#'
#' @keywords internal
.dbn_trim <- function(x, n = 26) {
  x <- as.character(x)
  ifelse(nchar(x) > n, paste0(substr(x, 1, n - 1), "\u2026"), x)
}


#' 将网络布局归一化为两列数据框
#'
#' @param coords 两列数值矩阵 / df，或 NULL。
#' @param nodes 要保留的节点标识字符向量。
#'
#' @return 含 `node`、`x`、`y` 列的数据框；当 `coords` 无法与节点匹配时返回 NULL。
#'
#' @keywords internal
.dbn_layout_df <- function(coords, nodes) {
  if (is.null(coords) || length(nodes) == 0) return(NULL)
  coords <- as.data.frame(coords)
  if (ncol(coords) < 2) return(NULL)
  if (nrow(coords) != length(nodes)) {
    # named layout: reorder / subset to the requested node order
    if (is.null(rownames(coords)) ||
        !all(nodes %in% rownames(coords))) return(NULL)
    coords <- coords[nodes, , drop = FALSE]
  }
  out <- data.frame(node = nodes,
                    x = as.numeric(coords[[1]][seq_len(length(nodes))]),
                    y = as.numeric(coords[[2]][seq_len(length(nodes))]),
                    stringsAsFactors = FALSE)
  rownames(out) <- NULL
  out
}


#' 使用 igraph 布局为网络计算节点坐标
#'
#' @description 封装 igraph 布局引擎，使网络图形统一采用同一种将边列表转换为坐标
#'   的方式。除力导向 / 谱布局外，它也可复用通过 `layout` 参数传入的手动布局。
#'
#' @param arcs 含 `from` 与 `to` 列的数据框。
#' @param layout 布局选择器，可选之一：
#'   \itemize{
#'     \item \code{"fr"} / \code{"force"}: Fruchterman-Reingold 力导向布局
#'       （若通过 \code{old_coords} 提供先前布局，则以其为起点）。
#'     \item \code{"kk"}: Kamada-Kawai 力导向布局。
#'     \item \code{"tree"}: Sugiyama 分层布局（适用于上游 -> 下游流向）。
#'     \item \code{"circle"}: 环形排列。
#'     \item 显式坐标的两列矩阵 / 数据框（行须以节点 id 命名）。
#'   }
#' @param old_coords 可选先前的坐标（具名矩阵），用作力导向布局的起点；否则忽略。
#'
#' @return 含 `node`、`x`、`y` 列的数据框。
#'
#' @keywords internal
.dbn_compute_layout <- function(arcs, layout = "fr", old_coords = NULL) {
  all_nodes <- unique(c(arcs$from, arcs$to))

  # 调用方传入的显式坐标矩阵
  if (is.matrix(layout) || is.data.frame(layout)) {
    return(.dbn_layout_df(layout, all_nodes))
  }

  lay_key <- tolower(as.character(layout)[1])
  g <- igraph::graph_from_data_frame(
    arcs[, c("from", "to"), drop = FALSE],
    directed = TRUE,
    vertices = data.frame(name = all_nodes, stringsAsFactors = FALSE))

  coords <- switch(
    lay_key,
    fr = , force = {
      seed <- NULL
      if (!is.null(old_coords) &&
          all(all_nodes %in% rownames(old_coords))) {
        seed <- old_coords[all_nodes, , drop = FALSE]
      }
      igraph::layout_with_fr(g, coords = seed, weights = NULL)
    },
    kk = {
      igraph::layout_with_kk(g)
    },
    tree = {
      tryCatch(
        igraph::layout_as_tree(g, circular = FALSE),
        error = function(e) igraph::layout_with_kk(g))
    },
    circle = {
      igraph::layout_in_circle(g)
    },
    {
      igraph::layout_nicely(g)
    })

  .dbn_layout_df(coords, all_nodes)
}


# ------------------------------------------------------------------------------
# Dynamic Bayesian network figures
# ------------------------------------------------------------------------------

#' 绘制单组学动态贝叶斯网络
#'
#' @description 将 DBN 的两个时间切片绘制为两列竖直柱：较早切片（t0）在左、
#'   较晚切片（t1）在右，使每条箭头都表示一个时间转移。弧的线宽与透明度编码
#'   自助弧强度。
#'
#' @param dbn_result \code{run_dbn_layer()} 的结果。
#' @param title 图标题。
#' @param label_top 标注的最大节点数，按度数选取。默认：30。
#' @param layout 网络布局。\code{"fr"} / \code{"force"}（默认）使用
#'   Fruchterman-Reingold 力导向布局，\code{"kk"} 使用 Kamada-Kawai 布局，
#'   \code{"tree"} 使用 Sugiyama 分层布局，\code{"hier"} 使用早期版本的两列时间
#'   切片布局。也可传入两列坐标矩阵（行以节点 id 命名）以显式指定节点位置。
#'
#' @return 一个 ggplot 对象。
#'
#' @examples
#' \dontrun{
#' export_plot(plot_dbn_layer(dbn, "Metabolome DBN"), fig_dir, "dbn_metabolome")
#' }
#'
#' @export
plot_dbn_layer <- function(dbn_result, title = NULL, label_top = 30,
                           layout = "fr") {
  if (is.null(dbn_result)) return(.dbn_empty_plot("No DBN result.", title))
  arcs <- dbn_result$arcs
  nd <- dbn_result$nodes_df
  if (is.null(arcs) || nrow(arcs) == 0) {
    return(.dbn_empty_plot("No time-lagged arc passed the strength filter.",
                           title))
  }

  # keep only nodes that participate in at least one arc
  active <- union(arcs$from, arcs$to)
  nd <- nd[nd$node %in% active, , drop = FALSE]
  if (nrow(nd) == 0) return(.dbn_empty_plot("No connected node.", title))

  hier_layout <- (is.character(layout) &&
                    tolower(layout)[1] %in% c("hier", "hierarchical"))
  if (hier_layout) {
    pos <- do.call(rbind, lapply(split(nd, nd$time_slice), function(s) {
      s <- s[order(-s$degree), , drop = FALSE]
      s$x <- if (s$time_slice[1] == "t0") 0 else 1
      s$y <- if (nrow(s) == 1) 0.5 else seq(0, 1, length.out = nrow(s))
      s
    }))
    rownames(pos) <- NULL
  } else {
    xy <- .dbn_compute_layout(arcs, layout = layout)
    if (is.null(xy)) {
      return(.dbn_empty_plot("Could not compute the network layout.", title))
    }
    pos <- nd
    pos$x <- xy$x[match(pos$node, xy$node)]
    pos$y <- xy$y[match(pos$node, xy$node)]
  }

  ed <- data.frame(
    x = pos$x[match(arcs$from, pos$node)],
    y = pos$y[match(arcs$from, pos$node)],
    xend = pos$x[match(arcs$to, pos$node)],
    yend = pos$y[match(arcs$to, pos$node)],
    strength = if ("strength" %in% colnames(arcs)) arcs$strength else 1,
    self_loop = if ("self_loop" %in% colnames(arcs)) arcs$self_loop else FALSE,
    stringsAsFactors = FALSE)
  ed <- ed[stats::complete.cases(ed[, c("x", "y", "xend", "yend")]), ,
           drop = FALSE]
  ed$strength[is.na(ed$strength)] <- 0.5

  lab <- pos[order(-pos$degree), , drop = FALSE]
  lab <- lab[seq_len(min(label_top, nrow(lab))), , drop = FALSE]
  lab$text <- .dbn_trim(lab$label)

  ggplot2::ggplot() +
    ggplot2::geom_segment(
      data = ed,
      ggplot2::aes(x = x, y = y, xend = xend, yend = yend,
                   linewidth = strength, alpha = strength,
                   colour = self_loop),
      arrow = grid::arrow(length = grid::unit(0.16, "cm"), type = "closed")) +
    ggplot2::geom_point(data = pos,
                        ggplot2::aes(x = x, y = y, fill = time_slice),
                        shape = 21, size = 3.4, colour = "white",
                        stroke = 0.6) +
    ggrepel::geom_text_repel(data = lab,
                             ggplot2::aes(x = x, y = y, label = text),
                             size = 2.4, max.overlaps = 40,
                             segment.size = 0.2, segment.colour = "grey70") +
    ggplot2::scale_linewidth_continuous(range = c(0.25, 1.5),
                                        guide = "none") +
    ggplot2::scale_alpha_continuous(range = c(0.3, 0.9), name = "Arc strength") +
    ggplot2::scale_colour_manual(values = c("FALSE" = "grey45",
                                            "TRUE" = "#e34a33"),
                                 labels = c("FALSE" = "regulatory",
                                            "TRUE" = "auto-regulation"),
                                 name = "Arc type") +
    ggplot2::scale_fill_manual(values = c(t0 = "#4a90d9", t1 = "#fe9929"),
                               labels = c(t0 = "time t", t1 = "time t+1"),
                               name = "Time slice") +
    ggplot2::labs(title = title, x = NULL, y = NULL) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 13, face = "bold"),
      panel.grid = ggplot2::element_blank(),
      axis.text.y = ggplot2::element_blank(),
      axis.text.x = ggplot2::element_blank()) +
    (if (hier_layout) {
      ggplot2::scale_x_continuous(breaks = c(0, 1),
                                  labels = c("t (past)", "t+1 (future)"),
                                  limits = c(-0.25, 1.25))
    } else {
      ggplot2::scale_x_continuous(breaks = NULL)
    })
}


#' 绘制合并的全组学动态贝叶斯网络
#'
#' @description 将节点按每层一列、依生物学层级排列，使跨组学层的弧在视觉上一目了然。
#'   跨组学弧被高亮，而组学内弧以淡色绘制，节点大小编码连接数。
#'
#' @param dbn_result \code{run_dbn_multiomics()} 的结果。
#' @param title 图标题。
#' @param layer_order 组学层的列顺序。默认：结果中存储的顺序。仅当 \code{layout = "hier"} 时使用。
#' @param label_top 标注的最大节点数。默认：30。
#' @param layout 网络布局。\code{"fr"} / \code{"force"}（默认）使用
#'   Fruchterman-Reingold 力导向布局，\code{"kk"} 使用 Kamada-Kawai 布局，
#'   \code{"hier"} 使用早期版本的每层一列布局。也可传入两列坐标矩阵（行以节点 id 命名）。
#'
#' @return 一个 ggplot 对象。
#'
#' @examples
#' \dontrun{
#' export_plot(plot_dbn_multiomics(dbn), fig_dir, "dbn_pan_omics")
#' }
#'
#' @export
plot_dbn_multiomics <- function(dbn_result, title = NULL, layer_order = NULL,
                                label_top = 30, layout = "fr") {
  if (is.null(dbn_result)) return(.dbn_empty_plot("No DBN result.", title))
  arcs <- dbn_result$arcs
  nd <- dbn_result$nodes_df
  if (is.null(arcs) || nrow(arcs) == 0) {
    return(.dbn_empty_plot("No time-lagged arc passed the strength filter.",
                           title))
  }
  if (!"omics" %in% colnames(nd)) {
    return(plot_dbn_layer(dbn_result, title = title, label_top = label_top,
                          layout = layout))
  }

  active <- union(arcs$from, arcs$to)
  nd <- nd[nd$node %in% active, , drop = FALSE]
  if (nrow(nd) == 0) return(.dbn_empty_plot("No connected node.", title))

  hier_layout <- (is.character(layout) &&
                    tolower(layout)[1] %in% c("hier", "hierarchical"))

  if (is.null(layer_order)) {
    layer_order <- dbn_result$layer_order %||% unique(nd$omics)
  }
  layer_order <- c(intersect(layer_order, unique(nd$omics)),
                   setdiff(unique(nd$omics), layer_order))
  nd$omics <- factor(nd$omics, levels = layer_order)

  if (hier_layout) {
    # one column per omics layer, t0 slightly left of t1 inside the column
    pos <- do.call(rbind, lapply(split(nd, nd$omics, drop = TRUE), function(s) {
      s <- s[order(s$time_slice, -s$degree), , drop = FALSE]
      s$x <- as.numeric(s$omics) + ifelse(s$time_slice == "t0", -0.16, 0.16)
      s$y <- if (nrow(s) == 1) 0.5 else seq(0, 1, length.out = nrow(s))
      s
    }))
    rownames(pos) <- NULL
  } else {
    xy <- .dbn_compute_layout(arcs, layout = layout)
    if (is.null(xy)) {
      return(.dbn_empty_plot("Could not compute the network layout.", title))
    }
    pos <- nd
    pos$x <- xy$x[match(pos$node, xy$node)]
    pos$y <- xy$y[match(pos$node, xy$node)]
  }

  ed <- data.frame(
    x = pos$x[match(arcs$from, pos$node)],
    y = pos$y[match(arcs$from, pos$node)],
    xend = pos$x[match(arcs$to, pos$node)],
    yend = pos$y[match(arcs$to, pos$node)],
    strength = if ("strength" %in% colnames(arcs)) arcs$strength else 1,
    edge_type = if ("edge_type" %in% colnames(arcs)) arcs$edge_type else
      "intra_omics",
    stringsAsFactors = FALSE)
  ed <- ed[stats::complete.cases(ed[, c("x", "y", "xend", "yend")]), ,
           drop = FALSE]
  ed$strength[is.na(ed$strength)] <- 0.5
  ed$edge_type[is.na(ed$edge_type)] <- "intra_omics"

  lab <- pos[order(-pos$degree), , drop = FALSE]
  lab <- lab[seq_len(min(label_top, nrow(lab))), , drop = FALSE]
  lab$text <- .dbn_trim(lab$label, 24)

  cols <- .dbn_layer_colors(levels(nd$omics))

  ggplot2::ggplot() +
    ggplot2::geom_segment(
      data = ed,
      ggplot2::aes(x = x, y = y, xend = xend, yend = yend,
                   colour = edge_type, alpha = edge_type,
                   linewidth = strength),
      arrow = grid::arrow(length = grid::unit(0.15, "cm"), type = "closed")) +
    ggplot2::geom_point(data = pos,
                        ggplot2::aes(x = x, y = y, fill = omics,
                                     size = degree, shape = time_slice),
                        colour = "white", stroke = 0.5) +
    ggrepel::geom_text_repel(data = lab,
                             ggplot2::aes(x = x, y = y, label = text),
                             size = 2.2, max.overlaps = 40,
                             segment.size = 0.2, segment.colour = "grey75") +
    ggplot2::scale_colour_manual(values = c(inter_omics = "#d7301f",
                                            intra_omics = "grey55"),
                                 name = "Arc type") +
    ggplot2::scale_alpha_manual(values = c(inter_omics = 0.85,
                                           intra_omics = 0.35),
                                guide = "none") +
    ggplot2::scale_linewidth_continuous(range = c(0.25, 1.4), guide = "none") +
    ggplot2::scale_size_continuous(range = c(2, 6), name = "Degree") +
    ggplot2::scale_shape_manual(values = c(t0 = 21, t1 = 24),
                                labels = c(t0 = "time t", t1 = "time t+1"),
                                name = "Time slice") +
    ggplot2::scale_fill_manual(values = cols, name = "Omics layer") +
    (if (hier_layout) {
      ggplot2::scale_x_continuous(breaks = seq_along(levels(nd$omics)),
                                  labels = levels(nd$omics))
    } else {
      ggplot2::scale_x_continuous(breaks = NULL)
    }) +
    ggplot2::guides(fill = ggplot2::guide_legend(
      override.aes = list(shape = 21, size = 4))) +
    ggplot2::labs(title = title, x = NULL, y = NULL) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 13, face = "bold"),
      panel.grid = ggplot2::element_blank(),
      axis.text.y = ggplot2::element_blank(),
      axis.text.x = if (hier_layout) {
        ggplot2::element_text(face = "bold", size = 9, angle = 20, hjust = 1)
      } else {
        ggplot2::element_blank()
      })
}


# ------------------------------------------------------------------------------
# Perturbation figures
# ------------------------------------------------------------------------------

#' 绘制被扰动节点的调控重要性排序
#'
#' @param importance_df \code{score_regulatory_importance()} 的输出，或
#'   \code{run_perturbation_panel()} 堆叠后的 \code{importance} 表。
#' @param top_n 每种模式显示的节点数。默认：20。
#' @param title 图标题。
#'
#' @return 一个 ggplot 对象。
#'
#' @examples
#' \dontrun{
#' export_plot(plot_perturbation_ranking(imp), fig_dir, "perturb_ranking")
#' }
#'
#' @export
plot_perturbation_ranking <- function(importance_df, top_n = 20,
                                      title = NULL) {
  if (is.null(importance_df) || nrow(importance_df) == 0) {
    return(.dbn_empty_plot("No perturbation result to display.", title))
  }
  df <- importance_df
  if (!"label" %in% colnames(df)) df$label <- df$node
  if (!"mode" %in% colnames(df)) df$mode <- "perturbation"

  df <- do.call(rbind, lapply(split(df, df$mode), function(s) {
    s <- s[order(-s$impact_score), , drop = FALSE]
    s[seq_len(min(top_n, nrow(s))), , drop = FALSE]
  }))
  df$text <- .dbn_trim(df$label, 30)
  # keep bars sorted within each facet
  df$key <- paste(df$mode, df$text, sep = "|")
  df <- df[order(df$mode, df$impact_score), , drop = FALSE]
  df$key <- factor(df$key, levels = unique(df$key))

  p <- ggplot2::ggplot(df, ggplot2::aes(x = key, y = impact_score))
  if ("omics" %in% colnames(df)) {
    p <- p + ggplot2::geom_col(ggplot2::aes(fill = omics), width = 0.72) +
      ggplot2::scale_fill_manual(values = .dbn_layer_colors(df$omics),
                                 name = "Omics layer")
  } else {
    p <- p + ggplot2::geom_col(fill = "#4a90d9", width = 0.72)
  }

  p +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.2f", impact_score)),
                       hjust = -0.15, size = 2.6) +
    ggplot2::scale_x_discrete(labels = function(x) sub("^[^|]*\\|", "", x)) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.18))) +
    ggplot2::coord_flip() +
    ggplot2::facet_wrap(~ mode, scales = "free_y") +
    ggplot2::labs(title = title, x = NULL, y = "Regulatory impact score") +
    ggplot2::theme_bw(base_size = 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 13, face = "bold"),
      panel.grid.major.y = ggplot2::element_blank(),
      strip.background = ggplot2::element_rect(fill = "grey92",
                                               colour = "grey70"),
      strip.text = ggplot2::element_text(face = "bold"))
}


#' 扰动对下游节点影响的瀑布热力图
#'
#' @description 展示每个被扰动节点对其下游节点状态分布的偏移强度。填充色编码有符号
#'   概率偏移（若可用），否则编码总变差距离。
#'
#' @param pair_details 扰动结果的 \code{pair_details} 表。
#' @param mode 限定为单一扰动模式。默认：首个具有可用推断值的模式。
#' @param top_n 显示的最大被扰动节点数。默认：15。
#' @param title 图标题。
#'
#' @return 一个 ggplot 对象。
#'
#' @examples
#' \dontrun{
#' export_plot(plot_perturbation_heatmap(pp$pair_details), fig_dir, "heat")
#' }
#'
#' @export
plot_perturbation_heatmap <- function(pair_details, mode = NULL, top_n = 15,
                                      title = NULL) {
  if (is.null(pair_details) || nrow(pair_details) == 0) {
    return(.dbn_empty_plot("No downstream pair to display.", title))
  }
  df <- pair_details

  if (is.null(mode) && "mode" %in% colnames(df)) {
    with_val <- df[!is.na(df$prob_shift) | !is.na(df$tvd), , drop = FALSE]
    mode <- if (nrow(with_val) > 0) with_val$mode[1] else df$mode[1]
  }
  if (!is.null(mode) && "mode" %in% colnames(df)) {
    df <- df[df$mode == mode, , drop = FALSE]
  }
  if (nrow(df) == 0) {
    return(.dbn_empty_plot("No downstream pair for this mode.", title))
  }

  use_shift <- "prob_shift" %in% colnames(df) && any(!is.na(df$prob_shift))
  df$value <- if (use_shift) df$prob_shift else df$tvd
  if (all(is.na(df$value))) {
    df$value <- 1
    legend_name <- "Downstream link"
  } else {
    legend_name <- if (use_shift) "P(high) shift" else "TVD"
  }

  if (!"perturbed_label" %in% colnames(df)) {
    df$perturbed_label <- df$perturbed_node
  }
  if (!"downstream_label" %in% colnames(df)) {
    df$downstream_label <- df$downstream_node
  }

  keep <- names(sort(table(df$perturbed_label), decreasing = TRUE))
  keep <- keep[seq_len(min(top_n, length(keep)))]
  df <- df[df$perturbed_label %in% keep, , drop = FALSE]

  df$xr <- .dbn_trim(df$perturbed_label, 28)
  df$yr <- .dbn_trim(df$downstream_label, 28)

  p <- ggplot2::ggplot(df, ggplot2::aes(x = xr, y = yr, fill = value)) +
    ggplot2::geom_tile(colour = "white", linewidth = 0.4)

  if (use_shift) {
    lim <- max(abs(df$value), na.rm = TRUE)
    if (!is.finite(lim) || lim == 0) lim <- 1
    p <- p + ggplot2::scale_fill_gradient2(low = "#2c7bb6", mid = "white",
                                           high = "#d7191c", midpoint = 0,
                                           limits = c(-lim, lim),
                                           name = legend_name)
  } else {
    p <- p + ggplot2::scale_fill_viridis_c(option = "C", name = legend_name)
  }

  sub <- if (!is.null(mode)) sprintf("Perturbation mode: %s", mode) else NULL

  p +
    ggplot2::labs(title = title, subtitle = sub,
                  x = "Perturbed node", y = "Downstream node") +
    ggplot2::theme_minimal(base_size = 10) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 13, face = "bold"),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1, size = 7.5),
      axis.text.y = ggplot2::element_text(size = 7.5),
      panel.grid = ggplot2::element_blank())
}


#' 绘制单个被扰动节点的下游影响子网络
#'
#' @description 提取该节点及其可达的所有节点，并绘制该子网络，其中被扰动节点高亮，
#'   其余节点按路径距离排布为同心环。
#'
#' @param dbn_result 一个 DBN 结果对象。
#' @param node 被扰动节点的名称。
#' @param title 图标题。
#' @param max_distance 包含的最大路径长度。默认：Inf。
#' @param layout 子网络布局。\code{"fr"} / \code{"force"}（默认）使用
#'   Fruchterman-Reingold 力导向布局，\code{"kk"} 使用 Kamada-Kawai 布局。
#'   \code{"ring"}（早期版本默认）按距被扰动节点的路径距离将节点排布为同心环。
#'   也可传入两列坐标矩阵。
#'
#' @return 一个 ggplot 对象。
#'
#' @examples
#' \dontrun{
#' export_plot(plot_perturbation_subnetwork(dbn, top_node), fig_dir, "sub")
#' }
#'
#' @export
plot_perturbation_subnetwork <- function(dbn_result, node, title = NULL,
                                         max_distance = Inf, layout = "fr") {
  if (is.null(dbn_result) || is.null(node) || length(node) == 0) {
    return(.dbn_empty_plot("No node supplied.", title))
  }
  desc <- get_downstream_nodes(dbn_result, node, max_distance = max_distance)
  if (nrow(desc) == 0) {
    return(.dbn_empty_plot(sprintf("Node '%s' has no downstream target.", node),
                           title))
  }

  keep <- c(node, desc$node)
  arcs <- dbn_result$arcs
  arcs <- arcs[arcs$from %in% keep & arcs$to %in% keep, , drop = FALSE]
  nd <- dbn_result$nodes_df
  nd <- nd[nd$node %in% keep, , drop = FALSE]

  ring_layout <- (is.character(layout) &&
                    tolower(layout)[1] %in% c("ring", "radial", "concentric"))

  if (ring_layout) {
    nd$distance <- 0
    m <- match(nd$node, desc$node)
    nd$distance[!is.na(m)] <- desc$distance[m[!is.na(m)]]

    # concentric rings: perturbed node in the middle, one ring per hop
    pos <- do.call(rbind, lapply(split(nd, nd$distance), function(s) {
      d <- s$distance[1]
      if (d == 0) {
        s$x <- 0; s$y <- 0
      } else {
        ang <- seq(0, 2 * pi, length.out = nrow(s) + 1)[seq_len(nrow(s))]
        s$x <- d * cos(ang)
        s$y <- d * sin(ang)
      }
      s
    }))
    rownames(pos) <- NULL
  } else {
    xy <- .dbn_compute_layout(arcs, layout = layout)
    if (is.null(xy)) {
      return(.dbn_empty_plot("Could not compute the sub-network layout.",
                             title))
    }
    pos <- nd
    pos$x <- xy$x[match(pos$node, xy$node)]
    pos$y <- xy$y[match(pos$node, xy$node)]
  }
  pos$role <- ifelse(pos$node == node, "perturbed", "downstream")

  ed <- data.frame(
    x = pos$x[match(arcs$from, pos$node)],
    y = pos$y[match(arcs$from, pos$node)],
    xend = pos$x[match(arcs$to, pos$node)],
    yend = pos$y[match(arcs$to, pos$node)],
    stringsAsFactors = FALSE)
  ed <- ed[stats::complete.cases(ed), , drop = FALSE]

  pos$text <- .dbn_trim(pos$label, 24)

  p <- ggplot2::ggplot()
  if (nrow(ed) > 0) {
    p <- p + ggplot2::geom_segment(
      data = ed,
      ggplot2::aes(x = x, y = y, xend = xend, yend = yend),
      arrow = grid::arrow(length = grid::unit(0.18, "cm"), type = "closed"),
      colour = "grey50", alpha = 0.7, linewidth = 0.45)
  }

  aes_point <- if ("omics" %in% colnames(pos)) {
    ggplot2::aes(x = x, y = y, fill = omics, size = role)
  } else {
    ggplot2::aes(x = x, y = y, size = role)
  }

  p <- p + ggplot2::geom_point(data = pos, aes_point, shape = 21,
                               colour = "grey20", stroke = 0.6)
  if ("omics" %in% colnames(pos)) {
    p <- p + ggplot2::scale_fill_manual(values = .dbn_layer_colors(pos$omics),
                                        name = "Omics layer")
  }

  p +
    ggrepel::geom_text_repel(data = pos,
                             ggplot2::aes(x = x, y = y, label = text),
                             size = 2.6, max.overlaps = 40,
                             segment.size = 0.2, segment.colour = "grey70") +
    ggplot2::scale_size_manual(values = c(perturbed = 7, downstream = 3.6),
                               name = NULL) +
    ggplot2::coord_equal() +
    ggplot2::labs(title = title, x = NULL, y = NULL) +
    ggplot2::theme_void(base_size = 11) +
    ggplot2::theme(plot.title = ggplot2::element_text(size = 13,
                                                      face = "bold"))
}


# ------------------------------------------------------------------------------
# PLS path model figure
# ------------------------------------------------------------------------------

#' 绘制分层多组学 PLS 路径模型
#'
#' @description 将潜变量按每层一列、依生物学层级排列，并绘制它们之间的估计路径
#'   系数。边的线宽编码系数大小，颜色编码符号，虚线标记不显著的路径。
#'
#' @param plspm_result \code{run_multiomics_plspm()} 的输出。
#' @param layer_order 组学层的列顺序。仅当 \code{layout = "hier"} 时使用。
#' @param p_threshold 线型所用的显著性阈值。默认：0.05。
#' @param min_abs_coeff 隐藏绝对系数低于该值的路径，以保持稠密模型的可读性。默认：0。
#' @param significant_only 仅绘制显著路径。默认：FALSE。
#' @param layout 网络布局。\code{"hier"}（默认）保持遵循生物学层级的每层一列布局。
#'   \code{"fr"} / \code{"force"} 使用 Fruchterman-Reingold 力导向布局，\code{"kk"}
#'   使用 Kamada-Kawai 布局。也可传入两列坐标矩阵（行以潜变量 id 命名）。
#' @param title 图标题。
#'
#' @return 一个 ggplot 对象。
#'
#' @examples
#' \dontrun{
#' export_plot(plot_plspm_hierarchy(res, layer_order), fig_dir, "plspm_paths")
#' }
#'
#' @export
plot_plspm_hierarchy <- function(plspm_result, layer_order = NULL,
                                 p_threshold = 0.05, min_abs_coeff = 0,
                                 significant_only = FALSE, layout = "hier",
                                 title = NULL) {
  if (is.null(plspm_result)) {
    return(.dbn_empty_plot("No PLS-PM result.", title))
  }
  ip <- plspm_result$inner_paths
  defs <- plspm_result$definitions
  if (is.null(ip) || nrow(ip) == 0 || is.null(defs)) {
    return(.dbn_empty_plot("No path coefficient to display.", title))
  }

  if (isTRUE(significant_only)) {
    ip <- ip[!is.na(ip$p_value) & ip$p_value < p_threshold, , drop = FALSE]
  }
  if (min_abs_coeff > 0) {
    ip <- ip[abs(ip$path_coeff) >= min_abs_coeff, , drop = FALSE]
  }
  if (nrow(ip) == 0) {
    return(.dbn_empty_plot("No path passed the filters.", title))
  }

  hier_layout <- (is.character(layout) &&
                    tolower(layout)[1] %in% c("hier", "hierarchical"))

  if (is.null(layer_order)) layer_order <- unique(defs$layer)
  layer_order <- c(intersect(layer_order, unique(defs$layer)),
                   setdiff(unique(defs$layer), layer_order))
  defs$layer <- factor(defs$layer, levels = layer_order)

  active <- union(ip$from, ip$to)
  pos <- defs[defs$latent %in% active, , drop = FALSE]
  if (nrow(pos) == 0) return(.dbn_empty_plot("No connected latent variable.",
                                             title))

  if (hier_layout) {
    pos <- do.call(rbind, lapply(split(pos, pos$layer, drop = TRUE), function(s) {
      s$x <- as.numeric(s$layer)
      s$y <- if (nrow(s) == 1) 0.5 else seq(0, 1, length.out = nrow(s))
      s
    }))
    rownames(pos) <- NULL
  } else {
    arcs_pl <- data.frame(from = ip$from, to = ip$to,
                          stringsAsFactors = FALSE)
    xy <- .dbn_compute_layout(arcs_pl, layout = layout)
    if (is.null(xy)) {
      return(.dbn_empty_plot("Could not compute the path layout.", title))
    }
    pos$x <- xy$x[match(pos$latent, xy$node)]
    pos$y <- xy$y[match(pos$latent, xy$node)]
  }

  ed <- data.frame(
    x = pos$x[match(ip$from, pos$latent)],
    y = pos$y[match(ip$from, pos$latent)],
    xend = pos$x[match(ip$to, pos$latent)],
    yend = pos$y[match(ip$to, pos$latent)],
    coeff = ip$path_coeff,
    sign = ifelse(ip$path_coeff >= 0, "positive", "negative"),
    sig = ifelse(!is.na(ip$p_value) & ip$p_value < p_threshold,
                 "significant", "n.s."),
    stringsAsFactors = FALSE)
  ed <- ed[stats::complete.cases(ed[, c("x", "y", "xend", "yend")]), ,
           drop = FALSE]
  ed$abs_coeff <- abs(ed$coeff)

  pos$text <- .dbn_trim(pos$latent, 24)
  cols <- .dbn_layer_colors(levels(defs$layer))

  # R2 of each endogenous latent variable drives the node size when available
  if (!is.null(plspm_result$fit_summary) &&
      "R2" %in% colnames(plspm_result$fit_summary)) {
    r2 <- plspm_result$fit_summary$R2[match(pos$latent,
                                            plspm_result$fit_summary$latent)]
    pos$r2 <- ifelse(is.na(r2), 0, r2)
  } else {
    pos$r2 <- 0
  }

  ggplot2::ggplot() +
    ggplot2::geom_segment(
      data = ed,
      ggplot2::aes(x = x, y = y, xend = xend, yend = yend,
                   colour = sign, linewidth = abs_coeff, linetype = sig),
      alpha = 0.75,
      arrow = grid::arrow(length = grid::unit(0.15, "cm"), type = "closed")) +
    ggplot2::geom_point(data = pos,
                        ggplot2::aes(x = x, y = y, fill = layer, size = r2),
                        shape = 21, colour = "white", stroke = 0.7) +
    ggrepel::geom_text_repel(data = pos,
                             ggplot2::aes(x = x, y = y, label = text),
                             size = 2.5, max.overlaps = 40,
                             segment.size = 0.2, segment.colour = "grey70") +
    ggplot2::scale_colour_manual(values = c(positive = "#d7191c",
                                            negative = "#2c7bb6"),
                                 name = "Path sign") +
    ggplot2::scale_linetype_manual(values = c(significant = "solid",
                                              "n.s." = "dashed"),
                                   name = sprintf("p < %.2f", p_threshold)) +
    ggplot2::scale_linewidth_continuous(range = c(0.2, 1.8),
                                        name = "|path coeff|") +
    ggplot2::scale_size_continuous(range = c(3, 8), name = expression(R^2)) +
    ggplot2::scale_fill_manual(values = cols, name = "Omics layer") +
    (if (hier_layout) {
      ggplot2::scale_x_continuous(breaks = seq_along(levels(defs$layer)),
                                  labels = levels(defs$layer),
                                  limits = c(0.6,
                                             length(levels(defs$layer)) + 0.4))
    } else {
      ggplot2::scale_x_continuous(breaks = NULL)
    }) +
    ggplot2::guides(fill = ggplot2::guide_legend(
      override.aes = list(size = 4))) +
    ggplot2::labs(title = title, x = NULL, y = NULL) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 13, face = "bold"),
      panel.grid = ggplot2::element_blank(),
      axis.text.y = ggplot2::element_blank(),
      axis.text.x = if (hier_layout) {
        ggplot2::element_text(face = "bold", size = 9, angle = 20, hjust = 1)
      } else {
        ggplot2::element_blank()
      })
}


#' 各潜变量解释方差的柱状图
#'
#' @param plspm_result \code{run_multiomics_plspm()} 的输出。
#' @param title 图标题。
#'
#' @return 一个 ggplot 对象。
#'
#' @examples
#' \dontrun{
#' export_plot(plot_plspm_r2(res), fig_dir, "plspm_r2")
#' }
#'
#' @export
plot_plspm_r2 <- function(plspm_result, title = NULL) {
  fs <- plspm_result$fit_summary
  if (is.null(fs) || nrow(fs) == 0 || !"R2" %in% colnames(fs)) {
    return(.dbn_empty_plot("No R2 information available.", title))
  }
  df <- fs[fs$R2 > 0, , drop = FALSE]
  if (nrow(df) == 0) {
    return(.dbn_empty_plot("All latent variables are exogenous (R2 = 0).",
                           title))
  }
  df$text <- .dbn_trim(df$latent, 30)
  df <- df[order(df$R2), , drop = FALSE]
  df$text <- factor(df$text, levels = unique(df$text))

  ggplot2::ggplot(df, ggplot2::aes(x = text, y = R2, fill = layer)) +
    ggplot2::geom_col(width = 0.72) +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.3f", R2)),
                       hjust = -0.15, size = 2.7) +
    ggplot2::scale_fill_manual(values = .dbn_layer_colors(df$layer),
                               name = "Omics layer") +
    ggplot2::scale_y_continuous(limits = c(0, 1),
                                expand = ggplot2::expansion(mult = c(0, 0.15))) +
    ggplot2::coord_flip() +
    ggplot2::labs(title = title, x = NULL,
                  y = expression(paste("Explained variance ", R^2))) +
    ggplot2::theme_bw(base_size = 11) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(size = 13, face = "bold"),
      panel.grid.major.y = ggplot2::element_blank())
}

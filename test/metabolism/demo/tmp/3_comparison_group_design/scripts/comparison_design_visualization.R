###############################################################################
#比对组设计可视化脚本
# Comparison Group Design Visualization
#生成展示三组两两比对关系的示意图
###############################################################################

library(ggplot2)

# ============================================================
#1.定义分组和比对信息
# ============================================================

groups <- data.frame(
 group = c("NC", "CD", "FE"),
 full_name = c("Standard (control)\n健康对照", 
 "Clostridium difficile\ninfection\n艰难梭菌感染", 
 "High iron diet before\n感染前高铁饮食干预"),
 n = c(6,6,6),
 color = c("#4CAF50", "#F44336", "#FF9800"),
 stringsAsFactors = FALSE
)

comparisons <- data.frame(
 name = c("FE_vs_CD", "CD_vs_NC", "FE_vs_NC"),
 treatment = c("FE", "CD", "FE"),
 control = c("CD", "NC", "NC"),
 label = c("高铁饮食对CDI的影响\n(核心比对)", 
 "CDI模型验证\n(基线比对)", 
 "高铁饮食+CDI整体效应\n(总体比对)"),
 priority = c(1,2,3),
 stringsAsFactors = FALSE
)

# ============================================================
#2.创建基于ggraph的桑基图风格比对图
# ============================================================

#为绘制连接线创建数据框
#使用网格布局绘制三个组及其比对关系

#设置组的位置坐标
groups$x <- c(1,3,5) # NC, CD, FE的x坐标
groups$y <- c(0,0,0) #同一水平线

#构建连接数据
edges <- data.frame(
 x_start = groups$x[match(comparisons$control, groups$group)],
 x_end = groups$x[match(comparisons$treatment, groups$group)],
 y_start = rep(0,3),
 y_end = rep(0.5,3), #弧线最高点
 label = comparisons$label,
 priority = comparisons$priority,
 stringsAsFactors = FALSE
)

#创建可视化
p <- ggplot() +
 #绘制连接弧线（从control指向treatment）
 geom_curve(data = edges,
 aes(x = x_start, y = y_start, 
 xend = x_end, yend = y_end,
 color = as.factor(priority),
 size = rev(priority)),
 curvature =0.3,
 arrow = arrow(length = unit(0.15, "inches"), type = "closed"),
 lineend = "round") +
 #绘制组节点
 geom_point(data = groups,
 aes(x = x, y = y),
 size =30,
 color = groups$color,
 fill = groups$color,
 shape =21,
 stroke =2) +
 #组名标签
 geom_text(data = groups,
 aes(x = x, y = y, label = full_name),
 size =4,
 fontface = "bold",
 color = "white",
 lineheight =0.9) +
 #样本数标签
 geom_text(data = groups,
 aes(x = x, y = y -0.15, 
 label = paste0("n = ", n)),
 size =3.5,
 color = "white",
 alpha =0.8) +
 #连接线上的比对名称标签
 geom_text(data = edges,
 aes(x = (x_start + x_end)/2, 
 y = y_end +0.12,
 label = label),
 size =3.5,
 fontface = "bold",
 lineheight =0.9) +
 #比对名称标签下方加方向说明
 geom_text(data = edges,
 aes(x = (x_start + x_end)/2, 
 y = y_end +0.05,
 label = paste0(toupper(comparisons$control), " → ", toupper(comparisons$treatment))),
 size =3,
 alpha =0.7) +
 scale_color_manual(values = c("1" = "#E74C3C", "2" = "#3498DB", "3" = "#2ECC71"),
 labels = c("1" = "核心比对 (Priority1)",
 "2" = "模型验证 (Priority2)", 
 "3" = "整体效应 (Priority3)"),
 name = "比对优先级") +
 scale_size_continuous(range = c(0.8,1.5)) +
 #添加标题和注释
 labs(title = "差异分析比对组设计",
 subtitle = "Comparison Group Design for High Iron Diet × CDI Metabolomics Study",
 caption = "箭头方向: Control → Treatment\nFE:感染前高铁饮食干预 | CD:艰难梭菌感染 | NC:健康对照") +
 xlim(0,6) +
 ylim(-0.3,1.0) +
 theme_void(base_size =12) +
 theme(
 plot.title = element_text(hjust =0.5, size =18, face = "bold", margin = margin(b =5)),
 plot.subtitle = element_text(hjust =0.5, size =11, color = "gray40", margin = margin(b =15)),
 plot.caption = element_text(hjust =0.5, size =9, color = "gray60", margin = margin(t =15)),
 legend.position = "bottom",
 legend.box = "horizontal",
 legend.title = element_text(size =10, face = "bold"),
 legend.text = element_text(size =9),
 plot.margin = margin(20,30,20,30)
 ) +
 guides(size = "none")

# ============================================================
#3.保存图片
# ============================================================
ggsave(
 filename = "G:/OmicsWorks/test/metabolism/demo/analysis/3_comparison_group_design/comparison_design_visualization.png",
 plot = p,
 width =12,
 height =7,
 dpi =300,
 bg = "white"
)

cat("可视化图片已保存至: G:/OmicsWorks/test/metabolism/demo/analysis/3_comparison_group_design/comparison_design_visualization.png\n")

# ============================================================
#4.输出比对设计摘要到控制台
# ============================================================
cat("\n==========比对设计摘要 ==========\n")
cat(sprintf("可用生物学分组: %d个\n", nrow(groups)))
cat(sprintf("1. %s: n=%d\n", groups$full_name[1], groups$n[1]))
cat(sprintf("2. %s: n=%d\n", groups$full_name[2], groups$n[2]))
cat(sprintf("3. %s: n=%d\n", groups$full_name[3], groups$n[3]))
cat(sprintf("设计的比对: %d组\n", nrow(comparisons)))
for (i in seq_len(nrow(comparisons))) {
 cat(sprintf(" %d. %s: %s (treatment) vs %s (control)\n", 
 i, comparisons$name[i], comparisons$treatment[i], comparisons$control[i]))
}
cat("\n比对设计CSV已保存至: G:/OmicsWorks/test/metabolism/demo/tmp/3_comparison_group_design/tables/comparison_design.csv\n")
cat("==================================\n")

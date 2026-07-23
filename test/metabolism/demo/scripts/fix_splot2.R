# Fix the S-plot section of the enhanced analysis script
file_path <- "G:/OmicsWorks/test/metabolism/demo/scripts/module_2_enhanced_analysis.R"
lines <- readLines(file_path, warn = FALSE)

# Replace lines408-450 (S-plot section) with a tryCatch-wrapped version
# Find the section boundaries
splot_start <- grep("# OPLSDA S-plot", lines)
splot_end <- grep("# ===========", lines)
splot_end <- splot_end[splot_end > splot_start][1]

cat("Replacing lines", splot_start, "to", (splot_end-1), "\n")

# New S-plot section with tryCatch
new_splot <- c(
 "# OPLSDA S-plot",
 "tryCatch({",
 " loadings <- oplsda_model$loadings$X",
 " if (is.null(loadings) || nrow(loadings) ==0) {",
 " loadings <- oplsda_model$loadings.star$X",
 " }",
 " if (!is.null(loadings) && nrow(loadings) >0) {",
 " loading_vec <- loadings[,1]",
 " ",
 " # Calculate p(corr)",
 " X <- scale(t(expr_matrix), center = TRUE, scale = TRUE)",
 " p_corr <- cor(X, oplsda_scores$predictive)[,1]",
 " ",
 " splot_df <- data.frame(",
 " molecule = names(loading_vec),",
 " p_corr = p_corr[match(names(loading_vec), names(p_corr))],",
 " loading = as.numeric(loading_vec),",
 " VIP = oplsda_vip_df$VIP[match(names(loading_vec), oplsda_vip_df$molecule)],",
 " stringsAsFactors = FALSE",
 " )",
 " ",
 " # Mark significant metabolites",
 " splot_df$significance <- ifelse(",
 " abs(splot_df$p_corr) >0.5 & splot_df$VIP >1,",
 " 'High',",
 " ifelse(abs(splot_df$p_corr) >0.3 & splot_df$VIP >0.8, 'Medium', 'Low')",
 " )",
 " ",
 " # Label top metabolites",
 " top_sig <- splot_df[order(-abs(splot_df$p_corr, na.rm=TRUE)), ]",
 " top_sig <- top_sig[top_sig$significance == 'High', ]",
 " top_labels <- head(top_sig$molecule,15)",
 " splot_df$label <- ifelse(splot_df$molecule %in% top_labels, splot_df$molecule, '')",
 " ",
 " p_splot <- ggplot(splot_df, aes(x = loading, y = p_corr, color = significance)) +",
 " geom_point(alpha =0.6, size =2) +",
 " scale_color_manual(values = c('High' = '#D73027', 'Medium' = '#FDAE61', 'Low' = '#ABD9E9')) +",
 " geom_text(aes(label = label), size =2.5, vjust = -0.5, hjust =0.5, check_overlap = TRUE) +",
 " geom_hline(yintercept = c(-0.5,0.5), linetype = 'dashed', color = 'grey60', alpha =0.5) +",
 " geom_vline(xintercept =0, linetype = 'dotted', color = 'grey60') +",
 " labs(x = 'Loading (p[1])', y = 'Correlation p(corr)[1]',",
 " title = 'OPLSDA S-plot',",
 " color = 'Significance') +",
 " theme_bw(base_size =14) +",
 " theme(plot.title = element_text(hjust =0.5, face = 'bold'))",
 " ",
 " ggsave(file.path(output_dir, 'figures', 'oplsda_splot.png'), p_splot, width =10, height =8, dpi =300)",
 " ggsave(file.path(output_dir, 'figures', 'oplsda_splot.pdf'), p_splot, width =10, height =8)",
 " } else {",
 " cat('Warning: No loadings available for S-plot\\n')",
 " }",
 "}, error = function(e) cat('Warning: S-plot failed:', e$message, '\\n'))"
)

# Replace the section
new_lines <- c(
 lines[1:(splot_start-1)],
 new_splot,
 lines[(splot_end):length(lines)]
)

writeLines(new_lines, file_path)
cat("Replaced S-plot section.\n")

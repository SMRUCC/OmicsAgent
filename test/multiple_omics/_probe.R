setwd('G:/OmicsWorks/agent/rscript')
sink(tempfile()); source('source_all_scripts.R'); sink()
library(ggplot2); library(ggrepel)

dd <- "G:/OmicsWorks/extdata/Tobacco-fermentation"
si <- load_sample_info(file.path(dd, "sampleinfo.csv"))
specs <- list(
  transcriptome = c("expression_transcriptome.csv","featureinfo_transcriptome.csv","gene_id","name"),
  proteome      = c("expression_proteome.csv","featureinfo_proteome.csv","gene_id","name"),
  metabolome    = c("expression_metabolome.csv","featureinfo_metabolome.csv","ID","name"),
  volatilome    = c("expression_volatilome.csv","featureinfo_volatilome.csv","ID","name"),
  microbiome    = c("expression_16s.csv","featureinfo_16s.csv","ID","ID")
)
el <- list(); fl <- list(); mc <- c()
for (nm in names(specs)) {
  s <- specs[[nm]]
  el[[nm]] <- load_expression_matrix(file.path(dd, s[1]))
  fl[[nm]] <- load_feature_info(file.path(dd, s[2]), id_col = s[3])
  mc[nm] <- s[4]
}
mo <- create_multiomics_data(el, si, fl, match_cols = mc)
mo <- preprocess_multiomics(mo, group_col = "condition")

cat("\n== procrustes retry ==\n")
pr <- run_procrustes(get_omics_matrix(mo,"microbiome"), get_omics_matrix(mo,"metabolome"),
                     permutations = 99, verbose = FALSE)
cat("r =", pr$correlation, " p =", pr$p_value, " coords:", paste(colnames(pr$coordinates), collapse=","), "\n")
p <- plot_procrustes(pr, mo$sample_info, "location"); cat("plot_procrustes:", class(p)[1], "\n")

cat("\n== mantel plot ==\n")
ml <- run_mantel_test(get_omics_list(mo),
        env_data = mo$sample_info[, c("temperature_C","humidity_pct","altitude_m")],
        permutations = 99, verbose = FALSE)
p <- plot_mantel_network(ml); cat("plot_mantel_network:", class(p)[1], "\n")

cat("\n== modules (super_class) ==\n")
mods <- build_cross_omics_modules(mo, category_col="super_class", min_size=3)
cat("layers:", paste(names(mods$eigengenes), collapse=", "), "\n")
if (nrow(mods$definitions)) print(utils::head(mods$definitions,4))

cat("\n== pathway bridge ==\n")
br <- tryCatch(run_pathway_bridge(mods), error=function(e){cat("ERR:",conditionMessage(e),"\n");NULL})
if (!is.null(br) && nrow(br$links)) {
  print(utils::head(br$links,4))
  p <- plot_pathway_bridge_heatmap(br); cat("plot_bridge:", class(p)[1], "\n")
}

cat("\n== network ==\n")
cc <- run_cross_correlation(get_omics_matrix(mo,"microbiome"), get_omics_matrix(mo,"volatilome"),
                            r_threshold=0.75, name_x="microbiome", name_y="volatilome", verbose=FALSE)
net <- build_cross_omics_network(list(microbiome_vs_volatilome=cc$pairs), r_threshold=0.75)
if (!is.null(net)) {
  hubs <- get_network_hubs(net, top_n=5)
  print(hubs)
  p <- plot_cross_omics_network(net); cat("plot_network:", class(p)[1], "\n")
}

cat("\n== temporal ==\n")
tj <- run_temporal_trajectory(get_omics_matrix(mo,"volatilome"), mo$sample_info,
                              time_col="day", group_col="location", phase_col="phase")
p <- plot_temporal_trajectory(tj); cat("plot_traj:", class(p)[1], "\n")
tc <- run_temporal_clustering(get_omics_matrix(mo,"volatilome"), mo$sample_info,
                              time_col="day", n_clusters=6)
p <- plot_temporal_clusters(tc); cat("plot_clusters:", class(p)[1], "\n")

cat("\n== diablo ==\n")
db <- run_diablo(mo, group_col="location", ncomp=2)
if (!is.null(db)) {
  cat("fields:", paste(names(db), collapse=", "), "\n")
  cat("scores cols:", paste(colnames(db$scores[[1]]), collapse=","), "\n")
  cat("selected:", nrow(db$selected_features), "\n")
  p <- plot_diablo_scores(db); cat("plot_diablo:", class(p)[1], "\n")
}
cat("\nALL PROBE DONE\n")

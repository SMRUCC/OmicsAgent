suppressMessages({source("g:/OmicsWorks/test/multiple_omics/transcript_demo/config.R")})
c <- readRDS("g:/OmicsWorks/test/multiple_omics/transcript_demo/cache/transcript_pipeline_cache.rds")
cat("de_phase rownames head:", paste(head(rownames(c$de_phase)), collapse = "|"), "\n")
cat("expr_log2 rownames head:", paste(head(rownames(c$expr_log2)), collapse = "|"), "\n")
cat("match de vs expr:", sum(rownames(c$de_phase) %in% rownames(c$expr_log2)), "/", nrow(c$de_phase), "\n")
cat("fi feature_id head:", paste(head(c$feature_info$feature_id), collapse = "|"), "\n")
cat("fi rownames head:", paste(head(rownames(c$feature_info)), collapse = "|"), "\n")
cat("n sig:", sum(c$de_phase$p_adj < 0.05 & abs(c$de_phase$logFC) >= 1, na.rm = TRUE), "\n")
sig <- rownames(c$de_phase)[c$de_phase$p_adj < 0.05 & abs(c$de_phase$logFC) >= 1]
cat("sig head:", paste(head(sig), collapse = "|"), "\n")
cat("sig in fi feature_id:", sum(sig %in% c$feature_info$feature_id), "\n")
sp <- c$feature_info[[3]]
names(sp) <- c$feature_info$feature_id
cat("super_class matched nonNA:", sum(!is.na(sp[intersect(sig, c$feature_info$feature_id)])), "\n")

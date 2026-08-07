ph <- read.csv("results/02_limma_phase.csv")
ph_deg <- sum(as.numeric(ph$p_adj) < 0.05 & abs(as.numeric(ph$logFC)) >= 1)
cat(sprintf("PHASE deg(adj<0.05&|logFC|>=1): %d / %d\n", ph_deg, nrow(ph)))
for (dim in c("super_class","category","family")) {
  d <- read.csv(sprintf("results/03_fisher_%s.csv", dim))
  cat(sprintf("FISHER %s sig(p_adj<0.05): %d / %d\n", dim,
              sum(as.numeric(d$p_adj) < 0.05, na.rm=TRUE), nrow(d)))
}

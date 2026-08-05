cat("R version:", R.version.string, "\n")
pkgs <- c("ggplot2", "tidyr", "dplyr", "reshape2", "data.table")
for (p in pkgs) {
 cat(sprintf("%-15s : %s\n", p, requireNamespace(p, quietly=TRUE)))
}

d <- read.csv("results/03_fisher_super_class.csv")
cat("Columns:", paste(colnames(d), collapse=", "), "\n")
cat("p_value range:", round(min(as.numeric(d$p_value),na.rm=TRUE),4), "-",
    round(max(as.numeric(d$p_value),na.rm=TRUE),4), "\n")
cat("p_adj range:", round(min(as.numeric(d$p_adj),na.rm=TRUE),4), "-",
    round(max(as.numeric(d$p_adj),na.rm=TRUE),4), "\n")
cat("n p_value<0.05:", sum(as.numeric(d$p_value)<0.05,na.rm=TRUE), "\n")
cat("n p_adj<0.05:", sum(as.numeric(d$p_adj)<0.05,na.rm=TRUE), "\n")
# toy check: expected vs observed
cat("top3 by p_value:\n")
print(head(d[order(as.numeric(d$p_value)),], 3))

# Quick test of bnlearn API
library(bnlearn)
data(learning.test)
net <- hc(learning.test)
cat("narcs:", bnlearn::narcs(net), "\n")
cat("num.arcs:", bnlearn::num.arcs(net), "\n")
cat("edges nm:", length(bnlearn::arcs(net)), "\n")
cat("edges nrow:", nrow(bnlearn::arcs(net)), "\n")

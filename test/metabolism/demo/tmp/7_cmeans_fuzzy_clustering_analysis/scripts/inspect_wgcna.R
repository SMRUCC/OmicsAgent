# Inspect WGCNA RData structure
f1 <- "G:/OmicsWorks/test/metabolism/demo/tmp/6_wgcna_trait_association_analysis/wgcna_step2_data.RData"
f2 <- "G:/OmicsWorks/test/metabolism/demo/tmp/6_wgcna_trait_association_analysis/wgcna_step1_data.RData"

cat("=== wgcna_step2_data.RData ===\n")
if (file.exists(f1)) {
 e <- new.env(); load(f1, envir=e)
 cat("Variables:", paste(ls(e), collapse=", "), "\n\n")
 for (vn in ls(e)) {
 cat(sprintf(" %s: class=%s, length=%d\n", vn, class(get(vn, envir=e))[1],
 if(is.vector(get(vn, envir=e))) length(get(vn, envir=e)) else
 if(is.matrix(get(vn,envir=e)) || is.data.frame(get(vn,envir=e))) nrow(get(vn,envir=e)) else NA))
 }
}

cat("\n=== wgcna_step1_data.RData ===\n")
if (file.exists(f2)) {
 e2 <- new.env(); load(f2, envir=e2)
 cat("Variables:", paste(ls(e2), collapse=", "), "\n\n")
 for (vn in ls(e2)) {
 cat(sprintf(" %s: class=%s, length=%d\n", vn, class(get(vn, envir=e2))[1],
 if(is.vector(get(vn, envir=e2))) length(get(vn, envir=e2)) else
 if(is.matrix(get(vn,envir=e2)) || is.data.frame(get(vn,envir=e2))) nrow(get(vn,envir=e2)) else NA))
 }
}

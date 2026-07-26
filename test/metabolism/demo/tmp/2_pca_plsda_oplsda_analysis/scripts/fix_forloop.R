lines <- readLines("G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
# Replace the incomplete for loop at line612 with complete version
new_for_loop <- c(
'for (pw_nm in pairwise_names) {',
' pv <- opls_perm_all$P_Value[opls_perm_all$Comparison == pw_nm]',
' q2v <- opls_params_all$Q2[opls_params_all$Comparison == pw_nm]',
' if (pv <0.05) {',
' cat(sprintf(" => OPLSDA(%s) separation significant (p=%.4f, Q2=%.3f)\\n", pw_nm, pv, q2v))',
' } else {',
' cat(sprintf(" => OPLSDA(%s) separation NOT significant (p=%.4f, Q2=%.3f)\\n", pw_nm, pv, q2v))',
' }',
' if (q2v >=0.4) cat(sprintf(" => OPLSDA(%s) good predictive ability\\n", pw_nm))',
' else if (q2v >=0) cat(sprintf(" => OPLSDA(%s) moderate predictive ability\\n", pw_nm))',
' else cat(sprintf(" => OPLSDA(%s) may be overfitted\\n", pw_nm))',
'}'
)

# Replace lines612-614 (the current broken for loop)
lines[612:614] <- new_for_loop
writeLines(lines, "G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
cat("Fixed summary for loop!\n")

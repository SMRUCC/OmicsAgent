# Fix summary section
lines <- readLines("G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")

# Replace lines597-612 with new summary
new_summary <- c(
'cat(sprintf(" PLSDA permutation p-value: %.4f\\n", p_val_plsda))',
'best_opls <- opls_params_all[which.max(opls_params_all$Q2), ]',
'cat(sprintf(" OPLSDA best model: %s (R2X_pred=%.3f, R2Y=%.3f, Q2=%.3f)\\n",',
' best_opls$Comparison, best_opls$R2X_pred, best_opls$R2Y, best_opls$Q2))',
'cat(sprintf(" PLSDA: VIP>1 metabolites: %d\\n", sum(plsda_vip_out$MeanVIP >1)))',
'for (pw_nm in pairwise_names) {',
' sp_cnt <- sum(all_splot_data[[pw_nm]]$Importance == "High (VIP>1 & |p(corr)|>0.5)")',
' cat(sprintf(" OPLSDA(%s): High-importance metabolites: %d\\n", pw_nm, sp_cnt))',
'}',
'cat("\\n")',
'',
'if (p_val_plsda <0.05) cat(" => PLSDA group separation significant (p<0.05)\\n")',
'else cat(" => PLSDA group separation NOT significant (p>=0.05)\\n")',
'',
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

# Replace lines
lines[597:612] <- new_summary
writeLines(lines, "G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R")
cat("Summary section fixed! Lines597-612 replaced.\n")
cat("New total lines:", length(lines), "\n")

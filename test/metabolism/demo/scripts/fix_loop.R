for (i in1:nrow(combined)) {
 cd_vs_nc_sig <- is_sig(combined$adj.P.Val_CD_vs_NC[i])
 fe_vs_cd_sig <- is_sig(combined$adj.P.Val_FE_vs_CD[i])
 fe_vs_nc_sig <- is_sig(combined$adj.P.Val_FE_vs_NC[i])

 cd_vs_nc_dir <- combined$logFC_CD_vs_NC[i]
 fe_vs_cd_dir <- combined$logFC_FE_vs_CD[i]
 fe_vs_nc_dir <- combined$logFC_FE_vs_NC[i]

 # Pattern1: Protective Rescue
 if (cd_vs_nc_sig && fe_vs_cd_sig) {
 if ((is_up(cd_vs_nc_dir) && is_down(fe_vs_cd_dir)) ||
 (is_down(cd_vs_nc_dir) && is_up(fe_vs_cd_dir))) {
 if (fe_vs_nc_sig) {
 combined$trend_pattern[i] <- "Partial Rescue (still differs from NC)"
 } else {
 combined$trend_pattern[i] <- "Full Rescue (restored to NC)"
 }
 next
 }
 }

 # Pattern2: Unique Protection
 if (fe_vs_cd_sig && !cd_vs_nc_sig) {
 combined$trend_pattern[i] <- "Unique Protection (iron-specific)"
 next
 }

 # Pattern3: Persistent Dysregulation
 if (cd_vs_nc_sig && fe_vs_nc_sig) {
 if ((is_up(cd_vs_nc_dir) && is_up(fe_vs_nc_dir)) ||
 (is_down(cd_vs_nc_dir) && is_down(fe_vs_nc_dir))) {
 combined$trend_pattern[i] <- "Persistent Dysregulation"
 next
 }
 }

 # Pattern4: Iron-specific
 if (fe_vs_cd_sig && fe_vs_nc_sig && !cd_vs_nc_sig) {
 combined$trend_pattern[i] <- "Iron-specific Alteration"
 next
 }

 # Pattern5: CDI-specific
 if (cd_vs_nc_sig && !fe_vs_cd_sig && !fe_vs_nc_sig) {
 combined$trend_pattern[i] <- "CDI-specific Only"
 next
 }
}

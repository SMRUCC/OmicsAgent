# Fix the S-plot p(corr) extraction to calculate manually
import re

with open(r"G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R", "r") as f:
 content = f.read()

# Replace the pcorr_pair extraction
old = " pcorr_pair <- opls_pair@suppLs[[\"mc\"]]"
new = """ # Compute p(corr) manually: correlation between each feature and predictive score
 pred_scores <- opls_pair@scoreMN[,1, drop=FALSE]
 pcorr_pair <- apply(X_pair,2, function(x) cor(x, pred_scores[,1]))"""

assert old in content, f"Could not find: {old}"
content = content.replace(old, new)

with open(r"G:/OmicsWorks/test/metabolism/demo/tmp/2_pca_plsda_oplsda_analysis/scripts/plsda_oplsda_analysis.R", "w") as f:
 f.write(content)

print("Fixed p(corr) calculation!")

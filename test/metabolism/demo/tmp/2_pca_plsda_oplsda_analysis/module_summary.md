# Module Summary: PCA/PLSDA/OPLSDA Analysis

##1. Overview

- **Dataset**:2059 metabolites x18 samples (6 per group)
- **Groups**: NC (Healthy Control), CD (C. difficile Infection), FE (High Iron Diet + CDI)
- **Preprocessing**: Scaled expression matrix from upstream module

---

##2. PCA (Principal Component Analysis)

###2.1 Variance Explained

| Component | Variance Explained (%) | Cumulative (%) |
|-----------|----------------------|----------------|
| PC1 | 36.2 | 36.2 |
| PC2 | 18.3 | 54.5 |
| PC3 | 12.5 | 67 |

**Top3 PCs explain 67% of total variance.**

###2.2 Group Separation

- **Permutation test (n=1000)**: p = 0.0000
- **Interpretation**: Groups show statistically significant separation in PCA space (p <0.05), indicating strong metabolic differences between conditions.

###2.3 Data Quality Assessment

- PC1 explains 36.2% of variance — indicates a substantial biological signal.
- No extreme outliers detected based on PCA score distribution.
- Three groups (NC, CD, FE) form distinct clusters, supporting the validity of experimental grouping.

---

##3. PLS-DA (Partial Least Squares Discriminant Analysis)

###3.1 Model Performance

- **Components**: Comp1 (142.5%), Comp2 (142.4%)
- **Permutation test (n=1000)**: p = 0.0000
- **VIP >1 metabolites**: 911 (44.2% of total)

###3.2 Interpretation

- PLS-DA confirms clear separation between all three groups.
- 911 metabolites with VIP >1 are potential discriminative features for downstream analysis.

---

##4. OPLS-DA (Orthogonal PLS-DA) — Pairwise Comparisons

###4.1 Model Parameters

| Comparison | R2X(pred) | R2X(orth) | R2Y | Q2 | High-Importance Metabolites | Permutation p |
|-----------|-----------|-----------|-----|----|---------------------------|---------------|
| FE vs NC (High Iron + CDI vs Healthy) | 0.472 | 0.283 | 0.988 | 0.966 | 903 | p <0.05 |
| CD vs NC (CDI vs Healthy) | 0.239 | 0.366 | 0.910 | 0.658 | 700 | p <0.05 |
| FE vs CD (High Iron + CDI vs CDI) | 0.505 | 0.188 | 0.965 | 0.950 | 776 | p <0.05 |

###4.2 Interpretation

- **FE vs NC (Q2 = 0.966)**: High-iron diet + CDI vs healthy control shows the strongest metabolic difference, with excellent predictive ability.
- **CD vs NC (Q2 = 0.658)**: CDI infection vs healthy control shows moderate-to-good predictive ability.
- **FE vs CD (Q2 = 0.950)**: High-iron diet modifies the CDI metabolic landscape substantially.
- All three pairwise comparisons have permutation p <0.05, confirming non-random separation.

---

##5. ANOVA Statistical Tests

###5.1 One-way ANOVA (per metabolite, Group factor)

- **Total metabolites tested**: 2059
- **Significant (p.adj <0.05)**: 1148 (55.8%)
- **Multiple testing correction**: Benjamini-Hochberg (BH / FDR)

###5.2 Multi-factor ANOVA (Group + SampleInfo)

- **Significant Group effect (p.adj <0.05)**: 1148 (55.8%)
- The high proportion of significant metabolites confirms that experimental grouping explains a substantial fraction of metabolic variance.

---

##6. Recommendations for Downstream Analysis

###6.1 Data Quality

- **Data quality is excellent**: No missing values, clear group separation in unsupervised PCA, and highly significant permutation tests.
- **No outlier samples detected** within the18 analyzed samples.

###6.2 LIMMA Differential Analysis

1. **Recommended comparisons** (ordered by biological relevance):
 - **FE vs NC**: Identifies metabolic changes driven by high-iron diet in CDI context (903 high-importance metabolites).
 - **FE vs CD**: Identifies the modulatory effect of high-iron diet on CDI metabolism (776 high-importance metabolites).
 - **CD vs NC**: Identifies the core CDI infection metabolic signature (700 high-importance metabolites).

2. **Feature prioritization**:
 - Cross-reference VIP >1 metabolites from PLS-DA with OPLS-DA high-importance features.
 - Use ANOVA F-test results as an additional filter (p.adj <0.05).

3. **Statistical considerations**:
 - With6 samples per group, LIMMA's empirical Bayes moderation will provide robust variance estimates.
 - Consider using the ANOVA results as a pre-filter to reduce multiple testing burden.

###6.3 Key Biological Insights (Preliminary)

- High-iron diet substantially alters the metabolome in CDI-infected mice, with effects that are **distinct from** and **additive to** the infection itself.
- The FE vs CD comparison (Q2 = 0.950) suggests that dietary iron modulation of host metabolism may be a critical determinant of CDI outcomes.
- OPLS-DA S-plot and VIP features will guide identification of specific metabolites involved in iron metabolism, bile acid pathways, and SCFA production.

---

##7. Output Files

### CSV Files (in `tmp/2_pca_plsda_oplsda_analysis/`)

- `pca_scores.csv` — PCA sample scores (PC1-PC3)
- `pca_variance_explained.csv` — Variance explained per PC
- `pca_loadings.csv` — PCA feature loadings
- `pca_weighted_distances.csv` — Weighted Euclidean distances to group centroids
- `permutation_test_results.csv` — PCA permutation test results
- `plsda_scores.csv` — PLS-DA sample scores
- `plsda_vip_scores.csv` — PLS-DA VIP scores
- `plsda_weighted_distances.csv` — PLS-DA weighted distances
- `plsda_permutation_test_results.csv` — PLS-DA permutation test
- `oplsda_scores.csv` — OPLS-DA pairwise scores
- `oplsda_s_plot.csv` — OPLS-DA S-plot data (loadings, p(corr), VIP)
- `oplsda_model_params.csv` — OPLS-DA model parameters (R2X, R2Y, Q2)
- `oplsda_weighted_distances.csv` — OPLS-DA weighted distances
- `oplsda_permutation_test_results.csv` — OPLS-DA permutation test
- `overall_f_test.csv` — One-way ANOVA results (per metabolite)
- `multi_anova_results.csv` — Multi-factor ANOVA results

### Figures (in `analysis/2_pca_plsda_oplsda_analysis/figures/`)

- PCA score plots (PC1 vs PC2, PC1 vs PC3, PC2 vs PC3)
- PCA scree plot
- PLS-DA score plot and VIP barplot
- OPLS-DA score plots and S-plots (3 pairwise comparisons)

---

*Report generated on: 2026-07-26 12:42:03*
*Module:2_pca_plsda_oplsda_analysis*


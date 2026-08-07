# -*- coding: utf-8 -*-
"""Quick exploration of the5 aligned expression matrices for preprocessing decisions."""
import pandas as pd
import numpy as np
import os

BASE = r"G:/OmicsWorks/test/multiple_omics/demo/aligned"
files = {
 "rna": "aligned_rna.csv",
 "proteome": "aligned_proteome.csv",
 "metabolome": "aligned_metabolome.csv",
 "microbiome": "aligned_microbiome.csv",
 "volatilome": "aligned_volatilome.csv",
}

for omics, fname in files.items():
 path = os.path.join(BASE, fname)
 df = pd.read_csv(path, index_col=0)
 mat = df.to_numpy(dtype=float)
 print("=" *70)
 print(f"[{omics}] file={fname} shape={df.shape}")
 print(f" first col name: '{df.columns[0]}', last col: '{df.columns[-1]}'")
 print(f" n_features={df.shape[0]}, n_samples={df.shape[1]}")
 print(f" any NA: {np.isnan(mat).any()}, NA count: {np.isnan(mat).sum()}")
 print(f" any Inf: {np.isinf(mat).any()}")
 print(f" min={mat.min():.6g}, max={mat.max():.6g}")
 print(f" zeros: {np.sum(mat==0)} ({100*np.sum(mat==0)/mat.size:.3f}% of cells)")
 rowmax = mat.max(axis=1)
 rowmed = np.nanmedian(mat, axis=1)
 print(f" row max: median={np.median(rowmax):.4g}, p95={np.percentile(rowmax,95):.4g}, min={np.min(rowmax):.4g}")
 print(f" row median: median={np.median(rowmed):.4g}, min={np.nanmin(rowmed):.4g}")
 print(f" max >100 ? {mat.max() >100} (suggests not log-transformed)")
 colsum = mat.sum(axis=0)
 print(f" column sums: min={colsum.min():.4g}, median={np.median(colsum):.4g}, max={colsum.max():.4g}")

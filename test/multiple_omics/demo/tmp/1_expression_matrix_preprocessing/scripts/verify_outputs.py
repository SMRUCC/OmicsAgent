# -*- coding: utf-8 -*-
"""Final verification: preprocessed matrices must match aligned inputs in shape,
feature ids, and subject_id column names/order. Numeric values only change."""
import pandas as pd
import numpy as np
import os

BASE = r"G:/OmicsWorks/test/multiple_omics/demo/aligned"
MOD = r"G:/OmicsWorks/test/multiple_omics/demo/tmp/1_expression_matrix_preprocessing"
ROOT_TMP = r"G:/OmicsWorks/test/multiple_omics/demo/tmp"

omics_map = ["rna", "proteome", "metabolome", "microbiome", "volatilome"]
all_ok = True

# cross-omics: all raw matrices must share identical subject_id order
raw_cols = {}
for om in omics_map:
 raw = pd.read_csv(os.path.join(BASE, f"aligned_{om}.csv"), index_col=0)
 raw_cols[om] = list(raw.columns)
base_cols = raw_cols[omics_map[0]]
for om in omics_map:
 ok = raw_cols[om] == base_cols
 print(f"[raw {om}] subject_id order identical to {omics_map[0]}: {ok}")
 all_ok = all_ok and ok

for om in omics_map:
 raw = pd.read_csv(os.path.join(BASE, f"aligned_{om}.csv"), index_col=0)
 pre = pd.read_csv(os.path.join(MOD, f"preprocess_{om}.csv"), index_col=0)
 pre2 = pd.read_csv(os.path.join(ROOT_TMP, f"preprocessed_{om}.csv"), index_col=0)

 same_copy = pre.equals(pre2)
 shape_ok = pre.shape == raw.shape
 feat_ok = list(pre.index) == list(raw.index)
 col_ok = list(pre.columns) == list(raw.columns)
 mat = pre.to_numpy(dtype=float)
 no_na = not (np.isnan(mat).any() or np.isinf(mat).any())
 rowmed = np.median(mat, axis=1)
 centered = np.allclose(rowmed,0, atol=1e-8)

 print(f"[{om}] shape={pre.shape} shape_ok={shape_ok} feat_ok={feat_ok} "
 f"col_ok={col_ok} no_na={no_na} median_centered={centered} "
 f"module_vs_root_identical={same_copy}")
 all_ok = all_ok and all([shape_ok, feat_ok, col_ok, no_na, centered, same_copy])

print("\nALL CHECKS PASSED" if all_ok else "SOME CHECKS FAILED")

for om in omics_map:
 pre = pd.read_csv(os.path.join(MOD, f"preprocess_{om}.csv"), index_col=0)
 m = pre.to_numpy(dtype=float)
 print(f"[{om}] out min={m.min():.4g} max={m.max():.4g}")

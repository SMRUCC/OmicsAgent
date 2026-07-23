import pandas as pd
import numpy as np

# Read expression data
df = pd.read_csv("G:/OmicsWorks/test/metabolism/expression.csv", index_col=0)

print(f"Shape: {df.shape}")
print(f"Rows (molecules): {df.shape[0]}")
print(f"Columns (samples): {df.shape[1]}")
print(f"Sample columns: {list(df.columns)}")
print()

# Check for missing values
na_count = df.isna().sum().sum()
print(f"NA/NaN count: {na_count}")

# Check for zeros
zero_count = (df ==0).sum().sum()
print(f"Zero count: {zero_count}")

# Check for negative values
neg_count = (df <0).sum().sum()
print(f"Negative value count: {neg_count}")

# Check data range
all_vals = df.values.flatten()
all_vals = all_vals[~np.isnan(all_vals)]
print(f"\nData range:")
print(f" Min: {np.min(all_vals):.6f}")
print(f" Max: {np.max(all_vals):.6f}")
print(f" Mean: {np.mean(all_vals):.6f}")
print(f" Median: {np.median(all_vals):.6f}")

# Check quantiles
for q in [0.01,0.05,0.25,0.5,0.75,0.95,0.99]:
 print(f" {q*100:.0f}% quantile: {np.quantile(all_vals, q):.6f}")

# Check per-molecule missing (non-NA count)
mol_valid_count = df.notna().sum(axis=1)
print(f"\nMolecules with any missing values: {(df.shape[1] - mol_valid_count >0).sum()}")
if (df.shape[1] - mol_valid_count >0).sum() >0:
 max_missing = (df.shape[1] - mol_valid_count).max()
 print(f"Max missing per molecule: {max_missing}")
 missing_df = pd.DataFrame({
 'molecule': df.index,
 'missing_count': df.shape[1] - mol_valid_count
 })
 missing_df = missing_df[missing_df['missing_count'] >0]
 print(f"Molecules with missing values (first20):")
 print(missing_df.head(20))

# Check column sums
col_sums = df.sum()
print(f"\nColumn sums:")
print(f" Min: {col_sums.min():.4f}")
print(f" Max: {col_sums.max():.4f}")
print(f" Mean: {col_sums.mean():.4f}")
print(f" Std: {col_sums.std():.4f}")

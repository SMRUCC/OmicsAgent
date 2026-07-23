import pandas as pd
import numpy as np

df = pd.read_csv("G:/OmicsWorks/test/metabolism/expression.csv", index_col=0)
print(f"Shape: {df.shape}")
print(f"Min value: {df.min().min()}")
print(f"Max value: {df.max().max()}")
print(f"Number of NA/NaN: {df.isna().sum().sum()}")
print(f"Number of zeros: {(df ==0).sum().sum()}")
print(f"Any value >100: {(df >100).any().any()}")
print(f"Any value >50: {(df >50).any().any()}")
print(f"Any value >10: {(df >10).any().any()}")
# Check column names
print(f"\nColumn names: {list(df.columns)}")
print(f"\nFirst5 rows sample:\n{df.head()}")

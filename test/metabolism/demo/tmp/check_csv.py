import csv, math, sys

with open("G:/OmicsWorks/test/metabolism/expression.csv", "r", newline='') as f:
 reader = csv.reader(f)
 rows = list(reader)

print("Total rows:", len(rows))
print("Total columns:", len(rows[0]))
print("Header (row0):", rows[0][:5])
print("Row1:", rows[1][:5])
print("Row2:", rows[2][:5])
print("Row3:", rows[3][:5])

print("\nNumeric check row1:")
for i in range(1, min(6, len(rows[0]))):
 val = rows[1][i]
 try:
 fval = float(val)
 print(f" Col {i}: {val} -> float={fval}")
 except:
 print(f" Col {i}: {val} -> NOT float")

all_vals = []
for row in rows[1:]:
 for v in row[1:]:
 try:
 all_vals.append(float(v))
 except:
 pass

if all_vals:
 print("\nMin:", min(all_vals))
 print("Max:", max(all_vals))
 print("Mean:", sum(all_vals)/len(all_vals))
 nan_count = sum(1 for v in all_vals if math.isnan(v))
 print("NaN count:", nan_count)
 print("Zero count:", sum(1 for v in all_vals if v ==0))
 print("Negative count:", sum(1 for v in all_vals if v <0))
 print("Total values:", len(all_vals))

print("\nFirst column values:")
print("Row0 col0:", repr(rows[0][0]))
print("Row1 col0:", repr(rows[1][0]))
print("Row2 col0:", repr(rows[2][0]))
print("Row3 col0:", repr(rows[3][0]))

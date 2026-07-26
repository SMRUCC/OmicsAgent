import csv
with open("G:/OmicsWorks/test/metabolism/demo/tmp/preprocessed_expression.csv", "r") as f:
 reader = csv.reader(f)
 for i, row in enumerate(reader):
 if i ==0:
 print("HEADER:", row[:5])
 elif i <=5:
 print(f"Row {i}: {row[:3]}")
 else:
 break
print("---")
with open("G:/OmicsWorks/test/metabolism/metabolites.csv", "r", encoding="utf-8") as f:
 reader = csv.reader(f)
 for i, row in enumerate(reader):
 if i ==0:
 print("ANNO HEADER:", row[:5])
 elif i <=5:
 print(f"Anno Row {i}: {row[:5]}")
 else:
 break

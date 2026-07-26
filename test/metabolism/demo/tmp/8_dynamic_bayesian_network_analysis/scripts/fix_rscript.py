import re

r_file = r"G:/OmicsWorks/test/metabolism/demo/tmp/8_dynamic_bayesian_network_analysis/scripts/run_bayesian_network.R"

with open(r_file, 'r', encoding='utf-8') as f:
 content = f.read()

# Fix1: nedges -> narcs
content = content.replace('bnlearn::nedges(', 'bnlearn::narcs(')

# Fix2: %||% operator -> custom null check
# Replace `module_size_map[[x]] %||% NA` with a function call
content = content.replace('module_size_map[[x]] %||% NA', 
 'ifelse(is.null(module_size_map[[x]]), NA, module_size_map[[x]])')

with open(r_file, 'w', encoding='utf-8') as f:
 f.write(content)

print("Fixed!")

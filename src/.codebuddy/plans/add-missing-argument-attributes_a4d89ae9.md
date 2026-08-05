---
name: add-missing-argument-attributes
overview: 为 Program.vb 中 MakeReport 和 AgentWorkflow 两个函数补充缺失的 `<Argument>` 自定义属性，遵循现有的命令行帮助信息编码模式。
todos:
  - id: add-makereport-args
    content: 为 MakeReport 函数补充 --workspace、--config、--skip-literature、--skip-kb、--report-format 共 5 个 Argument 属性
    status: completed
  - id: add-agentworkflow-args
    content: 为 AgentWorkflow 函数补充 --expression、--annotation、--sampleinfo、--workspace、--config、--skip-literature、--skip-kb、--module、--custom-modules、--report-format、--debug-cache、--make-report 共 12 个 Argument 属性
    status: completed
---

## 用户需求

基于 Program.vb 文件中现有的编码模式，为 MakeReport 和 AgentWorkflow 两个函数补充完整缺失的 `<Argument>` 自定义属性。

## 核心功能

- 为 MakeReport 函数补充缺失的 5 个 Argument 属性（--workspace, --config, --skip-literature, --skip-kb, --report-format）
- 为 AgentWorkflow 函数补充缺失的 12 个 Argument 属性（--expression, --annotation, --sampleinfo, --workspace, --config, --skip-literature, --skip-kb, --module, --custom-modules, --report-format, --debug-cache, --make-report）
- 所有新增 Argument 属性严格遵循现有编码模式：不设 BriefName、Description 引用 HelpText 中已有说明

## 技术栈

- 语言：VB.NET
- 框架：Microsoft.VisualBasic.CommandLine 反射系统
- 属性类：CommandLine.Reflection.ArgumentAttribute
- 修改文件：g:\OmicsWorks\src\Program.vb

## 实现方案

### 实现策略

采用逐参数补充的方式，依次为两个函数添加缺失的 `<Argument>` 自定义属性。所有属性插入到各自函数已有的 `<Argument>` 属性块中，位于 `<Usage>` 与函数声明之间，保持与现有属性的顺序一致性。

### 参数分类与类型映射

| 参数名 | CLI 类型 | 可选性 | 所属函数 |
| --- | --- | --- | --- |
| --workspace | CLITypes.File | True | MakeReport, AgentWorkflow |
| --config | CLITypes.File | True | MakeReport, AgentWorkflow |
| --skip-literature | CLITypes.Boolean | True | MakeReport, AgentWorkflow |
| --skip-kb | CLITypes.Boolean | True | MakeReport, AgentWorkflow |
| --report-format | CLITypes.String | True | MakeReport, AgentWorkflow |
| --expression | CLITypes.File | True | AgentWorkflow |
| --annotation | CLITypes.File | True | AgentWorkflow |
| --sampleinfo | CLITypes.File | True | AgentWorkflow |
| --module | CLITypes.String | True | AgentWorkflow |
| --custom-modules | CLITypes.File | True | AgentWorkflow |
| --debug-cache | CLITypes.Boolean | True | AgentWorkflow |
| --make-report | CLITypes.Boolean | True | AgentWorkflow |


### 关键设计决策

- **--expression/--annotation/--sampleinfo 标记为可选**：这三个参数与 --dataset 互斥（二选一），实际校验由 Opts.ValidateRequiredArgs() 在运行时负责，因此属性层面标记为 optional=True。
- **Boolean 类型参数使用 CLITypes.Boolean**：--skip-literature、--skip-kb、--debug-cache、--make-report 均为无值开关标志。
- **不设置 BriefName**：现有所有 `<Argument>` 属性均未使用 BriefName 命名参数，延续此约定以保持一致性。

## 实现细节

### 目录结构

```
g:\OmicsWorks\src\
└── Program.vb  # [MODIFY] 补充 MakeReport（第 152-154 行之后）和 AgentWorkflow（第 175-177 行之后）的 Argument 属性
```

### 修改位置说明

- **MakeReport 函数**（第 152-154 行区域）：在现有 `--dirs`、`--reference`、`--research` 三个 Argument 属性之后，`Public Async Function MakeReport` 声明之前，插入 5 个新的 `<Argument>` 属性。
- **AgentWorkflow 函数**（第 175-177 行区域）：在现有 `--dataset`、`--research`、`--reference` 三个 Argument 属性之后，`Public Async Function AgentWorkflow` 声明之前，插入 12 个新的 `<Argument>` 属性。

### 性能与可靠性

- 属性为编译时常量元数据，无运行时性能影响。
- Description 字符串直接引用 HelpText 和 Usage 中已有的英文描述，确保帮助信息一致性。
- 不改变任何函数签名或执行逻辑，零回归风险。
---
name: optimize-extract-knowledge-async
overview: 将 ExtractKnowledgeAsync 从"一次性合并所有文献再让LLM分析"改为"逐篇处理→保存中间结果→汇总合并"的三段式流程，避免因 combinedText 截断导致信息丢失。
todos:
  - id: refactor-extract-knowledge
    content: 重写 ExtractKnowledgeAsync 为两阶段流水线：逐篇提取保存 per_doc 中间文件 + 遍历完成后汇总生成 kb.json
    status: completed
  - id: add-per-doc-prompt
    content: 新增 BuildPerDocumentExtractionPrompt 方法，构造单篇文献知识点提取 prompt
    status: completed
    dependencies:
      - refactor-extract-knowledge
  - id: add-summary-prompt
    content: 新增 BuildSummaryPrompt 方法，构造基于所有提炼结果的全局汇总 prompt
    status: completed
    dependencies:
      - refactor-extract-knowledge
---

## 用户需求

优化 `ExtractKnowledgeAsync` 函数的执行逻辑，解决当前一次性将所有文献全文合并后截断导致的严重信息丢失问题。

## 核心改造

将当前"全量合并 + 截断 + 单次 LLM 调用"的粗放模式，改为**两阶段流水线**：

### 第一阶段：逐篇提取

- 使用 for 循环依次处理每篇文献文件
- 每篇文献单独调用 LLM，从该篇文献中提取结构化的生物学知识点
- 每篇提取结果保存为独立的中间 JSON 文件（如 `research_kb/per_doc_1.json`）
- 单篇提取失败时记录警告日志，不中断整体流程，继续处理下一篇

### 第二阶段：汇总生成

- 所有单篇提取完成后，读取全部中间 JSON 文件
- 将所有提炼后的知识点合并，交由 LLM 做一次全局汇总
- 汇总结果去重、整合，生成最终的 `kb.json` 知识库文件

## 预期效果

- 每篇文献的完整内容都会被 LLM 单独阅读分析，不再因截断丢失信息
- 可通过中间文件追溯每篇文献的提取结果，便于调试
- 最终 kb.json 是对所有提炼知识点的二次整合，质量更高

## 技术方案

### 实现策略

将 `ExtractKnowledgeAsync`（当前 211-246 行）重写为两阶段流水线：

**阶段一（逐篇提取）**：

1. for 循环遍历 `referenceFiles`
2. 对每个文件，读取全文，调用新增的 `BuildPerDocumentExtractionPrompt` 构造单篇提取 prompt
3. 通过 `llm.Chat(prompt, cancellationToken)` 获取提取结果
4. 用 `ExtractJsonFromResponse` 提取 JSON，保存为 `per_doc_{i}.json` 到 `_context.KnowledgeDir`
5. try-catch 包裹单篇处理，失败时 `LogInfo("[警告] ...")` 后 continue

**阶段二（全局汇总）**：

1. 读取阶段一生成的所有 `per_doc_*.json` 文件
2. 将所有单篇提取结果拼接为一个汇总文本
3. 调用新增的 `BuildSummaryPrompt` 构造汇总 prompt
4. 通过 `llm.Chat(prompt, cancellationToken)` 获取汇总结果
5. 提取 JSON 保存为最终 `kb.json`
6. 异常时回退到 fallback JSON

### 新增 Prompt 方法设计

- **`BuildPerDocumentExtractionPrompt(researchTopic, docContent, fileName)`**：单篇文献知识点提取 prompt，要求 LLM 输出与当前 `BuildKnowledgeExtractionPrompt` 相同结构但针对单篇的 JSON，包含 `key_genes_proteins`、`key_pathways`、`biological_mechanisms` 等字段
- **`BuildSummaryPrompt(researchTopic, allExtractions)`**：全局汇总 prompt，要求 LLM 基于所有提炼结果，去重整合后输出最终 `kb.json`

### 与现有架构的一致性

- 保持 `Async / Await` 模式
- 复用 `ExtractJsonFromResponse`、`EscapeJson`、`LogInfo` 等现有方法
- 使用 `Using llm = _llmFactory()` 确保 LLM 客户端生命周期正确
- 中间文件命名遵循 `per_doc_{index}.json`，存放于 `_context.KnowledgeDir`

### 性能考量

- 每篇文献一次 LLM 调用，总调用次数 = N + 1（N 篇文献 + 1 次汇总）
- 单篇提取结果文件较小，汇总阶段 LLM 输入量可控
- 可考虑后续扩展为并行调用（当前 for 循环串行，确保与现有代码风格一致且便于调试）

### 错误处理

- 单篇提取失败：LogInfo 警告 + 跳过该篇，不影响其他文献
- 所有文献提取均失败：回退到 `GenerateKnowledgeFromLLMAsync`
- 汇总阶段失败：使用单篇提取结果的简单拼接作为 fallback
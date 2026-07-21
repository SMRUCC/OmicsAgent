# Data 目录

此目录用于存放 KEGG 通路背景模型文件，供富集分析和 GSVA 计算使用。

## 所需文件

### KEGG 通路背景模型

- `kegg_pathways.xml` 或 `kegg_pathways.json`：KEGG 通路背景模型文件
  - 包含所有 KEGG 通路的 ID、名称、分类、所包含的分子 ID 列表
  - 用于富集分析（hypergeometric test）和 GSVA 计算
  - 可从 KEGG 官网下载，或使用 GCModeller 工具生成

## 文件格式说明

### XML 格式示例

```xml
<kegg_background>
  <pathway id="ko00010" name="Glycolysis / Gluconeogenesis" category="Metabolism">
    <molecule id="K00844"/>
    <molecule id="K12407"/>
    ...
  </pathway>
  ...
</kegg_background>
```

### JSON 格式示例

```json
{
  "pathways": [
    {
      "id": "ko00010",
      "name": "Glycolysis / Gluconeogenesis",
      "category": "Metabolism",
      "molecules": ["K00844", "K12407", ...]
    },
    ...
  ]
}
```

## 注意事项

- 若此目录下没有 KEGG 背景模型文件，agent 将尝试使用 R 的 clusterProfiler 包从 KEGG 在线数据库获取
- 建议预先下载背景模型文件，以避免在线获取时的网络延迟和速率限制

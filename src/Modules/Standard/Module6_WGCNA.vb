Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 6: 生物学性状关联分析（WGCNA）
' ============================================================================

''' <summary>
''' 生物学性状关联分析模块（WGCNA）。
''' 
''' 分析内容：
''' 1. 默认按 MAD 值降序排序取 top 20000 个分子做 WGCNA 分析
''' 2. 根据用户研究主题和样本分组信息、元数据信息构建 WGCNA 的生物表型关联性状数据
''' 3. 多组学数据：可将下游组学数据的 GSVA 分析结果作为表型数据，
'''    与上游组学数据的分子表达数据做关联分析
''' 4. 共表达模块与生物学性状值的线性回归分析
''' 5. 共表达模块分子的 KEGG 功能富集分析
''' </summary>
Public Class WGCNAModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "WGCNA Trait Association Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 6

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "wgcna_"
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Function GeneratePlanPromptText() As String
        Return "为 WGCNA 共表达网络分析设计计划，包括以下内容：
1. 按 MAD（中位数绝对偏差）降序选取 top 20000 个分子
2. 构建 WGCNA 共表达网络
   - 确定软阈值幂次（soft threshold power）
   - 构建网络并识别模块
   - 计算模块特征基因（module eigengene）
3. 构建生物学性状数据：
   - 使用样本元数据（分组、品系、时间等）作为性状
   - 多组学场景：将下游组学的 GSVA 得分作为上游组学的性状数据
4. 分析共表达模块与生物学性状的关联
5. 模块与性状值的线性回归分析
6. 模块分子的 KEGG 功能富集分析

# 上下游衔接说明
- 上游输入：读取模块 1 预处理后的表达矩阵（tmp/ 目录下，文件名以 'preprocessed_' 开头）
- 上游输入：读取样本元数据（分组、品系、时间等列）
- 上游输入（多组学）：读取模块 5 的 GSVA 得分作为表型性状数据
- 下游输出：共表达模块结果将供模块 7(CMeans) 做关联对比，结果表供模块 10(表格) 和模块 11(报告) 引用

# 实现要求
- 读取 tmp/ 目录中预处理后的表达矩阵
- 按 MAD 降序选取 top 20000 个分子（若总数不足则全选）
- 使用 pickSoftThreshold 确定软阈值幂次
- 构建 WGCNA 网络：
  - 分块构建网络（block-wise）
  - 模块识别
  - 模块特征基因计算
- 从样本元数据构建性状数据：
  - 对 group、line、time 等列做数值编码
  - 多组学场景：从模块 5 加载 GSVA 得分作为性状
- 计算模块特征基因与性状的相关性（Pearson 相关 + pvalue）
- 对显著相关的性状执行模块 vs 性状的线性回归
- 对每个模块的分子执行 KEGG 富集分析
- 生成以下图形（PNG + PDF，300 dpi，英文标签）：
  - 软阈值幂次选择图
  - 模块聚类树（dendrogram）
  - 模块-性状相关性热图
  - 模块特征基因条形图
  - Hub 基因网络可视化（针对关键模块）
  - 各显著模块的 KEGG 富集点图
- 将模块结果、模块-性状相关性、KEGG 富集结果保存为 CSV

# 绘图要求
- 使用 WGCNA、ggplot2、ComplexHeatmap、clusterProfiler
- 出版级质量主题
- 所有文字标签使用英文
- 同时保存 PNG（300 dpi）和 PDF 两种格式

# 重要注意事项
- 优雅处理缺失的 R 包（如缺失则自动安装）
- WGCNA 内存消耗较大，必要时使用分块处理"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. WGCNA 网络构建的整体情况（soft threshold power、模块数量、模块大小分布）
2. 模块与生物学性状的关联分析结果（哪些模块与哪些性状显著相关）
3. 关键模块的生物学功能（KEGG 富集结果，参考 kb.json 知识库）
4. Hub 基因/分子的识别
5. 多组学关联分析结果（若适用）
6. 共表达模块与生物学性状的线性回归分析结果
7. 分析结果是否支持用户的研究主题，生物学机制的关联性是否存在强相关"
    End Function

End Class

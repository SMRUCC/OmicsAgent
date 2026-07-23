Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 8: 动态贝叶斯网络分析（bnlearn）
' ============================================================================

''' <summary>
''' 动态贝叶斯网络分析模块。
''' 
''' 分析内容：
''' 1. 时间序列数据：进行 bnlearn 动态贝叶斯网络的构建以及后续分析
''' 2. 识别分子/模块之间的调控关系
''' </summary>
Public Class BayesianNetworkModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "Dynamic Bayesian Network Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 8

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "bayesian_"
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Function GeneratePlanPromptText() As String
        Return "为动态贝叶斯网络分析设计计划，使用 bnlearn R 包。
本分析适用于具有充足样本量的时间序列数据。

# 上下游衔接说明
- 上游输入：读取模块 1 预处理后的表达矩阵（tmp/ 目录下，文件名以 'preprocessed_' 开头）
- 上游输入：读取样本信息表中的时间信息
- 上游输入（可选）：读取模块 6(WGCNA) 或模块 7(CMeans) 的模块/聚类结果
- 下游输出：调控网络结果供模块 10(表格) 和模块 11(报告) 引用

# 实现要求
- 动态贝叶斯网络（仅时间序列数据）：
  - 读取表达矩阵和时间信息
  - 使用 bnlearn 构建动态贝叶斯网络
  - 识别调控边
  - 绘制网络图

# 绘图要求
- 使用 bnlearn、igraph、ggplot2
- 出版级质量主题
- 所有文字标签使用英文
- 同时保存 PNG（300 dpi）和 PDF 两种格式

# 重要注意事项
- 优雅处理缺失的 R 包（如缺失则自动安装）
- 若数据非时间序列则跳过本分析
- 重点识别分子/模块之间的关键调控关系"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. 动态贝叶斯网络分析结果（若适用，关键调控关系）
2. 分子/模块之间的调控网络拓扑特征
3. 分析结果是否支持用户的研究主题，生物学机制的关联性是否存在强相关
4. 与前面模块分析结果的一致性和补充性"
    End Function

End Class

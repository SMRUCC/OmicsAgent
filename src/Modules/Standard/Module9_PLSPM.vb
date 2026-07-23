Imports OmicsAgent.AppRuntime

' ============================================================================
' 模块 9: PLS-PM 因果路径分析
' ============================================================================

''' <summary>
''' PLS-PM 因果路径分析模块。
''' 
''' 分析内容：
''' 1. 多组学数据且样本量足够：按不同的组学层次构建潜变量
''' 2. 进行 PLS-PM 因果路径分析
''' </summary>
Public Class PLSPMAnalysisModule : Inherits AnalysisModuleBase

    Public Overrides ReadOnly Property ModuleName As String = "PLS-PM Causal Path Analysis"
    Public Overrides ReadOnly Property ModuleIndex As Integer = 9

    Public Overrides ReadOnly Property CsvFileNamePrefix As String
        Get
            Return "plspm_"
        End Get
    End Property

    Public Sub New(config As AgentConfig, context As AnalysisContext, Optional logger As Action(Of String) = Nothing)
        MyBase.New(config, context, logger)
    End Sub

    Protected Overrides Function GeneratePlanPromptText() As String
        Return "为 PLS-PM（偏最小二乘路径建模）因果路径分析设计计划。
本分析适用于具有充足样本量的多组学数据。

# 上下游衔接说明
- 上游输入：读取模块 1 预处理后的各组学表达矩阵（tmp/ 目录下，文件名以 'preprocessed_' 开头）
- 上游输入（可选）：读取模块 5(KEGG GSVA) 或模块 6(WGCNA 模块特征基因) 的结果作为潜变量
- 下游输出：因果路径分析结果供模块 10(表格) 和模块 11(报告) 引用

# 实现要求
- PLS-PM（仅多组学且样本量充足时）：
  - 为每个组学层次构建潜变量
  - 构建路径模型
  - 估计路径系数
  - 绘制路径图

# 绘图要求
- 使用 plspm、igraph、ggplot2
- 出版级质量主题
- 所有文字标签使用英文
- 同时保存 PNG（300 dpi）和 PDF 两种格式

# 重要注意事项
- 优雅处理缺失的 R 包（如缺失则自动安装）
- 若数据为单组学或样本量不足则跳过本分析
- 重点分析各组学层次之间的因果关系"
    End Function

    Protected Overrides Function GetConclusionItems() As String
        Return "1. PLS-PM 因果路径分析结果（若适用，组学层次间的因果路径）
2. 各组学层次潜变量的构建情况及路径系数
3. 分析结果是否支持用户的研究主题，生物学机制的关联性是否存在强相关
4. 与前面模块分析结果的一致性和补充性"
    End Function

End Class

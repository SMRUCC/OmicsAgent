' ============================================================================
' LLMClient 参考接口定义（用户已有此模块的实际实现）
' ============================================================================
' 此文件仅作为项目编译的接口参考。用户应将其替换为实际的 LLMClient 实现。
' 
' LLMClient 类基于本地安装的 Ollama 大语言模型服务提供 LLM 接入能力，
' 支持对话（Chat）和函数调用（AddFunction）功能。
' ============================================================================

Imports System.Threading
Imports System.Threading.Tasks

''' <summary>
''' LLM 响应结果，包含思考过程和实际输出内容
''' </summary>
Public Class LLMsResponse

    ''' <summary>LLM 的思考过程文本</summary>
    Public Property think As String

    ''' <summary>LLM 的实际输出内容，响应用户的输入</summary>
    Public Property output As String

End Class

''' <summary>
''' 基于 Ollama 的大语言模型客户端，提供对话和函数调用能力。
''' 
''' 注意：此类为接口参考定义。用户应将其替换为实际的 LLMClient 实现。
''' 实际实现应基于本地安装的 Ollama 服务，通过 HTTP API 进行通信。
''' </summary>
Public Class LLMClient
    Implements IDisposable

    Private ReadOnly _serviceUrl As String
    Private ReadOnly _modelName As String
    Private ReadOnly _apiKey As String
    Private ReadOnly _functions As New Dictionary(Of String, Func(Of FunctionCall, String))()
    Private ReadOnly _functionMetadatas As New List(Of FunctionModel)()

    ''' <summary>
    ''' 创建 LLM 客户端实例
    ''' </summary>
    ''' <param name="serviceUrl">Ollama 服务 URL</param>
    ''' <param name="modelName">模型名称</param>
    ''' <param name="apiKey">API Key（可选）</param>
    Public Sub New(serviceUrl As String, modelName As String, Optional apiKey As String = "")
        _serviceUrl = serviceUrl.TrimEnd("/"c)
        _modelName = modelName
        _apiKey = apiKey
    End Sub

    ''' <summary>
    ''' 与 LLM 对话，发送用户消息并获取响应结果
    ''' </summary>
    ''' <param name="prompt_text">发送给 LLM 的提示文本</param>
    ''' <param name="cancellationToken">取消令牌</param>
    ''' <returns>LLM 的响应结果，包含 think 思考文本和 output 实际内容</returns>
    Public Async Function Chat(prompt_text As String, Optional cancellationToken As CancellationToken = Nothing) As Task(Of LLMsResponse)
        ' 实际实现应通过 HTTP POST 调用 Ollama 的 /api/chat 接口
        ' 请求体包含 model、messages、tools（若注册了函数）
        ' 响应体解析出 think 和 output 字段
        ' 
        ' 若 LLM 返回函数调用请求，应自动执行对应函数并将结果回传给 LLM
        ' 直到 LLM 返回最终文本响应
        Await Task.CompletedTask
        Return New LLMsResponse() With {.think = "", .output = ""}
    End Function

    ''' <summary>
    ''' 注册自定义函数工具，供 LLM 函数调用使用
    ''' </summary>
    ''' <param name="func">函数工具元数据，包含函数名、参数信息</param>
    ''' <param name="f">函数调用的 CLR 后端实现</param>
    Public Sub AddFunction(func As FunctionModel, Optional f As Func(Of FunctionCall, String) = Nothing)
        _functionMetadatas.Add(func)
        If f IsNot Nothing Then
            _functions(func.Name) = f
        End If
    End Sub

    ''' <summary>
    ''' 通过反射注册 CLR 对象的指定方法为函数工具
    ''' </summary>
    ''' <typeparam name="T">CLR 对象类型</typeparam>
    ''' <param name="obj">CLR 对象实例，作为函数工具的容器</param>
    ''' <param name="fun">目标函数名，从给定 CLR 对象中获取</param>
    Public Sub AddFunction(Of T)(obj As T, fun As String)
        ' 实际实现应通过反射获取 obj 上的 fun 方法
        ' 解析方法的 DescriptionAttribute 和参数的 ArgumentAttribute
        ' 构造 FunctionModel 并注册
        ' 同时构造一个 Func(Of FunctionCall, String) 委托来调用该方法
    End Sub

    Public Sub Dispose() Implements IDisposable.Dispose
        ' 清理资源
    End Sub

End Class

''' <summary>
''' 函数工具元数据，描述可被 LLM 调用的函数
''' </summary>
Public Class FunctionModel

    Public Property Name As String
    Public Property Description As String
    Public Property Parameters As List(Of ParameterProperties) = New List(Of ParameterProperties)()

    Public Sub New(name As String, description As String, ParamArray parameters As ParameterProperties())
        Me.Name = name
        Me.Description = description
        If parameters IsNot Nothing Then
            Me.Parameters = parameters.ToList()
        End If
    End Sub

End Class

''' <summary>
''' 函数参数属性描述
''' </summary>
Public Class ParameterProperties

    Public Property Name As String
    Public Property Description As String
    Public Property Type As TypeCode

    Public Sub New(name As String, description As String, type As TypeCode)
        Me.Name = name
        Me.Description = description
        Me.Type = type
    End Sub

End Class

''' <summary>
''' LLM 发起的函数调用请求
''' </summary>
Public Class FunctionCall

    Public Property Name As String
    Public Property Arguments As Dictionary(Of String, String) = New Dictionary(Of String, String)()

    Default Public Property Item(key As String) As String
        Get
            Return If(Arguments.ContainsKey(key), Arguments(key), "")
        End Get
        Set(value As String)
            Arguments(key) = value
        End Set
    End Property

End Class

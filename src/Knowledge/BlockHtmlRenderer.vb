Imports System.Runtime.CompilerServices
Imports Microsoft.VisualBasic.Linq
Imports Microsoft.VisualBasic.MIME.text.markdown
Imports Microsoft.VisualBasic.MIME.text.markdown.JSONSchema

''' <summary>
''' 结构化内容块（<see cref="JSONSchema.Block"/>）到 HTML 片段的渲染器。
''' 
''' 底层直接复用 sciBASIC# 的 <see cref="JSONSchema.JSONRenderer.ToHtml"/>，
''' 本模块仅负责空值防御与异常兜底，保证单个坏块不会中断整份报告的生成。
''' </summary>
Module BlockHtmlRenderer

    ''' <summary>
    ''' 将内容块数组渲染为 HTML 片段。
    ''' blocks 为 Nothing 或空数组时返回空串；渲染异常时降级为空串并记录日志。
    ''' </summary>
    <Extension>
    Friend Function RenderBlocks(blocks As JSONSchema.Block(), Optional loginfo As Action(Of String) = Nothing) As String
        If blocks.IsNullOrEmpty Then
            Return ""
        End If

        Try
            Return blocks.Where(Function(b) b IsNot Nothing).ToHtml
        Catch ex As Exception
            If loginfo IsNot Nothing Then
                Call loginfo($"Failed to render content blocks into html: {ex.Message}")
            End If

            Return ""
        End Try
    End Function

End Module

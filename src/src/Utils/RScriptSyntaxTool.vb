Imports System.Text.RegularExpressions

Public Module RScriptFixer

    ' 用于存储提取和修正结果的类
    Public Class RForLoopFix
        Public Property OriginalSnippet As String
        Public Property FixedSnippet As String

        Public Overrides Function ToString() As String
            Return $"{OriginalSnippet} => {FixedSnippet}"
        End Function
    End Class

    '''
    ''' 从 R 脚本中提取 "in关键词后直接跟数字" 的错误 for 循环片段，并返回修正后的内容。
    '''
    ''' <param name="rScript">LLM生成的R脚本字符串</param>
    ''' <returns>包含原始错误片段和修正后片段的列表</returns>
    Private Iterator Function ExtractAndFixForLoopErrors(rScript As String) As IEnumerable(Of RForLoopFix)
        ' 正则表达式解释：
        ' \bfor\s*\(        : 匹配 for 和左括号
        ' \s*[a-zA-Z_]\w*   : 匹配循环变量名 (如 i, var1)
        ' \s+in             : 匹配 in 关键词 (确保前面有空格)
        ' (\d+)             : 捕获组1：匹配紧跟在 in 后面的数字 (这就是错误的特征)
        Dim pattern As String = "\bfor\s*\(\s*[a-zA-Z_]\w*\s+in(\d+)"
        Dim regex As New Regex(pattern, RegexOptions.IgnoreCase)

        Dim matches As MatchCollection = regex.Matches(rScript)

        For Each match As Match In matches
            Dim startIndex As Integer = match.Index
            ' 找到 'for' 后面的第一个左括号 '('
            Dim openParenIndex As Integer = rScript.IndexOf("("c, startIndex)

            If openParenIndex = -1 Then Continue For

            ' 从左括号开始，寻找配对的右括号 ')'，以提取完整的 for(...) 片段
            Dim parenCount As Integer = 1
            Dim endIndex As Integer = openParenIndex

            While parenCount > 0 AndAlso endIndex < rScript.Length - 1
                endIndex += 1
                If rScript(endIndex) = "("c Then
                    parenCount += 1
                ElseIf rScript(endIndex) = ")"c Then
                    parenCount -= 1
                End If
            End While

            If parenCount = 0 Then
                ' 成功找到了完整的 for(...) 代码片段
                Dim originalSnippet As String = rScript.Substring(startIndex, endIndex - startIndex + 1)

                ' 修正语法：在 "in" 和数字之间插入一个空格
                ' 直接对提取出的片段再次使用正则替换
                Dim fixedSnippet As String = FixEntireRScriptSnippet(originalSnippet)

                Yield New RForLoopFix With {
                    .OriginalSnippet = originalSnippet,
                    .FixedSnippet = fixedSnippet
                }
            End If
        Next
    End Function

    Public Function FixEntireRScript(rScript As String) As String
        Dim script As New StringBuilder(rScript)

        For Each snippet In ExtractAndFixForLoopErrors(rScript)
            Call script.Replace(snippet.OriginalSnippet, snippet.FixedSnippet)
        Next

        Return script.ToString
    End Function

    '''
    ''' 直接修正整个 R 脚本字符串，并返回修正后的完整脚本。
    ''' (如果在写回文件时更方便，可以直接使用此方法)
    '''
    Private Function FixEntireRScriptSnippet(rScript As String) As String
        ' 直接全局替换 in紧接数字 的情况
        ' 为了安全，只替换前面有字母变量和空格的 in (如 " i in1")
        Return Regex.Replace(rScript, "(\bin)(\d+)", "$1 $2", RegexOptions.IgnoreCase)
    End Function
End Module

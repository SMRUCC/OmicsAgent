' ============================================================================
' JSON 辅助工具
' ============================================================================
Imports Newtonsoft.Json
Imports Newtonsoft.Json.Linq

Namespace Utils

    ''' <summary>
    ''' JSON 序列化/反序列化辅助方法
    ''' </summary>
    Public Module JsonHelper

        Public Function ToJson(obj As Object, Optional indented As Boolean = False) As String
            If obj Is Nothing Then Return "null"
            Dim settings As New JsonSerializerSettings With {
                .Formatting = If(indented, Formatting.Indented, Formatting.None),
                .NullValueHandling = NullValueHandling.Ignore
            }
            Return JsonConvert.SerializeObject(obj, settings)
        End Function

        Public Function FromJson(Of T)(json As String) As T
            Return JsonConvert.DeserializeObject(Of T)(json)
        End Function

        Public Function Parse(json As String) As JObject
            Return JObject.Parse(json)
        End Function

        Public Function PrettyJson(json As String) As String
            Try
                Dim token = JToken.Parse(json)
                Return token.ToString(Formatting.Indented)
            Catch
                Return json
            End Try
        End Function

    End Module

End Namespace

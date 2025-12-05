{{- define "stack.fullname" -}}
{{- if .Values.stackName -}}
{{ .Values.stackName | lower | replace "_" "-" }}
{{- else -}}
{{ .Release.Name }}
{{- end -}}
{{- end -}}

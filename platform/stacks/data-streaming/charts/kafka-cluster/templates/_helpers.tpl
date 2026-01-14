{{- define "pn-kafka-cluster.name" -}}
{{- default .Chart.Name .Values.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "pn-kafka-cluster.labels" -}}
app.kubernetes.io/name: {{ include "pn-kafka-cluster.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: data-streaming
{{- end -}}

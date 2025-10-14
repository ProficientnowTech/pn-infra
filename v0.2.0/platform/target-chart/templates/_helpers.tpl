{{/*
Target-Chart Helper Templates
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "target-chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "target-chart.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "target-chart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "target-chart.labels" -}}
helm.sh/chart: {{ include "target-chart.chart" . }}
{{ include "target-chart.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "target-chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "target-chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Validate sync wave ordering
*/}}
{{- define "target-chart.validateSyncWaves" -}}
{{- $waves := list }}
{{- range .Values.applications }}
  {{- if .annotations }}
    {{- if index .annotations "argocd.argoproj.io/sync-wave" }}
      {{- $waves = append $waves (index .annotations "argocd.argoproj.io/sync-wave" | int) }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}
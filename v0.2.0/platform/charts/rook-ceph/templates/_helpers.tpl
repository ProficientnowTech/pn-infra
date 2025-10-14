{{/*
Expand the name of the chart.
*/}}
{{- define "rook-ceph.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "rook-ceph.fullname" -}}
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
{{- define "rook-ceph.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "rook-ceph.labels" -}}
helm.sh/chart: {{ include "rook-ceph.chart" . }}
{{ include "rook-ceph.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Values.labels.managed-by | default .Release.Service }}
{{- if .Values.labels.component }}
app.kubernetes.io/component: {{ .Values.labels.component }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "rook-ceph.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rook-ceph.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
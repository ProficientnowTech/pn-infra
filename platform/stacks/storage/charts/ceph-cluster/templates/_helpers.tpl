{{- define "ceph-cluster.namespace" -}}
{{- .Values.namespace | default "rook-ceph" -}}
{{- end -}}

{{- define "ceph-cluster.cephUserSecretName" -}}
{{- printf "rook-ceph-object-user-%s-%s" .store .name -}}
{{- end -}}

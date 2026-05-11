{{- define "harvest-consultations.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "harvest-consultations.harvestImageTag" -}}
{{- $duckdb := .Chart.AppVersion | replace "." "" -}}
{{- default (printf "%s-duckdb%s" .Chart.Version $duckdb) .Values.harvest.image.tag -}}
{{- end }}

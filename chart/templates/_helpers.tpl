{{- define "harvest-consultations.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "harvest-consultations.harvestImageTag" -}}
{{- $duckdb := .Chart.AppVersion | replace "." "" -}}
{{- default (printf "%s-duckdb%s" .Chart.Version $duckdb) .Values.harvest.image.tag -}}
{{- end }}

{{- define "harvest-consultations.harvestImage" -}}
{{- if .Values.harvest.image.digest -}}
{{- printf "%s@%s" .Values.harvest.image.repository .Values.harvest.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.harvest.image.repository (include "harvest-consultations.harvestImageTag" .) -}}
{{- end -}}
{{- end }}

{{- define "harvest-consultations.secretName" -}}
{{- default "db-credentials" .Values.db.existingSecret -}}
{{- end }}

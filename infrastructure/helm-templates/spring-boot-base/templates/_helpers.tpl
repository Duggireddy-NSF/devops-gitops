{{/*
Expand the name of the chart.
*/}}
{{- define "spring-boot-base.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "spring-boot-base.fullname" -}}
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
{{- define "spring-boot-base.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "spring-boot-base.labels" -}}
helm.sh/chart: {{ include "spring-boot-base.chart" . }}
{{ include "spring-boot-base.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ .Values.app.name | default "spring-boot-app" }}
{{- if .Values.github.packages.enabled }}
github.com/package-registry: {{ .Values.github.packages.registry }}
github.com/organization: {{ .Values.github.packages.organization }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "spring-boot-base.selectorLabels" -}}
app.kubernetes.io/name: {{ include "spring-boot-base.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "spring-boot-base.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "spring-boot-base.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the image pull secret name
*/}}
{{- define "spring-boot-base.imagePullSecretName" -}}
{{- if .Values.github.packages.enabled }}
{{- .Values.github.packages.imagePullSecret }}
{{- else }}
{{- "github-packages-secret" }}
{{- end }}
{{- end }}

{{/*
Generate the full image name
*/}}
{{- define "spring-boot-base.image" -}}
{{- printf "%s/%s:%s" .Values.image.registry .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) }}
{{- end }}

{{/*
Generate environment variables for Spring Boot
*/}}
{{- define "spring-boot-base.springEnv" -}}
- name: SPRING_PROFILES_ACTIVE
  value: {{ .Values.app.profile | quote }}
- name: APP_NAME
  value: {{ .Values.app.name | quote }}
- name: APP_VERSION
  value: {{ .Values.app.version | quote }}
{{- end }}

{{/*
Generate common annotations
*/}}
{{- define "spring-boot-base.annotations" -}}
app.kubernetes.io/name: {{ include "spring-boot-base.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ include "spring-boot-base.chart" . }}
{{- if .Values.github.packages.enabled }}
github.com/package-registry: {{ .Values.github.packages.registry }}
{{- end }}
{{- end }}

{{/*
Create ingress host
*/}}
{{- define "spring-boot-base.ingressHost" -}}
{{- if .Values.ingress.hosts }}
{{- range .Values.ingress.hosts }}
{{- .host }}
{{- end }}
{{- else }}
{{- printf "%s.local" (include "spring-boot-base.name" .) }}
{{- end }}
{{- end }}

{{/*
Generate security context
*/}}
{{- define "spring-boot-base.securityContext" -}}
allowPrivilegeEscalation: false
capabilities:
  drop:
  - ALL
readOnlyRootFilesystem: {{ .Values.securityContext.readOnlyRootFilesystem | default false }}
runAsNonRoot: true
runAsUser: {{ .Values.podSecurityContext.runAsUser | default 1001 }}
{{- end }}

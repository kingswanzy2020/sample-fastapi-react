{{/*
Release-scoped name for objects nothing else refers to by a hardcoded name
(ConfigMap, Secret, Jobs, the ServiceAccount).
*/}}
{{- define "fastapi-react.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Labels on every object. "app" is kept alongside the recommended
app.kubernetes.io labels because the runbooks select on it
(kubectl get pods -l app=backend).
*/}}
{{- define "fastapi-react.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | trunc 63 | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{/*
Selector labels for one component. Call with (dict "ctx" $ "component" "backend").
Selectors are immutable on a Deployment, so these never include the version.
*/}}
{{- define "fastapi-react.selectorLabels" -}}
app: {{ .component }}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
{{- end -}}

{{/*
Labels for an object that belongs to one component: the common labels plus
the selector labels, without repeating app.kubernetes.io/instance.
Call with (dict "ctx" $ "component" "backend").
*/}}
{{- define "fastapi-react.componentLabels" -}}
{{ include "fastapi-react.labels" .ctx }}
app: {{ .component }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/*
Full image reference for one of the application images.
Call with (dict "ctx" $ "name" "backend").

The name layout matches docker-compose.yml ("${REGISTRY}/backend") and the ECR
module ("<project>-<env>/backend"), so the same build tags work everywhere.
*/}}
{{- define "fastapi-react.image" -}}
{{- $tag := required "image.tag is required: pass --set image.tag=sha-$(git rev-parse HEAD). Never deploy latest." .ctx.Values.image.tag -}}
{{- $registry := required "image.registry is required (fastapi-react locally, the ECR registry_prefix on EKS)" .ctx.Values.image.registry -}}
{{- printf "%s/%s:%s" $registry .name $tag -}}
{{- end -}}

{{/*
Pod-level security context for the backend image (appuser, UID 1000 -- see
backend/Dockerfile).
*/}}
{{- define "fastapi-react.appPodSecurityContext" -}}
runAsNonRoot: true
runAsUser: 1000
runAsGroup: 1000
fsGroup: 1000
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{/*
Container-level hardening for the backend image. The root filesystem is
read-only; /tmp is an emptyDir because gunicorn keeps worker heartbeat files
there.
*/}}
{{- define "fastapi-react.appContainerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end -}}

{{/*
The env every backend-image container gets: non-secret config plus secrets.
*/}}
{{- define "fastapi-react.appEnvFrom" -}}
- configMapRef:
    name: {{ include "fastapi-react.fullname" . }}-config
- secretRef:
    name: {{ include "fastapi-react.fullname" . }}-secrets
{{- end -}}

{{/*
Spread replicas one per node where possible, and across zones when
topologySpread.zones is on (EKS). Call with (dict "ctx" $ "component" "backend").
*/}}
{{- define "fastapi-react.spreading" -}}
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          topologyKey: kubernetes.io/hostname
          labelSelector:
            matchLabels:
              {{- include "fastapi-react.selectorLabels" . | nindent 14 }}
{{- if .ctx.Values.topologySpread.zones }}
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        {{- include "fastapi-react.selectorLabels" . | nindent 8 }}
{{- end }}
{{- end -}}

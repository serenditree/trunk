{{/*
The name of the service and the component is identical.
*/}}
{{- define "st-default-labels" }}
    app.kubernetes.io/name: {{ .Chart.Name }}
    app.kubernetes.io/version: {{ .Chart.AppVersion }}
    app.kubernetes.io/component: {{ .Chart.Name }}
    app.kubernetes.io/part-of: serenditree
    serenditree.io/otel: {{ .Chart.Name }}
{{- end }}
{{/*
The name of the component is the first part of the service name.
For root-seed "root" is the component and "root-seed" the service name.
*/}}
{{- define "st-default-labels-component" }}
    app.kubernetes.io/name: {{ .Chart.Name }}
    app.kubernetes.io/version: {{ .Chart.AppVersion }}
    app.kubernetes.io/component: {{ regexReplaceAll "-.*" .Chart.Name "" }}
    app.kubernetes.io/part-of: serenditree
    serenditree.io/otel: {{ .Chart.Name }}
{{- end }}
{{/*
For templates that render multiple resources using range-loops like branch.
The service name (.name) and the chart information (.context) are provided separately.
*/}}
{{- define "st-default-labels-range" }}
    app.kubernetes.io/name: {{ .name }}
    app.kubernetes.io/version: {{ .context.Chart.AppVersion }}
    app.kubernetes.io/component: {{ regexReplaceAll "-.*" .name "" }}
    app.kubernetes.io/part-of: serenditree
    serenditree.io/otel: {{ .name }}
{{- end }}

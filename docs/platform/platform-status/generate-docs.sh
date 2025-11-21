#!/bin/bash
# Script to auto-generate chart documentation from cluster data

set -e

DOCS_DIR="/home/devsupreme/work/pn-infra-main/v0.2.0/platform/docs/platform-status/charts"
TEMPLATE="/home/devsupreme/work/pn-infra-main/v0.2.0/platform/docs/platform-status/TEMPLATE.md"

# Charts already documented
SKIP_CHARTS=("temporal" "grafana")

# Function to check if chart is already documented
is_documented() {
    local chart=$1
    for skip in "${SKIP_CHARTS[@]}"; do
        if [ "$chart" == "$skip" ]; then
            return 0
        fi
    done
    return 1
}

# Function to get app info from ArgoCD
get_app_info() {
    local app_name=$1
    kubectl get application -n argocd "$app_name" -o json 2>/dev/null || echo "{}"
}

# Function to get namespace from ArgoCD app
get_namespace() {
    local app_name=$1
    local ns=$(kubectl get application -n argocd "$app_name" -o jsonpath='{.spec.destination.namespace}' 2>/dev/null)
    echo "${ns:-unknown}"
}

# Function to get chart version
get_chart_version() {
    local app_name=$1
    kubectl get application -n argocd "$app_name" -o jsonpath='{.status.summary.images[0]}' 2>/dev/null | cut -d':' -f2 || echo "unknown"
}

# Function to get health status
get_health_status() {
    local app_name=$1
    local status=$(kubectl get application -n argocd "$app_name" -o jsonpath='{.status.health.status}' 2>/dev/null)
    case "$status" in
        "Healthy") echo "✅ Deployed & Operational" ;;
        "Progressing") echo "⚠️ Progressing" ;;
        "Degraded") echo "⚠️ Degraded" ;;
        *) echo "❌ Unknown" ;;
    esac
}

# Function to get ingress URL
get_ingress_url() {
    local ns=$1
    local app=$2
    kubectl get ingress -n "$ns" -o jsonpath='{.items[*].spec.rules[0].host}' 2>/dev/null | tr ' ' '\n' | head -1
}

# Function to check if monitoring is enabled
has_servicemonitor() {
    local ns=$1
    kubectl get servicemonitor -n "$ns" 2>/dev/null | grep -q . && echo "✅ Yes" || echo "❌ No"
}

# Function to get replica count
get_replicas() {
    local ns=$1
    local total=0
    total=$(kubectl get deploy,sts -n "$ns" -o jsonpath='{.items[*].spec.replicas}' 2>/dev/null | tr ' ' '\n' | awk '{s+=$1} END {print s}')
    echo "${total:-0}"
}

# Function to check HA
check_ha() {
    local ns=$1
    local replicas=$(get_replicas "$ns")
    if [ "$replicas" -ge 3 ]; then
        echo "✅ Yes"
    elif [ "$replicas" -ge 2 ]; then
        echo "⚠️ Partial"
    else
        echo "❌ No"
    fi
}

# Function to generate documentation for a chart
generate_chart_doc() {
    local chart_name=$1
    local output_file="$DOCS_DIR/${chart_name}.md"

    if is_documented "$chart_name"; then
        echo "Skipping $chart_name (already documented)"
        return
    fi

    echo "Generating documentation for $chart_name..."

    local ns=$(get_namespace "$chart_name")
    local version=$(get_chart_version "$chart_name")
    local health=$(get_health_status "$chart_name")
    local url=$(get_ingress_url "$ns" "$chart_name")
    local monitoring=$(has_servicemonitor "$ns")
    local ha=$(check_ha "$ns")
    local today=$(date +%Y-%m-%d)

    # Check if app exists in ArgoCD
    if ! kubectl get application -n argocd "$chart_name" &>/dev/null; then
        # Chart exists but not deployed
        cat > "$output_file" <<EOF
# ${chart_name^} - Not Deployed

## Status Overview

| Attribute | Value |
|-----------|-------|
| **Status** | ❌ Not Deployed |
| **Chart Available** | ✅ Yes |
| **Location** | \`platform/charts/${chart_name}\` |

## Notes

This chart is available in the repository but not currently deployed to the cluster.

## Deployment

To deploy this chart, add it to the ArgoCD application manifest in \`target-chart/values-production.yaml\`.

EOF
        return
    fi

    # Generate documentation from template
    cat > "$output_file" <<EOF
# ${chart_name^} - Chart Documentation

## Status Overview

| Attribute | Value |
|-----------|-------|
| **Status** | $health |
| **Version** | $version |
| **Namespace** | \`$ns\` |
| **Deployment Date** | $today |
| **Production Ready** | TBD |
| **Monitoring Enabled** | $monitoring |
| **High Availability** | $ha |

## Quick Links

EOF

    if [ -n "$url" ]; then
        echo "- **URL**: [https://$url](https://$url)" >> "$output_file"
    fi

    cat >> "$output_file" <<'EOF'

## Dependencies

### Hard Dependencies
<!-- Add dependencies that MUST be running -->

### Soft Dependencies
<!-- Add optional dependencies -->

## Architecture

### Components Deployed

<!-- Run: kubectl get deploy,sts,ds -n NAMESPACE -->

## Network Configuration

### External Access
<!-- Document ingress/loadbalancer configuration -->

### Internal Access
<!-- Document service configuration -->

## Production Configuration

### High Availability
- Status: See overview table
- <!-- Add specific HA configuration details -->

### Resource Management
<!-- Document resource requests/limits -->

### Security
<!-- Document security configuration -->

### Persistence
<!-- Document PVCs and storage -->

## Monitoring & Observability

### Metrics
<!-- Document Prometheus metrics -->

### Logs
<!-- Document log aggregation -->

### Alerts
<!-- Document alerting rules -->

## Known Issues

<!-- Document any known issues -->

## Enhancement Opportunities

### High Priority
<!-- Add high priority enhancements -->

### Medium Priority
<!-- Add medium priority enhancements -->

### Low Priority
<!-- Add low priority enhancements -->

## Operational Procedures

### Common Operations

<!-- Add operational procedures -->

## Troubleshooting

### Common Issues

<!-- Add troubleshooting steps -->

## Change Log

### $today
- ✅ Auto-generated documentation template
- ⚠️ Requires manual review and enhancement

## Related Documentation

- [Platform Status](../README.md)
- [Template](../TEMPLATE.md)
EOF

    echo "  Created: $output_file"
}

# Main execution
echo "Starting documentation generation..."
echo "=================================="

# Get all ArgoCD applications
apps=$(kubectl get applications -n argocd -o jsonpath='{.items[*].metadata.name}')

for app in $apps; do
    generate_chart_doc "$app"
done

# Check for charts in directory that aren't deployed
echo ""
echo "Checking for non-deployed charts..."
echo "===================================="

for chart_dir in /home/devsupreme/work/pn-infra-main/v0.2.0/platform/charts/*/; do
    chart_name=$(basename "$chart_dir")
    if ! echo "$apps" | grep -q "$chart_name"; then
        generate_chart_doc "$chart_name"
    fi
done

echo ""
echo "Documentation generation complete!"
echo "=================================="
echo "Generated files in: $DOCS_DIR"
echo ""
echo "Next steps:"
echo "1. Review each generated file"
echo "2. Fill in missing details"
echo "3. Add specific operational procedures"
echo "4. Document dependencies"
echo "5. Commit the changes"

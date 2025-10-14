#!/bin/bash
set -e

# Platform Applications Validation Script
# Validates YAML syntax, ArgoCD application structure, and configuration completeness

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_DIR="$SCRIPT_DIR"
APPLICATIONS_DIR="$PLATFORM_DIR/applications"
VALUES_DIR="$PLATFORM_DIR/values"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

echo -e "${BLUE}=== Platform Applications Validation ===${NC}"
echo "Validating applications in: $APPLICATIONS_DIR"
echo "Validating values in: $VALUES_DIR"
echo

# Function to print status
print_status() {
    local status=$1
    local message=$2
    case $status in
    "OK")
        echo -e "  ${GREEN}✅ $message${NC}"
        ;;
    "WARN")
        echo -e "  ${YELLOW}⚠️  $message${NC}"
        ((WARNINGS++))
        ;;
    "ERROR")
        echo -e "  ${RED}❌ $message${NC}"
        ((ERRORS++))
        ;;
    "INFO")
        echo -e "  ${BLUE}ℹ️  $message${NC}"
        ;;
    esac
}

# Validate YAML syntax
validate_yaml_syntax() {
    local file=$1
    local filename=$(basename "$file")

    if command -v yamllint >/dev/null 2>&1; then
        if yamllint -d relaxed "$file" >/dev/null 2>&1; then
            print_status "OK" "$filename: YAML syntax valid"
        else
            print_status "ERROR" "$filename: YAML syntax errors detected"
        fi
    elif command -v yq >/dev/null 2>&1; then
        if yq eval . "$file" >/dev/null 2>&1; then
            print_status "OK" "$filename: YAML syntax valid (yq)"
        else
            print_status "ERROR" "$filename: YAML syntax errors (yq)"
        fi
    else
        print_status "WARN" "$filename: No YAML validator available (install yamllint or yq)"
    fi
}

# Validate ArgoCD application structure
validate_argocd_app() {
    local file=$1
    local filename=$(basename "$file")

    # Check required fields
    local required_fields=(
        ".apiVersion"
        ".kind"
        ".metadata.name"
        ".metadata.namespace"
        ".spec.project"
        ".spec.sources"
        ".spec.destination.server"
        ".spec.destination.namespace"
    )

    for field in "${required_fields[@]}"; do
        if command -v yq >/dev/null 2>&1; then
            if ! yq eval "$field" "$file" >/dev/null 2>&1 || [[ "$(yq eval "$field" "$file")" == "null" ]]; then
                print_status "ERROR" "$filename: Missing required field $field"
            fi
        fi
    done

    # Check if it's an ArgoCD Application
    if command -v yq >/dev/null 2>&1; then
        local kind=$(yq eval '.kind' "$file" 2>/dev/null)
        local api_version=$(yq eval '.apiVersion' "$file" 2>/dev/null)

        if [[ "$kind" == "Application" && "$api_version" == "argoproj.io/v1alpha1" ]]; then
            print_status "OK" "$filename: Valid ArgoCD Application"
        else
            print_status "ERROR" "$filename: Not a valid ArgoCD Application (kind: $kind, apiVersion: $api_version)"
        fi
    fi
}

# Validate multi-source pattern
validate_multi_source() {
    local file=$1
    local filename=$(basename "$file")

    if command -v yq >/dev/null 2>&1; then
        local sources_count=$(yq eval '.spec.sources | length' "$file" 2>/dev/null)

        if [[ "$sources_count" == "2" ]]; then
            print_status "OK" "$filename: Multi-source pattern detected (2 sources)"

            # Check if one source has valueFiles reference
            local has_value_files=$(yq eval '.spec.sources[0].helm.valueFiles // empty' "$file" 2>/dev/null)
            local has_ref=$(yq eval '.spec.sources[1].ref // empty' "$file" 2>/dev/null)

            if [[ -n "$has_value_files" && "$has_ref" == "values" ]]; then
                print_status "OK" "$filename: Proper multi-source pattern with external values"
            else
                print_status "WARN" "$filename: Multi-source pattern may not be properly configured"
            fi
        elif [[ "$sources_count" == "1" ]]; then
            print_status "WARN" "$filename: Single source pattern (should be multi-source)"
        else
            print_status "ERROR" "$filename: Invalid sources configuration"
        fi
    fi
}

# Validate value file exists
validate_value_file() {
    local app_file=$1
    local filename=$(basename "$app_file" .yaml)
    local expected_values="$VALUES_DIR/${filename}-values.yaml"

    if [[ -f "$expected_values" ]]; then
        print_status "OK" "$filename: Corresponding value file exists"
        validate_yaml_syntax "$expected_values"
    else
        print_status "WARN" "$filename: Expected value file not found: ${filename}-values.yaml"
    fi
}

# Validate sync wave
validate_sync_wave() {
    local file=$1
    local filename=$(basename "$file")

    if command -v yq >/dev/null 2>&1; then
        local sync_wave=$(yq eval '.metadata.annotations."argocd.argoproj.io/sync-wave"' "$file" 2>/dev/null)

        if [[ "$sync_wave" != "null" && -n "$sync_wave" ]]; then
            print_status "OK" "$filename: Sync wave defined: $sync_wave"
        else
            print_status "WARN" "$filename: No sync wave annotation defined"
        fi
    fi
}

# Validate required labels
validate_labels() {
    local file=$1
    local filename=$(basename "$file")

    if command -v yq >/dev/null 2>&1; then
        local has_name=$(yq eval '.metadata.labels."app.kubernetes.io/name"' "$file" 2>/dev/null)
        local has_managed_by=$(yq eval '.metadata.labels."managed-by"' "$file" 2>/dev/null)

        if [[ "$has_name" != "null" && -n "$has_name" ]]; then
            print_status "OK" "$filename: Has app.kubernetes.io/name label"
        else
            print_status "WARN" "$filename: Missing app.kubernetes.io/name label"
        fi

        if [[ "$has_managed_by" == "argocd" ]]; then
            print_status "OK" "$filename: Has managed-by: argocd label"
        else
            print_status "WARN" "$filename: Missing or incorrect managed-by label"
        fi
    fi
}

# Main validation
echo -e "${BLUE}1. Validating Application Files${NC}"

if [[ ! -d "$APPLICATIONS_DIR" ]]; then
    print_status "ERROR" "Applications directory not found: $APPLICATIONS_DIR"
    exit 1
fi

app_count=0
for app_file in "$APPLICATIONS_DIR"/*.yaml; do
    if [[ -f "$app_file" ]]; then
        ((app_count++))
        filename=$(basename "$app_file")
        echo -e "\n${BLUE}Validating: $filename${NC}"

        validate_yaml_syntax "$app_file"
        validate_argocd_app "$app_file"
        validate_multi_source "$app_file"
        validate_sync_wave "$app_file"
        validate_labels "$app_file"
        validate_value_file "$app_file"
    fi
done

echo -e "\n${BLUE}2. Validating Value Files${NC}"

if [[ ! -d "$VALUES_DIR" ]]; then
    print_status "ERROR" "Values directory not found: $VALUES_DIR"
    exit 1
fi

values_count=0
for values_file in "$VALUES_DIR"/*.yaml; do
    if [[ -f "$values_file" ]]; then
        ((values_count++))
        filename=$(basename "$values_file")
        echo -e "\n${BLUE}Validating: $filename${NC}"
        validate_yaml_syntax "$values_file"
    fi
done

echo -e "\n${BLUE}3. Summary${NC}"
print_status "INFO" "Applications validated: $app_count"
print_status "INFO" "Value files validated: $values_count"

if [[ $ERRORS -gt 0 ]]; then
    print_status "ERROR" "Total errors: $ERRORS"
fi

if [[ $WARNINGS -gt 0 ]]; then
    print_status "WARN" "Total warnings: $WARNINGS"
fi

if [[ $ERRORS -eq 0 ]]; then
    print_status "OK" "All validations passed!"
    echo -e "\n${GREEN}✅ Platform applications are ready for deployment${NC}"
else
    echo -e "\n${RED}❌ Platform applications have errors that need to be fixed${NC}"
    exit 1
fi

echo -e "\n${BLUE}4. Deployment Order (by sync-wave)${NC}"
if command -v yq >/dev/null 2>&1; then
    for app_file in "$APPLICATIONS_DIR"/*.yaml; do
        if [[ -f "$app_file" ]]; then
            local name=$(yq eval '.metadata.name' "$app_file" 2>/dev/null)
            local wave=$(yq eval '.metadata.annotations."argocd.argoproj.io/sync-wave"' "$app_file" 2>/dev/null)
            if [[ "$wave" != "null" ]]; then
                echo "  Wave $wave: $name"
            else
                echo "  No wave: $name"
            fi
        fi
    done | sort
fi

echo

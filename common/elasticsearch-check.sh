#!/bin/bash

# Reusable Elasticsearch health check function
# Can be sourced by other scripts
# Location: /home/andrzej/DevOps/common/elasticsearch-check.sh

# Check Elasticsearch health
# Usage: check_elasticsearch_health "url" "username" "password"
# Returns: 0 if healthy, 1 if not
check_elasticsearch_health() {
    local es_url="$1"
    local username="$2"
    local password="$3"
    local auth_flag=""

    # Prepare authentication if credentials provided
    if [ -n "$username" ] && [ -n "$password" ]; then
        auth_flag="-u ${username}:${password}"
    fi

    # Try to connect to Elasticsearch
    local response=$(curl -s $auth_flag -o /dev/null -w "%{http_code}" "$es_url" 2>/dev/null)

    if [ "$response" = "200" ]; then
        return 0
    else
        return 1
    fi
}

# Get Elasticsearch cluster health
# Usage: get_elasticsearch_cluster_health "url" "username" "password"
# Returns: Cluster health status (green/yellow/red) or "unreachable"
get_elasticsearch_cluster_health() {
    local es_url="$1"
    local username="$2"
    local password="$3"
    local auth_flag=""

    # Prepare authentication if credentials provided
    if [ -n "$username" ] && [ -n "$password" ]; then
        auth_flag="-u ${username}:${password}"
    fi

    # Get cluster health
    local health=$(curl -s $auth_flag "${es_url}/_cluster/health" 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

    if [ -n "$health" ]; then
        echo "$health"
    else
        echo "unreachable"
    fi
}

# Get Elasticsearch version
# Usage: get_elasticsearch_version "url" "username" "password"
# Returns: Elasticsearch/OpenSearch version or "unknown"
get_elasticsearch_version() {
    local es_url="$1"
    local username="$2"
    local password="$3"
    local auth_flag=""

    # Prepare authentication if credentials provided
    if [ -n "$username" ] && [ -n "$password" ]; then
        auth_flag="-u ${username}:${password}"
    fi

    # Get version from cluster info
    local version=$(curl -s $auth_flag "$es_url" 2>/dev/null | grep -o '"number":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -n "$version" ]; then
        echo "$version"
    else
        echo "unknown"
    fi
}

# Display Elasticsearch connection info
# Usage: display_elasticsearch_info "url" "username" "password"
display_elasticsearch_info() {
    local es_url="$1"
    local username="$2"
    local password="$3"

    echo "Elasticsearch Connection Details:"
    echo "=================================="
    echo "URL: $es_url"

    if [ -n "$username" ]; then
        echo "Username: $username"
        echo "Authentication: Enabled"
    else
        echo "Authentication: Disabled"
    fi
    echo ""

    # Check connection
    if check_elasticsearch_health "$es_url" "$username" "$password"; then
        local version=$(get_elasticsearch_version "$es_url" "$username" "$password")
        local health=$(get_elasticsearch_cluster_health "$es_url" "$username" "$password")

        echo "✅ Connection: SUCCESS"
        echo "   Version: $version"
        echo "   Cluster Health: $health"

        # Color-code health status
        case "$health" in
            "green")
                echo "   Status: All good!"
                ;;
            "yellow")
                echo "   Status: Warning - Some replicas not allocated"
                ;;
            "red")
                echo "   Status: ERROR - Some primary shards not allocated"
                ;;
            *)
                echo "   Status: Unknown"
                ;;
        esac
    else
        echo "❌ Connection: FAILED"
        echo "   Unable to reach Elasticsearch cluster"
        return 1
    fi

    echo ""
    return 0
}

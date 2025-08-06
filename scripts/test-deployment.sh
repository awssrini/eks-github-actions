#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE=${NAMESPACE:-"confluent-staging"}
TIMEOUT=${TIMEOUT:-300}
TEST_TOPIC="test-deployment-$(date +%s)"

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to wait for pods to be ready
wait_for_pods() {
    local app_label=$1
    local expected_count=${2:-1}
    local timeout=${3:-$TIMEOUT}
    
    log "Waiting for $expected_count pod(s) with label app=$app_label to be ready..."
    
    if kubectl wait --for=condition=ready pod -l app="$app_label" \
        --timeout="${timeout}s" -n "$NAMESPACE" >/dev/null 2>&1; then
        log "✅ Pods with label app=$app_label are ready"
        return 0
    else
        error "❌ Pods with label app=$app_label failed to become ready within ${timeout}s"
        return 1
    fi
}

# Function to check pod status
check_pod_status() {
    local app_label=$1
    
    info "Checking pod status for app=$app_label"
    
    local pods
    pods=$(kubectl get pods -l app="$app_label" -n "$NAMESPACE" --no-headers 2>/dev/null || echo "")
    
    if [ -z "$pods" ]; then
        error "❌ No pods found with label app=$app_label"
        return 1
    fi
    
    echo "$pods" | while read -r pod_info; do
        local pod_name status ready
        pod_name=$(echo "$pod_info" | awk '{print $1}')
        status=$(echo "$pod_info" | awk '{print $3}')
        ready=$(echo "$pod_info" | awk '{print $2}')
        
        if [ "$status" = "Running" ] && [[ "$ready" == *"/"* ]] && [[ "${ready%%/*}" -eq "${ready##*/}" ]]; then
            log "✅ Pod $pod_name is running and ready ($ready)"
        else
            warn "⚠️  Pod $pod_name status: $status, ready: $ready"
        fi
    done
}

# Function to test Kafka connectivity
test_kafka_connectivity() {
    log "Testing Kafka connectivity..."
    
    # Find a Kafka pod
    local kafka_pod
    kafka_pod=$(kubectl get pods -l app=kafka -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" | head -1)
    
    if [ -z "$kafka_pod" ]; then
        error "❌ No Kafka pods found"
        return 1
    fi
    
    log "Using Kafka pod: $kafka_pod"
    
    # Test broker API versions
    if kubectl exec "$kafka_pod" -n "$NAMESPACE" -- \
        kafka-broker-api-versions --bootstrap-server localhost:9092 >/dev/null 2>&1; then
        log "✅ Kafka broker API versions check passed"
    else
        error "❌ Kafka broker API versions check failed"
        return 1
    fi
    
    # Test cluster metadata
    if kubectl exec "$kafka_pod" -n "$NAMESPACE" -- \
        kafka-metadata-shell --snapshot /var/lib/kafka/data/__cluster_metadata-0/00000000000000000000.log --print cluster >/dev/null 2>&1; then
        log "✅ Kafka cluster metadata check passed"
    else
        warn "⚠️  Kafka cluster metadata check failed (may be expected for non-KRaft clusters)"
    fi
}

# Function to test topic operations
test_topic_operations() {
    log "Testing Kafka topic operations..."
    
    local kafka_pod
    kafka_pod=$(kubectl get pods -l app=kafka -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" | head -1)
    
    if [ -z "$kafka_pod" ]; then
        error "❌ No Kafka pods found"
        return 1
    fi
    
    # Create test topic
    log "Creating test topic: $TEST_TOPIC"
    if kubectl exec "$kafka_pod" -n "$NAMESPACE" -- \
        kafka-topics --create --topic "$TEST_TOPIC" --bootstrap-server localhost:9092 \
        --partitions 3 --replication-factor 3 >/dev/null 2>&1; then
        log "✅ Test topic created successfully"
    else
        error "❌ Failed to create test topic"
        return 1
    fi
    
    # List topics to verify creation
    if kubectl exec "$kafka_pod" -n "$NAMESPACE" -- \
        kafka-topics --list --bootstrap-server localhost:9092 | grep -q "$TEST_TOPIC"; then
        log "✅ Test topic found in topic list"
    else
        error "❌ Test topic not found in topic list"
        return 1
    fi
    
    # Describe topic
    if kubectl exec "$kafka_pod" -n "$NAMESPACE" -- \
        kafka-topics --describe --topic "$TEST_TOPIC" --bootstrap-server localhost:9092 >/dev/null 2>&1; then
        log "✅ Topic description retrieved successfully"
    else
        error "❌ Failed to describe test topic"
        return 1
    fi
}

# Function to test producer/consumer
test_producer_consumer() {
    log "Testing Kafka producer/consumer..."
    
    local kafka_pod
    kafka_pod=$(kubectl get pods -l app=kafka -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" | head -1)
    
    if [ -z "$kafka_pod" ]; then
        error "❌ No Kafka pods found"
        return 1
    fi
    
    local test_message="Test message $(date)"
    
    # Produce message
    log "Producing test message..."
    if echo "$test_message" | kubectl exec -i "$kafka_pod" -n "$NAMESPACE" -- \
        kafka-console-producer --topic "$TEST_TOPIC" --bootstrap-server localhost:9092 >/dev/null 2>&1; then
        log "✅ Message produced successfully"
    else
        error "❌ Failed to produce message"
        return 1
    fi
    
    # Wait a moment for message to be committed
    sleep 2
    
    # Consume message
    log "Consuming test message..."
    local consumed_message
    consumed_message=$(kubectl exec "$kafka_pod" -n "$NAMESPACE" -- \
        timeout 10 kafka-console-consumer --topic "$TEST_TOPIC" --bootstrap-server localhost:9092 \
        --from-beginning --max-messages 1 2>/dev/null || echo "")
    
    if [ "$consumed_message" = "$test_message" ]; then
        log "✅ Message consumed successfully and matches produced message"
    else
        error "❌ Message consumption failed or message mismatch"
        log "Expected: $test_message"
        log "Received: $consumed_message"
        return 1
    fi
}

# Function to test Control Center accessibility
test_control_center() {
    log "Testing Control Center accessibility..."
    
    # Check if Control Center service exists
    if ! kubectl get svc controlcenter -n "$NAMESPACE" >/dev/null 2>&1; then
        warn "⚠️  Control Center service not found, skipping test"
        return 0
    fi
    
    # Port forward to Control Center
    log "Setting up port forward to Control Center..."
    kubectl port-forward svc/controlcenter 19021:9021 -n "$NAMESPACE" >/dev/null 2>&1 &
    local port_forward_pid=$!
    
    # Wait for port forward to establish
    sleep 5
    
    # Test HTTP connectivity
    if command_exists curl; then
        if curl -f http://localhost:19021 >/dev/null 2>&1; then
            log "✅ Control Center is accessible via HTTP"
        else
            warn "⚠️  Control Center HTTP check failed"
        fi
    else
        warn "⚠️  curl not available, skipping HTTP connectivity test"
    fi
    
    # Clean up port forward
    kill $port_forward_pid 2>/dev/null || true
}

# Function to test Schema Registry (if available)
test_schema_registry() {
    log "Testing Schema Registry..."
    
    # Check if Schema Registry service exists
    if ! kubectl get svc schemaregistry -n "$NAMESPACE" >/dev/null 2>&1; then
        warn "⚠️  Schema Registry service not found, skipping test"
        return 0
    fi
    
    # Port forward to Schema Registry
    log "Setting up port forward to Schema Registry..."
    kubectl port-forward svc/schemaregistry 18081:8081 -n "$NAMESPACE" >/dev/null 2>&1 &
    local port_forward_pid=$!
    
    # Wait for port forward to establish
    sleep 5
    
    # Test Schema Registry subjects endpoint
    if command_exists curl; then
        if curl -f http://localhost:18081/subjects >/dev/null 2>&1; then
            log "✅ Schema Registry is accessible and responding"
        else
            warn "⚠️  Schema Registry subjects endpoint check failed"
        fi
    else
        warn "⚠️  curl not available, skipping Schema Registry connectivity test"
    fi
    
    # Clean up port forward
    kill $port_forward_pid 2>/dev/null || true
}

# Function to check resource usage
check_resource_usage() {
    log "Checking resource usage..."
    
    # Get resource usage for all pods in namespace
    if command_exists kubectl; then
        info "Current resource usage in namespace $NAMESPACE:"
        kubectl top pods -n "$NAMESPACE" 2>/dev/null || warn "⚠️  Unable to get pod resource usage (metrics server may not be available)"
    fi
    
    # Check for any pods with high restart counts
    local high_restart_pods
    high_restart_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | awk '$4 > 5 {print $1, $4}' || echo "")
    
    if [ -n "$high_restart_pods" ]; then
        warn "⚠️  Pods with high restart counts:"
        echo "$high_restart_pods"
    else
        log "✅ No pods with high restart counts"
    fi
}

# Function to cleanup test resources
cleanup() {
    log "Cleaning up test resources..."
    
    if [ -n "${TEST_TOPIC:-}" ]; then
        local kafka_pod
        kafka_pod=$(kubectl get pods -l app=kafka -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name" | head -1 2>/dev/null || echo "")
        
        if [ -n "$kafka_pod" ]; then
            log "Deleting test topic: $TEST_TOPIC"
            kubectl exec "$kafka_pod" -n "$NAMESPACE" -- \
                kafka-topics --delete --topic "$TEST_TOPIC" --bootstrap-server localhost:9092 >/dev/null 2>&1 || true
        fi
    fi
}

# Function to run all tests
run_all_tests() {
    log "🚀 Starting Confluent deployment tests for namespace: $NAMESPACE"
    
    # Check prerequisites
    if ! command_exists kubectl; then
        error "kubectl is required but not installed"
    fi
    
    # Verify namespace exists
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        error "Namespace $NAMESPACE does not exist"
    fi
    
    local test_results=()
    local failed_tests=0
    
    # Test 1: Check pod status
    log "🧪 Test 1: Checking pod status..."
    if check_pod_status "kafka"; then
        test_results+=("✅ Kafka pod status check")
    else
        test_results+=("❌ Kafka pod status check")
        ((failed_tests++))
    fi
    
    if check_pod_status "controlcenter"; then
        test_results+=("✅ Control Center pod status check")
    else
        test_results+=("⚠️  Control Center pod status check (may not be deployed)")
    fi
    
    # Test 2: Wait for pods to be ready
    log "🧪 Test 2: Waiting for pods to be ready..."
    if wait_for_pods "kafka" 3; then
        test_results+=("✅ Kafka pods ready")
    else
        test_results+=("❌ Kafka pods ready")
        ((failed_tests++))
    fi
    
    # Test 3: Kafka connectivity
    log "🧪 Test 3: Testing Kafka connectivity..."
    if test_kafka_connectivity; then
        test_results+=("✅ Kafka connectivity")
    else
        test_results+=("❌ Kafka connectivity")
        ((failed_tests++))
    fi
    
    # Test 4: Topic operations
    log "🧪 Test 4: Testing topic operations..."
    if test_topic_operations; then
        test_results+=("✅ Topic operations")
    else
        test_results+=("❌ Topic operations")
        ((failed_tests++))
    fi
    
    # Test 5: Producer/Consumer
    log "🧪 Test 5: Testing producer/consumer..."
    if test_producer_consumer; then
        test_results+=("✅ Producer/Consumer")
    else
        test_results+=("❌ Producer/Consumer")
        ((failed_tests++))
    fi
    
    # Test 6: Control Center (optional)
    log "🧪 Test 6: Testing Control Center..."
    if test_control_center; then
        test_results+=("✅ Control Center accessibility")
    else
        test_results+=("⚠️  Control Center accessibility")
    fi
    
    # Test 7: Schema Registry (optional)
    log "🧪 Test 7: Testing Schema Registry..."
    if test_schema_registry; then
        test_results+=("✅ Schema Registry accessibility")
    else
        test_results+=("⚠️  Schema Registry accessibility")
    fi
    
    # Test 8: Resource usage
    log "🧪 Test 8: Checking resource usage..."
    check_resource_usage
    test_results+=("✅ Resource usage check")
    
    # Print test summary
    echo
    log "📊 Test Summary:"
    for result in "${test_results[@]}"; do
        echo "  $result"
    done
    
    echo
    if [ $failed_tests -eq 0 ]; then
        log "🎉 All critical tests passed! Confluent deployment is healthy."
        return 0
    else
        error "💥 $failed_tests critical test(s) failed. Please check the deployment."
        return 1
    fi
}

# Trap for cleanup
trap cleanup EXIT

# Main execution
main() {
    case "${1:-run}" in
        "run"|"test"|"")
            run_all_tests
            ;;
        "kafka")
            test_kafka_connectivity && test_topic_operations && test_producer_consumer
            ;;
        "ui")
            test_control_center && test_schema_registry
            ;;
        "status")
            check_pod_status "kafka"
            check_pod_status "controlcenter"
            check_resource_usage
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [COMMAND]"
            echo "Commands:"
            echo "  run, test    Run all tests (default)"
            echo "  kafka        Test only Kafka functionality"
            echo "  ui           Test only UI components"
            echo "  status       Check deployment status"
            echo "  help         Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  NAMESPACE    Kubernetes namespace (default: confluent-staging)"
            echo "  TIMEOUT      Timeout in seconds for pod readiness (default: 300)"
            ;;
        *)
            error "Unknown command: $1. Use '$0 help' for usage information."
            ;;
    esac
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
#!/bin/bash

################################################################################
# 🤖 Universal Agents Auto-Deployment Script
# Automatically deploys universal-agents.yml to all your repositories
# Usage: bash deploy-universal-agents.sh
################################################################################

set -e

# Configuration
GITHUB_USERNAME="Garrettc123"
GITHUB_TOKEN="${GITHUB_TOKEN}"
WORKFLOW_FILE=".github/workflows/universal-agents.yml"
WORKFLOW_SOURCE_REPO="ai-agent-platform"
TEMP_DIR="/tmp/github-workflow-deploy"
LOG_FILE="deployment-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# UTILITY FUNCTIONS
################################################################################

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}❌ $1${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

check_dependencies() {
    log "Checking dependencies..."
    
    if ! command -v git &> /dev/null; then
        error "git is not installed. Please install git."
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        error "curl is not installed. Please install curl."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Installing..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sudo apt-get update && sudo apt-get install -y jq
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            brew install jq
        fi
    fi
    
    success "All dependencies are available"
}

validate_github_token() {
    if [ -z "$GITHUB_TOKEN" ]; then
        error "GITHUB_TOKEN environment variable is not set"
        error "Please export GITHUB_TOKEN before running this script"
        error "Example: export GITHUB_TOKEN='your_github_token_here'"
        exit 1
    fi
    
    log "Validating GitHub token..."
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        https://api.github.com/user)
    
    if echo "$response" | jq -e '.login' > /dev/null 2>&1; then
        success "GitHub token is valid"
    else
        error "GitHub token validation failed"
        exit 1
    fi
}

fetch_user_repos() {
    log "Fetching all repositories for $GITHUB_USERNAME..."
    
    mkdir -p "$TEMP_DIR"
    
    local page=1
    local per_page=100
    local all_repos=()
    
    while true; do
        log "Fetching page $page..."
        
        response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/users/$GITHUB_USERNAME/repos?page=$page&per_page=$per_page&sort=updated&direction=desc")
        
        if echo "$response" | jq -e '.[0]' > /dev/null 2>&1; then
            repos=$(echo "$response" | jq -r '.[].name')
            all_repos+=($repos)
            ((page++))
        else
            break
        fi
    done
    
    echo "${all_repos[@]}"
}

get_repo_default_branch() {
    local repo=$1
    
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$repo")
    
    echo "$response" | jq -r '.default_branch'
}

check_workflow_exists() {
    local repo=$1
    local branch=$2
    
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$repo/contents/$WORKFLOW_FILE?ref=$branch")
    
    if echo "$response" | jq -e '.sha' > /dev/null 2>&1; then
        echo "true"
    else
        echo "false"
    fi
}

download_workflow() {
    log "Downloading workflow template from $WORKFLOW_SOURCE_REPO..."
    
    workflow_content=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://raw.githubusercontent.com/$GITHUB_USERNAME/$WORKFLOW_SOURCE_REPO/master/$WORKFLOW_FILE")
    
    if [ -z "$workflow_content" ]; then
        error "Failed to download workflow template"
        exit 1
    fi
    
    echo "$workflow_content"
}

deploy_workflow_to_repo() {
    local repo=$1
    local branch=$2
    local workflow_content=$3
    
    log "Deploying workflow to $repo (branch: $branch)..."
    
    # Check if file exists
    file_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$GITHUB_USERNAME/$repo/contents/$WORKFLOW_FILE?ref=$branch")
    
    if echo "$file_info" | jq -e '.sha' > /dev/null 2>&1; then
        # File exists, update it
        sha=$(echo "$file_info" | jq -r '.sha')
        
        encoded_content=$(echo -n "$workflow_content" | base64 -w 0)
        
        response=$(curl -s -X PUT \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Content-Type: application/json" \
            "https://api.github.com/repos/$GITHUB_USERNAME/$repo/contents/$WORKFLOW_FILE" \
            -d "{
                \"message\": \"🤖 Update Universal Agents Workflow\",
                \"content\": \"$encoded_content\",
                \"sha\": \"$sha\",
                \"branch\": \"$branch\"
            }")
    else
        # File doesn't exist, create it
        encoded_content=$(echo -n "$workflow_content" | base64 -w 0)
        
        response=$(curl -s -X PUT \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Content-Type: application/json" \
            "https://api.github.com/repos/$GITHUB_USERNAME/$repo/contents/$WORKFLOW_FILE" \
            -d "{
                \"message\": \"🤖 Add Universal Agents Workflow\",
                \"content\": \"$encoded_content\",
                \"branch\": \"$branch\"
            }")
    fi
    
    if echo "$response" | jq -e '.commit' > /dev/null 2>&1; then
        success "✓ Workflow deployed to $repo"
        return 0
    else
        error "✗ Failed to deploy workflow to $repo"
        echo "$response" | jq '.' >> "$LOG_FILE"
        return 1
    fi
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    log "🤖 Starting Universal Agents Auto-Deployment"
    log "Log file: $LOG_FILE"
    
    # Pre-flight checks
    check_dependencies
    validate_github_token
    
    # Download workflow template
    workflow_content=$(download_workflow)
    success "Workflow template downloaded"
    
    # Get all repositories
    log "Fetching all repositories..."
    repos=($(fetch_user_repos))
    total_repos=${#repos[@]}
    
    if [ $total_repos -eq 0 ]; then
        error "No repositories found for $GITHUB_USERNAME"
        exit 1
    fi
    
    success "Found $total_repos repositories"
    
    # Deploy to each repository
    deployed=0
    skipped=0
    failed=0
    
    log "Starting deployment to repositories..."
    
    for repo in "${repos[@]}"; do
        echo ""
        log "Processing repository: $repo ($(($deployed + $skipped + $failed + 1))/$total_repos)"
        
        # Get default branch
        branch=$(get_repo_default_branch "$repo")
        if [ -z "$branch" ] || [ "$branch" == "null" ]; then
            warning "Could not determine default branch for $repo, skipping..."
            ((skipped++))
            continue
        fi
        
        # Skip source repo itself
        if [ "$repo" == "$WORKFLOW_SOURCE_REPO" ]; then
            success "Skipping source repo $repo"
            ((skipped++))
            continue
        fi
        
        # Deploy workflow
        if deploy_workflow_to_repo "$repo" "$branch" "$workflow_content"; then
            ((deployed++))
            sleep 1  # Rate limiting
        else
            ((failed++))
        fi
    done
    
    # Summary
    echo ""
    echo "==============================================="
    log "🎉 Deployment Complete!"
    echo "==============================================="
    success "Deployed to: $deployed repositories"
    warning "Skipped: $skipped repositories"
    error "Failed: $failed repositories"
    echo "==============================================="
    
    if [ $deployed -gt 0 ]; then
        success "Universal Agents workflow has been deployed!"
        log "Check your repositories at: https://github.com/$GITHUB_USERNAME"
    fi
    
    if [ $failed -gt 0 ]; then
        warning "Some deployments failed. Check $LOG_FILE for details."
    fi
}

# Run main function
main

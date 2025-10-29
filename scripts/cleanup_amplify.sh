#!/bin/bash

# Standalone Amplify Cleanup Script
# Use this if Amplify apps are still showing in the console after running cleanup.sh

set -e

echo "🔧 Amplify Cleanup Script"
echo "========================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} AWS credentials not configured. Please run 'aws configure'."
    exit 1
fi

print_status "Listing all Amplify apps..."

# Get all Amplify apps
ALL_APPS=$(aws amplify list-apps --query 'apps[].[appId,name,defaultDomain]' --output table 2>/dev/null)

if [ -z "$ALL_APPS" ] || [ "$ALL_APPS" = "[]" ]; then
    print_success "No Amplify apps found!"
    exit 0
fi

echo "$ALL_APPS"
echo ""

# Get threat-detection apps specifically
THREAT_APPS=$(aws amplify list-apps --query 'apps[?contains(name, `threat-detection`)].appId' --output text 2>/dev/null || echo "")

if [ -n "$THREAT_APPS" ]; then
    print_warning "Found threat-detection apps: $THREAT_APPS"
    read -p "Delete all threat-detection apps? (y/n): " -r
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        for app_id in $THREAT_APPS; do
            print_status "Deleting app: $app_id"
            aws amplify delete-app --app-id "$app_id"
            print_success "Deleted app: $app_id"
        done
    fi
else
    print_status "No apps with 'threat-detection' in name found."
    
    # Show all apps and let user choose
    echo "All Amplify apps:"
    aws amplify list-apps --query 'apps[].[appId,name]' --output table
    
    read -p "Enter app ID to delete (or 'all' to delete everything, 'n' to cancel): " -r
    
    if [ "$REPLY" = "all" ]; then
        ALL_APP_IDS=$(aws amplify list-apps --query 'apps[].appId' --output text)
        for app_id in $ALL_APP_IDS; do
            print_status "Deleting app: $app_id"
            aws amplify delete-app --app-id "$app_id"
            print_success "Deleted app: $app_id"
        done
    elif [ "$REPLY" != "n" ] && [ -n "$REPLY" ]; then
        print_status "Deleting app: $REPLY"
        aws amplify delete-app --app-id "$REPLY"
        print_success "Deleted app: $REPLY"
    fi
fi

print_success "Amplify cleanup completed!"
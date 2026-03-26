#!/bin/bash

# Auto-push script for tools-cegp-relay
# This script pushes the repository to GitHub

set -e

echo "════════════════════════════════════════════════════════════"
echo "🚀 tools-cegp-relay - Automatic GitHub Push"
echo "════════════════════════════════════════════════════════════"
echo ""

# Check if git is configured
if [ -z "$(git config --global user.email)" ]; then
    echo "Configuring git..."
    git config --global user.email "andre@example.com"
    git config --global user.name "Andre Fernandes"
fi

echo "📍 Repository: https://github.com/andrefernandes86/tools-cegp-relay"
echo ""

# Check if repository exists on GitHub
echo "Checking if repository needs to be created on GitHub..."
echo "1. Go to: https://github.com/new"
echo "2. Repository name: tools-cegp-relay"
echo "3. Description: Enterprise-grade SMTP relay for Trend Micro CEGP"
echo "4. Visibility: PUBLIC"
echo "5. DO NOT initialize with README"
echo "6. Click Create repository"
echo ""
read -p "Press ENTER after creating the repository on GitHub..."
echo ""

# Add remote if not exists
if ! git remote get-url origin &>/dev/null; then
    echo "Adding remote origin..."
    git remote add origin https://github.com/andrefernandes86/tools-cegp-relay.git
fi

# Push
echo "🔑 You'll be prompted for credentials."
echo "   Use your GitHub Personal Access Token (from https://github.com/settings/tokens)"
echo ""
echo "Pushing to GitHub..."
echo ""

git push -u origin main

echo ""
echo "════════════════════════════════════════════════════════════"
echo "✅ SUCCESS! Repository pushed to GitHub!"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "📍 Your repository: https://github.com/andrefernandes86/tools-cegp-relay"
echo ""
echo "🎉 Share it with your team and the community!"
echo ""

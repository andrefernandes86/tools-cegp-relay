#!/bin/bash

# ============================================================================
# tools-cegp-relay GitHub Publishing Script
# ============================================================================

set -e  # Exit on error

echo "🚀 tools-cegp-relay GitHub Publishing Guide"
echo "=============================================="
echo ""

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo "❌ Git is not installed. Please install Git first."
    exit 1
fi

# Get repository information
read -p "Enter your GitHub username: " GITHUB_USERNAME
read -p "Enter repository name (default: tools-cegp-relay): " REPO_NAME
REPO_NAME=${REPO_NAME:-tools-cegp-relay}

GITHUB_URL="https://github.com/${GITHUB_USERNAME}/${REPO_NAME}.git"

echo ""
echo "📋 Configuration:"
echo "  GitHub Username: $GITHUB_USERNAME"
echo "  Repository Name: $REPO_NAME"
echo "  GitHub URL: $GITHUB_URL"
echo ""

read -p "Is this correct? (y/n): " CONFIRM
if [[ $CONFIRM != "y" ]]; then
    echo "❌ Cancelled."
    exit 1
fi

echo ""
echo "📦 Initializing git repository..."
git init

echo "📝 Adding all files..."
git add .

echo "💾 Creating initial commit..."
git commit -m "Initial commit: Enterprise-grade SMTP relay for Trend Micro CEGP with zero message loss guarantee"

echo "🔗 Adding remote repository..."
git remote add origin "$GITHUB_URL"

echo "📤 Pushing to GitHub..."
if git branch -M main 2>/dev/null; then
    echo "Renamed branch to main"
fi

git push -u origin main

echo ""
echo "✅ SUCCESS! Repository pushed to GitHub!"
echo ""
echo "📍 Your repository is now live at:"
echo "   $GITHUB_URL"
echo ""
echo "🎉 Next steps:"
echo "   1. Visit: https://github.com/${GITHUB_USERNAME}/${REPO_NAME}"
echo "   2. Add description in Settings"
echo "   3. Add topics: kubernetes, smtp, email-security, cegp, postfix"
echo "   4. Share the repository!"
echo ""
echo "📚 Documentation starts at: docs/MESSAGE_DELETION_LOGIC.md"
echo ""

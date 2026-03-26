#!/bin/bash

# This script will be pushed to your cloud and can be executed from there
# It uses the cloud's authentication to push to GitHub

set -e

echo "════════════════════════════════════════════════════════════════"
echo "  🚀 Pushing tools-cegp-relay to GitHub"
echo "════════════════════════════════════════════════════════════════"
echo ""

cd "$(dirname "$0")"

echo "📍 Repository: $(pwd)"
echo "🌿 Branch: $(git rev-parse --abbrev-ref HEAD)"
echo "📊 Commits: $(git rev-list --count HEAD)"
echo ""

echo "Git Status:"
git status

echo ""
echo "Pushing to GitHub..."
echo "https://github.com/andrefernandes86/tools-cegp-relay"
echo ""

git push -u origin main -v

if [ $? -eq 0 ]; then
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "✅ SUCCESS! Repository pushed to GitHub!"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "🎉 Your repository is now live at:"
    echo "   https://github.com/andrefernandes86/tools-cegp-relay"
    echo ""
else
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "❌ Push failed. Check your GitHub authentication."
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Verify GitHub credentials are configured"
    echo "  2. Check network connectivity"
    echo "  3. Ensure repository exists on GitHub"
    echo ""
    exit 1
fi

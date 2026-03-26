# Publishing to GitHub

## Prerequisites

```bash
# Install Git
git --version

# Configure Git
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

## Steps to Publish

### 1. Create GitHub Repository

Go to https://github.com/new

- Repository name: `tools-cegp-relay`
- Description: "Enterprise-grade SMTP relay for Trend Micro CEGP with zero message loss guarantee"
- Visibility: **Public** (or Private if preferred)
- DO NOT initialize with README (we have one)
- Click "Create repository"

### 2. Push to GitHub

```bash
cd /home/claude/tools-cegp-relay

# Initialize git repository
git init

# Add all files
git add .

# Commit
git commit -m "Initial commit: Complete CEGP SMTP relay solution with persistent storage"

# Add remote (replace YOUR_USERNAME)
git remote add origin https://github.com/YOUR_USERNAME/tools-cegp-relay.git

# Rename branch to main if on master
git branch -M main

# Push to GitHub
git push -u origin main
```

### 3. Verify on GitHub

- Visit: https://github.com/YOUR_USERNAME/tools-cegp-relay
- Check:
  - README.md displays correctly
  - All files present
  - Directory structure visible

### 4. (Optional) Add GitHub Topics

Go to repo Settings → click "Topics" and add:
- kubernetes
- smtp
- email-security
- cegp
- postfix
- trend-micro
- docker

### 5. (Optional) Add GitHub Actions for CI/CD

Create `.github/workflows/lint.yml`:

```yaml
name: Lint

on: [push, pull_request]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Lint Markdown
        uses: nosborn/github-action-markdown-cli@v3.0.0
        with:
          files: .
```

## Commands Quick Reference

```bash
# Initialize repo
git init
git add .
git commit -m "Initial commit"

# Add remote
git remote add origin https://github.com/YOUR_USERNAME/tools-cegp-relay.git
git branch -M main
git push -u origin main

# Future updates
git add .
git commit -m "Your message"
git push
```

## GitHub Features to Enable

1. **Issues** - Allow community to report bugs
2. **Discussions** - Allow Q&A
3. **Wiki** - Documentation (optional, we have docs/)
4. **Releases** - Tag stable versions

## Release Tags

```bash
# Tag current release
git tag -a v3.0.0 -m "Production ready with persistent storage"
git push origin v3.0.0

# Future releases
git tag -a v3.1.0 -m "Add feature X"
git push origin v3.1.0
```

## README Badges

Add to top of README.md:

```markdown
[![GitHub license](https://img.shields.io/github/license/YOUR_USERNAME/tools-cegp-relay)](LICENSE)
[![GitHub issues](https://img.shields.io/github/issues/YOUR_USERNAME/tools-cegp-relay)](https://github.com/YOUR_USERNAME/tools-cegp-relay/issues)
[![GitHub stars](https://img.shields.io/github/stars/YOUR_USERNAME/tools-cegp-relay)](https://github.com/YOUR_USERNAME/tools-cegp-relay)
```

## Create Releases

On GitHub:
1. Go to "Releases"
2. Click "Create a new release"
3. Tag: v3.0.0
4. Title: "CEGP SMTP Relay v3.0.0 - Production Ready"
5. Description: Copy from CHANGELOG
6. Click "Publish release"

Done! 🚀

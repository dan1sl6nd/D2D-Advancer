# GitHub Pages Setup for D2D Advancer Password Reset

## Step 1: Create GitHub Repository

1. Go to https://github.com/new
2. Repository name: `d2d-password-reset`
3. Make it Public
4. Check "Add a README file"
5. Click "Create repository"

## Step 2: Upload Files

### Option A: Via GitHub Web Interface
1. Click "uploading an existing file"
2. Drag and drop the `password-reset.html` file
3. Rename it to `index.html` 
4. Click "Commit changes"

### Option B: Via Command Line
```bash
# Clone your new repo
git clone https://github.com/YOURUSERNAME/d2d-password-reset.git
cd d2d-password-reset

# Copy the HTML file
cp "/Users/dan1sland/Documents/XCode Projects/D2D Advancer/password-reset.html" ./index.html

# Commit and push
git add index.html
git commit -m "Add password reset page"
git push origin main
```

## Step 3: Enable GitHub Pages
1. Go to your repo → Settings tab
2. Scroll down to "Pages" section
3. Source: "Deploy from a branch"
4. Branch: "main"
5. Folder: "/ (root)"
6. Click "Save"

## Step 4: Get Your URL
After a few minutes, your page will be live at:
`https://YOURUSERNAME.github.io/d2d-password-reset`

## Step 5: Update Supabase
Go to Supabase Dashboard → Authentication → URL Configuration:
- **Site URL**: `https://YOURUSERNAME.github.io/d2d-password-reset`
- **Redirect URLs**: `https://YOURUSERNAME.github.io/d2d-password-reset`

Replace `YOURUSERNAME` with your actual GitHub username.
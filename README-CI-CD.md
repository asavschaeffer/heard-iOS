# 🚀 Heard iOS App - CI/CD Setup

## 📱 GitHub Actions → TestFlight Workflow

This repo is configured for automatic iOS builds and TestFlight deployment!

### 🔄 How It Works

1. **Write code on any platform** (PC, Mac, etc.)
2. **Push to GitHub** → Automatic build triggers
3. **GitHub Actions builds** the iOS app on macOS
4. **Deploys to TestFlight** → Install on your phone
5. **Test on real device** → Repeat cycle

### 🛠️ Required GitHub Secrets

Go to your GitHub repo → Settings → Secrets and variables → Actions → Add these:

```
GEMINI_API_KEY=your_google_gemini_api_key
APPSTORE_ISSUER_ID=your_issuer_id_from_app_store_connect
APPSTORE_API_KEY_ID=your_api_key_id_from_app_store_connect  
APPSTORE_API_KEY=-----BEGIN PRIVATE KEY-----
[Your API Key Content Here]
-----END PRIVATE KEY-----
```

### 📋 How to Get App Store Connect Keys

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. **Users and Access** → **Keys**
3. Click **"+"** → **App Store Connect API**
4. Enter **Key Name** (e.g., "GitHub Actions")
5. Select **App Manager** role
6. Download **.p8** file - this is your `APPSTORE_API_KEY`
7. Copy **Key ID** - this is `APPSTORE_API_KEY_ID`  
8. Copy **Issuer ID** - this is `APPSTORE_ISSUER_ID`

### 🚀 Triggering Builds

#### Automatic (on push):
```bash
git add .
git commit -m "New feature"
git push origin master
```

#### Manual (from GitHub):
1. Go to **Actions** tab in your repo
2. Select **"Build and Deploy to TestFlight"**
3. Click **"Run workflow"**
4. Add release notes (optional)
5. Click **"Run workflow"**

#### Manual (from CLI):
```bash
gh workflow run "Build and Deploy to TestFlight" \
  --field release_notes="Updated Gemini integration"
```

### 📱 Installing on Your Device

1. **Check TestFlight app** on your iPhone
2. **Accept invitation** (email or TestFlight app)
3. **Install "Chef AI"** app
4. **Trust developer** (first time only):
   - Settings → General → VPN & Device Management → Trust

### 🔧 Local Development Setup

For local builds, ensure your Gemini API key is configured:

```bash
# Edit secrets file
open app/Secrets.xcconfig
# Replace placeholder with your actual Gemini key
```

### 🌍 Development Workflow

#### On PC/Windows/Linux:
1. **Clone repo:** `git clone [your-repo-url]`
2. **Edit code:** Use VS Code with Swift extensions
3. **Push changes:** `git push` → Builds automatically
4. **Test on device:** Wait for TestFlight notification

#### Complete Cycle:
```
Write Swift on PC → Push to GitHub → Auto-build → TestFlight → Install on iPhone → Test
```

### 📊 Monitoring

- **Build logs:** GitHub Actions tab
- **TestFlight:** App Store Connect dashboard
- **Crash reports:** TestFlight analytics
- **API usage:** Google AI console

### 🎯 Branch Strategy

- **`master`** → Production builds → TestFlight
- **`develop`** → Development builds → TestFlight
- **feature branches** → No auto-deploy (manual trigger only)

### 🚨 Troubleshooting

**Build fails:**
- Check GitHub Actions logs
- Verify API secrets are correct
- Ensure Xcode project builds locally

**TestFlight issues:**
- Check App Store Connect permissions
- Verify provisioning profiles
- Wait a few minutes for processing

**Device issues:**
- Reinstall TestFlight app
- Restart iPhone
- Check iOS version compatibility

### 🔄 Continuous Integration

This setup gives you:
- ✅ **Cloud-based iOS builds**
- ✅ **Automatic TestFlight deployment**
- ✅ **No Mac required for development**
- ✅ **Real device testing**
- ✅ **Version control integration**
- ✅ **Build artifact preservation**

---

**Ready to go! Just push code and it builds automatically!** 🚀
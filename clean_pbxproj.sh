#!/bin/bash

# Stop on first error
set -e

PBXPROJ="PostgresGUI.xcodeproj/project.pbxproj"

if [ ! -f "$PBXPROJ" ]; then
    echo "❌ File $PBXPROJ not found. Please run this script from the project root."
    exit 1
fi

# Define variables using arguments or defaults
TEAM_ID=${1:-""}
BUNDLE_PREFIX=${2:-"com.localbuild"}

echo "🧹 Cleaning up project credentials..."

if [ -z "$TEAM_ID" ]; then
    echo "⚠️ No Team ID provided. Removing original Team ID..."
    sed -i '' 's/DEVELOPMENT_TEAM = 75KGPEX6ZF;/DEVELOPMENT_TEAM = "";/g' "$PBXPROJ"
else
    echo "🔑 Applying your Team ID ($TEAM_ID)..."
    sed -i '' "s/DEVELOPMENT_TEAM = 75KGPEX6ZF;/DEVELOPMENT_TEAM = $TEAM_ID;/g" "$PBXPROJ"
    sed -i '' "s/DEVELOPMENT_TEAM = \"\";/DEVELOPMENT_TEAM = $TEAM_ID;/g" "$PBXPROJ"
fi

echo "📦 Applying Bundle Identifier ($BUNDLE_PREFIX)..."
sed -i '' "s/PRODUCT_BUNDLE_IDENTIFIER = com.mghazi./PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_PREFIX./g" "$PBXPROJ"

echo "✅ File project.pbxproj successfully updated!"

if [ -z "$TEAM_ID" ]; then
    echo "⚠️ IMPORTANT: Because no Team ID was provided, you MUST open Xcode to select your Personal Team before building."
else
    echo "🚀 Ready to build! You can now run ./build_dmg.sh without opening Xcode."
fi

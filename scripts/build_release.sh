#!/usr/bin/env bash
# ============================================================
# بناء نسخة تثبيت موقّعة تلقائيًا بضغطة واحدة (لينكس / ماك)
# الاستخدام:  ./scripts/build_release.sh
# الناتج:     build/app/outputs/flutter-apk/app-release.apk
# ============================================================
set -e
cd "$(dirname "$0")/.."

echo "🔄 1/3) جلب الاعتماديات..."
flutter pub get

echo "🎨 2/3) توليد أيقونة التطبيق..."
dart run flutter_launcher_icons || true

echo "📦 3/3) بناء نسخة الإفراج الموقّعة..."
flutter build apk --release

echo ""
echo "✅ تم البناء بنجاح. ملف التثبيت الموقّع:"
echo "   build/app/outputs/flutter-apk/app-release.apk"

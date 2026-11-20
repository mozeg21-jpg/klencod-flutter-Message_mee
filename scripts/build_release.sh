#!/usr/bin/env bash
# ============================================================
# بناء نسخة تثبيت موقّعة تلقائيًا بضغطة واحدة (لينكس / ماك)
# الاستخدام:  ./scripts/build_release.sh
# الناتج:     build/app/outputs/flutter-apk/app-release.apk
# ============================================================
set -e
cd "$(dirname "$0")/.."

echo "🔄 1/4) جلب الاعتماديات..."
flutter pub get

echo "🔑 2/4) تجهيز مفتاح التوقيع..."
if [ ! -s android/app/release-key.jks ] && [ -s android/signing/release-key.jks.b64 ]; then
  mkdir -p android/app
  base64 -d android/signing/release-key.jks.b64 > android/app/release-key.jks
  cp android/signing/key.properties android/key.properties
  echo "    تم استعادة release-key.jks من مجلد android/signing/."
elif [ ! -s android/app/release-key.jks ]; then
  echo "    تحذير: مفتاح release غير متوفر؛ Gradle سيستخدم توقيع debug التلقائي."
  echo "    الـ APK يبقى موقّعًا وقابلًا للتثبيت في كل الأحوال."
  rm -f android/key.properties
fi

echo "🎨 3/4) توليد أيقونة التطبيق..."
dart run flutter_launcher_icons

echo "📦 4/4) بناء نسخة الإفراج الموقّعة..."
flutter build apk --release

echo ""
echo "✅ تم البناء بنجاح. ملف التثبيت الموقّع:"
echo "   build/app/outputs/flutter-apk/app-release.apk"

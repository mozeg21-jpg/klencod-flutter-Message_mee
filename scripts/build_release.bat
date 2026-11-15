@echo off
REM ============================================================
REM بناء نسخة تثبيت موقّعة تلقائيًا بضغطة واحدة (ويندوز)
REM الناتج: build\app\outputs\flutter-apk\app-release.apk
REM ============================================================
cd /d "%~dp0.."

echo [1/3] جلب الاعتماديات...
call flutter pub get
if errorlevel 1 goto :err

echo [2/3] توليد أيقونة التطبيق...
call dart run flutter_launcher_icons

echo [3/3] بناء نسخة الإفراج الموقّعة...
call flutter build apk --release
if errorlevel 1 goto :err

echo.
echo [OK] تم البناء: build\app\outputs\flutter-apk\app-release.apk
pause
exit /b 0

:err
echo.
echo [X] فشل البناء، راجع الرسائل بالأعلى.
pause
exit /b 1

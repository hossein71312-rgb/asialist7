import os, re, sys
m = 'android/app/src/main/AndroidManifest.xml'
s = open(m, encoding='utf-8').read()
perm = '<uses-permission android:name="android.permission.CAMERA"/>\n    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n    '
s = s[:s.index('<application')] + perm + s[s.index('<application'):]
s = re.sub(r'android:label="[^"]*"', 'android:label="آسیا - قیمت و انبار"', s, count=1)
open(m, 'w', encoding='utf-8').write(s)
print('manifest patched')

if os.path.exists('android/key.properties'):
    kts = 'android/app/build.gradle.kts'
    gr = 'android/app/build.gradle'
    if os.path.exists(kts):
        t = open(kts, encoding='utf-8').read()
        block = '''    signingConfigs {
        create("release") {
            val props = Properties()
            val kf = rootProject.file("key.properties")
            if (kf.exists()) { props.load(FileInputStream(kf)) }
            keyAlias = props.getProperty("keyAlias")
            keyPassword = props.getProperty("keyPassword")
            val sf = props.getProperty("storeFile")
            if (sf != null) { storeFile = file(sf) }
            storePassword = props.getProperty("storePassword")
        }
    }
    buildTypes {'''
        assert 'buildTypes {' in t and 'signingConfigs.getByName("debug")' in t, 'unexpected build.gradle.kts'
        t = t.replace('    buildTypes {', block, 1)
        t = t.replace('signingConfigs.getByName("debug")', 'signingConfigs.getByName("release")', 1)
        t = 'import java.io.FileInputStream\nimport java.util.Properties\n\n' + t
        open(kts, 'w', encoding='utf-8').write(t)
    else:
        t = open(gr, encoding='utf-8').read()
        block = '''    signingConfigs {
        release {
            def props = new java.util.Properties()
            def kf = rootProject.file("key.properties")
            if (kf.exists()) { props.load(new java.io.FileInputStream(kf)) }
            keyAlias props['keyAlias']
            keyPassword props['keyPassword']
            storeFile props['storeFile'] ? file(props['storeFile']) : null
            storePassword props['storePassword']
        }
    }
    buildTypes {'''
        assert 'buildTypes {' in t and 'signingConfigs.debug' in t, 'unexpected build.gradle'
        t = t.replace('    buildTypes {', block, 1)
        t = t.replace('signingConfigs.debug', 'signingConfigs.release', 1)
        open(gr, 'w', encoding='utf-8').write(t)
    print('release signing enabled')
else:
    print('NO KEYSTORE: building with debug key (not for stores)')

# --- R8: ML Kit needs its classes kept; also try to switch minify off for release
open('android/app/proguard-rules.pro', 'w', encoding='utf-8').write(
    '-dontwarn com.google.mlkit.vision.text.chinese.**\n'
    '-dontwarn com.google.mlkit.vision.text.devanagari.**\n'
    '-dontwarn com.google.mlkit.vision.text.japanese.**\n'
    '-dontwarn com.google.mlkit.vision.text.korean.**\n'
    '-dontwarn com.google.android.play.core.**\n'
    '-dontwarn io.flutter.embedding.**\n'
    '-keep class com.google.mlkit.** { *; }\n'
    '-keep class com.google.android.gms.internal.mlkit_** { *; }\n'
    '-keep class com.google_mlkit_** { *; }\n'
    '-keep class * implements com.google.firebase.components.ComponentRegistrar\n')
for f, kts in (('android/app/build.gradle.kts', True), ('android/app/build.gradle', False)):
    if os.path.exists(f):
        t = open(f, encoding='utf-8').read()
        i = t.index('buildTypes {')
        head, tail = t[:i], t[i:]
        tail = re.sub(r'\n[ \t]*(isMinifyEnabled|isShrinkResources|minifyEnabled|shrinkResources)\b[^\n]*', '', tail)
        j = tail.index('release {') + len('release {')
        if kts:
            ins = '\n            isMinifyEnabled = false\n            isShrinkResources = false\n            proguardFiles("proguard-rules.pro")'
        else:
            ins = "\n            minifyEnabled false\n            shrinkResources false\n            proguardFiles 'proguard-rules.pro'"
        tail = tail[:j] + ins + tail[j:]
        open(f, 'w', encoding='utf-8').write(head + tail)
        print('release minify disabled + proguard rules in', f)
        break

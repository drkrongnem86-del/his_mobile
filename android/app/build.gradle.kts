import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// v3.0.118: Load release keystore từ key.properties (stable signing, cài đè được lên bản cũ)
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) {
        load(FileInputStream(f))
    }
}

android {
    namespace = "com.drnem.ccdk.his_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.drnem.ccdk.his_mobile"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        // v3.0.164: ARM64 only (Samsung A17) - gọn nhẹ cho máy BS
        // v3.0.172-fix: Dùng splits.abi (không phải ndk.abiFilters) để tương thích với
        //   `flutter build apk --target-platform android-arm64 --split-per-abi` trên CI.
        //   Gradle conflict nếu set cả 2: "Conflicting configuration : 'arm64-v8a' in ndk
        //   abiFilters cannot be present when splits abi filters are set"
    }

    // v3.0.118: Custom signing config cho release (stable keystore - không bị thay đổi như debug.keystore)
    signingConfigs {
        create("release") {
            if (keystoreProperties.getProperty("storeFile") != null) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // v3.0.76: disable minify for openvpn_flutter (some symbols stripped by Play)
            isMinifyEnabled = false
            isShrinkResources = false
            // v3.0.118: Dùng stable release keystore (fix lỗi "App not installed" khi cài đè bản cũ)
            signingConfig = if (keystoreProperties.getProperty("storeFile") != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // v3.0.76: openvpn_flutter cần legacy packaging cho jniLibs
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    // v3.0.76: openvpn_flutter yêu cầu
    lint {
        disable += "InvalidPackage"
        checkReleaseBuilds = false
    }

    // v3.0.76: Bundle config - không split theo ABI
    bundle {
        language {
            enableSplit = false
        }
        density {
            enableSplit = false
        }
        abi {
            enableSplit = false
        }
    }

    // v3.0.172-fix: ABI splits cho APK (chỉ arm64-v8a, dùng cho Samsung A17)
    // - splits.abi thay vì ndk.abiFilters để tương thích với flag `--split-per-abi` trên CI
    // - Cùng với --target-platform android-arm64 → chỉ tạo 1 file app-arm64-v8a-release.apk
    // - v3.0.173-fix: Chỉ enable khi build APK (assemble*), KHÔNG enable khi build AAB (bundle*)
    //   Lý do: AAB mặc định dùng 3 ABIs (armeabi-v7a + arm64-v8a + x86_64) → conflict với splits.abi
    splits {
        abi {
            isEnable = gradle.startParameter.taskNames.any { it.lowercase().contains("assemble") }
            reset()
            include("arm64-v8a")
            isUniversalApk = false
        }
    }
}

flutter {
    source = "../.."
}

// v3.0.24: VNPT SmartCA Android SDK (Deeplink)
// Docs: https://smartca.vnpt.vn/help/docs/sdks/deeplink/steps/android/
// v3.0.76: openvpn_flutter pulls in ics-openvpn automatically
dependencies {
    implementation("com.github.VNPTSmartCA:android-sdk:1.0.4")
}

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
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }
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

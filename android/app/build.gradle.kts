plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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
    }

    buildTypes {
        release {
            // v3.0.76: disable minify for openvpn_flutter (some symbols stripped by Play)
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("debug")
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

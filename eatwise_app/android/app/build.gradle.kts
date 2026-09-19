plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.eatwise.eatwise"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications 要求启用 core library desugaring。
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.eatwise.eatwise"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // 阶段 D：health 插件（Health Connect）要求 minSdk 26，与合规文档
        // 「Android 权限清单（API 26+，D-14）」口径一致。
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // CI 显式签名：CI_KEYSTORE_PATH 存在时用它建独立 signing config。
    // 背景：CI runner 上 debug 默认 keystore 查找不可靠（曾每次发版签名
    // 随机漂移），显式指定路径后产物签名才可复现。本地构建不设置该环境
    // 变量，仍回落 debug 签名。
    val ciKeystorePath = System.getenv("CI_KEYSTORE_PATH")

    signingConfigs {
        if (ciKeystorePath != null) {
            create("ciRelease") {
                storeFile = file(ciKeystorePath)
                storePassword = System.getenv("CI_KEYSTORE_PASSWORD") ?: "android"
                keyAlias = System.getenv("CI_KEY_ALIAS") ?: "androiddebugkey"
                keyPassword = System.getenv("CI_KEY_PASSWORD") ?: "android"
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig =
                if (ciKeystorePath != null) {
                    signingConfigs.getByName("ciRelease")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

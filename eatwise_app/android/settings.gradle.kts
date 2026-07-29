pluginManagement {
    val flutterSdkPath =
        run {
            // 注意：java.util.Properties.load() 按 ISO-8859-1 解码，
            // 当 Flutter SDK 路径含非 ASCII 字符（如中文目录「个人文件」）时会乱码，
            // 导致 includeBuild 找不到 flutter_tools/gradle。
            // 这里改为按 UTF-8 逐行解析 flutter.sdk。
            val localPropertiesFile = file("local.properties")
            val flutterSdkPath =
                localPropertiesFile
                    .readLines(Charsets.UTF_8)
                    .firstOrNull { it.startsWith("flutter.sdk=") }
                    ?.substringAfter("=")
                    ?.trim()
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // 国内构建加速：优先走阿里云镜像，源站兜底。
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/central")
        maven("https://maven.aliyun.com/repository/gradle-plugin")
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/central")
        maven("https://maven.aliyun.com/repository/public")
        google()
        mavenCentral()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")

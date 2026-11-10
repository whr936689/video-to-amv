plugins {
    id("com.android.application")
}

android {
    namespace = "com.example.amvconverter"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.example.amvconverter"
        minSdk = 19
        targetSdk = 28
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }
}

dependencies {
    implementation(files("libs/FFmpegAndroid-0.3.2.aar"))
}

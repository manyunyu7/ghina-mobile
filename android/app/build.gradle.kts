import java.util.Properties
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.zip.ZipFile

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing key lives outside the repo (~/.android-keystores, repo is public).
// android/key.properties points at it; without it, release builds fall back to debug keys.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "com.henryaugusta.ghina"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications needs java.time on old Android versions.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.henryaugusta.ghina"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures { buildConfig = true }

    flavorDimensions += "app"
    productFlavors {
        create("ghina") { dimension = "app" }
        create("ravel") {
            dimension = "app"
            applicationId = "com.henryaugusta.ravel"
        }
    }

    signingConfigs {
        if (keystoreProperties.containsKey("storeFile")) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // AppCompat LaunchTheme for local_auth (Kunci Kebiasaan) — see res/values/styles.xml.
    implementation("androidx.appcompat:appcompat:1.7.1")
}

// Flutter writes generated JNI libraries outside AGP's generated-source API.
// AGP 9 can retain an old incremental JNI merge even after app.so changes.
// Force a full JNI merge (downstream native merge/strip remain incremental).
tasks.configureEach {
    if (name.matches(Regex("merge.+ReleaseJniLibFolders"))) {
        outputs.upToDateWhen { false }
    }
}

// Stripping preserves the GNU build ID. Check the actual APK against the AOT
// compiler output, not the intermediate JNI copy that may itself be stale.
fun aotBuildId(bytes: ByteArray): List<Byte> {
    require(bytes.size > 64 && bytes.take(4) == listOf<Byte>(127, 69, 76, 70)) {
        "Expected ELF AOT library"
    }
    val elf64 = bytes[4].toInt() == 2
    val buffer = ByteBuffer.wrap(bytes).order(
        if (bytes[5].toInt() == 1) ByteOrder.LITTLE_ENDIAN else ByteOrder.BIG_ENDIAN
    )
    val headers = if (elf64) buffer.getLong(32).toInt() else buffer.getInt(28)
    val headerSize = buffer.getShort(if (elf64) 54 else 42).toInt() and 0xffff
    val count = buffer.getShort(if (elf64) 56 else 44).toInt() and 0xffff
    repeat(count) { index ->
        val header = headers + index * headerSize
        if (buffer.getInt(header) == 4) { // PT_NOTE
            var offset = if (elf64) buffer.getLong(header + 8).toInt() else buffer.getInt(header + 4)
            val end = offset + if (elf64) buffer.getLong(header + 32).toInt() else buffer.getInt(header + 16)
            while (offset + 12 <= end) {
                val nameSize = buffer.getInt(offset)
                val valueSize = buffer.getInt(offset + 4)
                val type = buffer.getInt(offset + 8)
                offset += 12
                val name = bytes.copyOfRange(offset, offset + nameSize)
                offset += (nameSize + 3) and -4
                val value = bytes.copyOfRange(offset, offset + valueSize)
                offset += (valueSize + 3) and -4
                if (type == 3 && name.contentEquals(byteArrayOf(71, 78, 85, 0))) {
                    return value.toList()
                }
            }
        }
    }
    error("Missing GNU build ID in Flutter AOT library")
}

listOf("ravel", "ghina").forEach { flavor ->
    val variant = "${flavor}Release"
    val suffix = "${flavor.replaceFirstChar { it.uppercase() }}Release"
    val verification = tasks.register("verify${suffix}Aot") {
        dependsOn("package$suffix")
        doLast {
            val output = layout.buildDirectory.dir("outputs/apk/$flavor/release").get().asFile
            val apks = output.walkTopDown().filter { it.extension == "apk" }.toList()
            check(apks.isNotEmpty()) { "No release APK found for AOT verification" }
            apks.forEach { apk ->
                ZipFile(apk).use { zip ->
                    val libraries = zip.entries().asSequence()
                        .filter { it.name.matches(Regex("lib/[^/]+/libapp.so")) }.toList()
                    check(libraries.isNotEmpty()) { "APK has no Flutter AOT library" }
                    libraries.forEach { entry ->
                        val abi = entry.name.split('/')[1]
                        val compiled = layout.buildDirectory.file(
                            "intermediates/flutter/$variant/$abi/app.so"
                        ).get().asFile
                        val actual = zip.getInputStream(entry).use { aotBuildId(it.readBytes()) }
                        check(actual == aotBuildId(compiled.readBytes())) {
                            "Stale Flutter AOT in ${apk.name} ($abi); refusing release"
                        }
                    }
                }
                logger.lifecycle("Verified current Flutter AOT in ${apk.name}")
            }
        }
    }
    tasks.matching { it.name == "assemble$suffix" }.configureEach {
        dependsOn(verification)
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

// Some plugins pin an older compileSdk than the one this project builds
// against — flutter_inappwebview_android asks for 34, and only android-36 is
// installed here. Compiling a library against a *newer* platform is safe, and
// it avoids requiring an SDK download the build environment may not be able to
// perform. Anything that already asked for a newer SDK is left alone.
//
// This must be registered before the evaluationDependsOn block below: that
// block evaluates :app immediately, and afterEvaluate cannot be registered on
// a project that is already evaluated. The hook also has to be afterEvaluate
// rather than plugins.withId, because a plugin sets its own compileSdk partway
// through its build script.
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android")
        if (android is com.android.build.gradle.BaseExtension) {
            val requested = android.compileSdkVersion?.removePrefix("android-")?.toIntOrNull()
            if (requested == null || requested < 36) {
                android.compileSdkVersion(36)
            }
        }
    }
}

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

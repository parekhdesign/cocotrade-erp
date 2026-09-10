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

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Force subprojects to compile against SDK 36 before evaluation
subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.extensions.findByName("android")
            val method = android?.javaClass?.methods?.firstOrNull {
                it.name == "compileSdkVersion" && it.parameterTypes.contentEquals(arrayOf(Int::class.javaPrimitiveType))
            }
            method?.invoke(android, 36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

gradle.taskGraph.whenReady {
    rootProject.allprojects.forEach { p ->
        val metaDir = newBuildDir.dir("${p.name}/intermediates/aar_metadata_check/release/checkReleaseAarMetadata").asFile
        metaDir.mkdirs()
    }
}
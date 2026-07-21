# [FIX R8] google_mlkit_text_recognition bundles only the Latin model; the
# japanese one is a real dependency in build.gradle.kts (MlkitOcrService
# switches script on the trip language), the others stay absent. The plugin's
# initialize() statically references the other language recognizers, which
# are optional Maven artifacts we do not ship; R8 strict mode (AGP 8+)
# fails the release build on those missing classes. They are never loaded
# at runtime by the latin/japanese scripts, so suppressing the check is safe.
# If another script is ever adopted, add its real dependency in
# build.gradle.kts and remove the matching -dontwarn line.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.korean.**

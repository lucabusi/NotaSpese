# [FIX R8] google_mlkit_text_recognition bundles only the Latin model
# (MlkitOcrService uses TextRecognitionScript.latin). The plugin's
# initialize() statically references the other language recognizers, which
# are optional Maven artifacts we do not ship; R8 strict mode (AGP 8+)
# fails the release build on those missing classes. They are never loaded
# at runtime with the latin script, so suppressing the check is safe.
# If a language-specific script is ever adopted (e.g. japanese, see the
# decision point in mlkit_ocr_service.dart), add its real dependency in
# build.gradle.kts and remove the matching -dontwarn line.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

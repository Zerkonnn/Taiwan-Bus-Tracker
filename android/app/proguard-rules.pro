# google_mlkit_text_recognition references every ML Kit script, but only
# Chinese (and Latin) are bundled - tell R8 the others are meant to be missing,
# otherwise release builds fail in minifyReleaseWithR8.
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# youtubedl-android ships no consumer rules (spec-v0.3 D-31).
# commons-compress unzips Python on first launch and creates zip extra
# fields by reflection; R8 otherwise strips them ("is not a concrete class").
-keep class com.yausername.** { *; }
-keep class org.apache.commons.compress.archivers.zip.** { *; }
# The yt-dlp updater parses GitHub's release JSON with Jackson.
-keep class com.fasterxml.jackson.** { *; }
-dontwarn com.fasterxml.jackson.**
-dontwarn org.apache.commons.compress.**

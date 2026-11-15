# youtubedl-android unpacks Python/FFmpeg with commons-compress, whose
# ExtraFieldUtils creates every ZIP extra-field class by reflection. Without
# this, R8 strips their constructors and the first unpack on a fresh install
# fails (ExceptionInInitializerError, then NoClassDefFoundError).
-keepclassmembers class org.apache.commons.compress.archivers.zip.** { public <init>(); }

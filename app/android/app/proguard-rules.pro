# Rules for the WebView kernel swap. Flutter already points R8 at this file
# (see FlutterPlugin.kt: "Fallback to android/app/proguard-rules.pro"), so
# creating it is all that is required — no Gradle change.
#
# Why the rules are needed at all: WebViewUpgrade hooks Android's WebView
# provider binders by reflection, and it ships no consumer rules of its own —
# the AAR's proguard.txt is empty. With R8 on, it renames the library's
# internals (WebViewUpgrade became Q2.e) and deletes classes it cannot see a
# direct reference to (WebViewUpdateServiceHook$1 was dropped outright).
#
# The failure mode is what makes this worth a comment: the build succeeds, the
# APK installs, and the hook silently does nothing on exactly the old devices
# it exists to help. Nothing else in the pipeline would notice.
-keep class com.norman.webviewup.** { *; }
-keepclassmembers class com.norman.webviewup.** { *; }

# The reflection layer is built out of runtime-visible annotations; R8 strips
# the attribute unless asked not to, and then the hook finds nothing to bind.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

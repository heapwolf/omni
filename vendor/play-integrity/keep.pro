# R8's root: the bridge, and what it reaches. Shrinking only: no
# optimizing and no renaming, and every attribute kept, so what's kept is
# Google's code as built, and javac can compile the bridge against it.
-keep class com.omni.OmniAttest { *; }
-keepattributes *
-dontoptimize
-dontobfuscate
